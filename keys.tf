locals {
  ssh_authorized_keys_loaded = [for key in var.ssh_authorized_keys : startswith(key, "/") || startswith(key, "~") ? file(key) : key]
  ssh_authorized_key         = local.ssh_authorized_keys_loaded[0]
  ssh_authorized_keys        = slice(local.ssh_authorized_keys_loaded, 1, length(local.ssh_authorized_keys_loaded))

  # Unix home paths start with "/", Windows ones with a drive letter
  is_windows = substr(pathexpand("~"), 0, 1) != "/"

  kubeconfig_cmd_unix = <<EOF
  ssh-keygen -R ${local.external_ip} >/dev/null 2>&1
  until rsync -e "ssh -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" --rsync-path="sudo rsync" ${var.servers[0].system_user}@${local.external_ip}:/etc/rancher/rke2/rke2.yaml rke2.yaml >/dev/null 2>&1; do echo Wait rke2.yaml generation && sleep 5; done \
  && chmod go-r rke2.yaml \
  && yq eval --inplace '.clusters[0].name = "${var.name}-cluster"' rke2.yaml \
  && yq eval --inplace '.clusters[0].cluster.server = "https://${local.external_ip}:6443"' rke2.yaml \
  && yq eval --inplace '.users[0].name = "${var.name}-user"' rke2.yaml \
  && yq eval --inplace '.contexts[0].context.cluster = "${var.name}-cluster"' rke2.yaml \
  && yq eval --inplace '.contexts[0].context.user = "${var.name}-user"' rke2.yaml \
  && yq eval --inplace '.contexts[0].name = "${var.name}"' rke2.yaml \
  && yq eval --inplace '.current-context = "${var.name}"' rke2.yaml \
  && mv rke2.yaml ${var.name}.rke2.yaml
  EOF

  kubeconfig_cmd_windows = <<EOF
  ssh-keygen -R ${local.external_ip} 2>$null | Out-Null
  $opts = @('-o','ConnectTimeout=5','-o','UserKnownHostsFile=NUL','-o','StrictHostKeyChecking=no')
  $remote = '${var.servers[0].system_user}@${local.external_ip}'

  do {
    ssh @opts $remote 'sudo cp /etc/rancher/rke2/rke2.yaml /tmp/rke2.yaml && sudo chown ${var.servers[0].system_user} /tmp/rke2.yaml' 2>$null
    if ($LASTEXITCODE -eq 0) { scp @opts "$($remote):/tmp/rke2.yaml" rke2.yaml 2>$null }
    if ($LASTEXITCODE -ne 0) { Write-Host 'Wait rke2.yaml generation'; Start-Sleep 5 }
  } while ($LASTEXITCODE -ne 0)

  ssh @opts $remote 'rm -f /tmp/rke2.yaml' 2>$null

  $exprs = @(
    '.clusters[0].name = \"${var.name}-cluster\"',
    '.clusters[0].cluster.server = \"https://${local.external_ip}:6443\"',
    '.users[0].name = \"${var.name}-user\"',
    '.contexts[0].context.cluster = \"${var.name}-cluster\"',
    '.contexts[0].context.user = \"${var.name}-user\"',
    '.contexts[0].name = \"${var.name}\"',
    '.current-context = \"${var.name}\"'
  )
  foreach ($e in $exprs) {
    yq eval --inplace $e rke2.yaml
    if ($LASTEXITCODE -ne 0) { exit 1 }
  }

  Move-Item -Force rke2.yaml ${var.name}.rke2.yaml
  EOF
}

resource "random_string" "rke2_token" {
  length = 64
}

resource "openstack_compute_keypair_v2" "key" {
  name       = "${var.name}-key"
  public_key = local.ssh_authorized_key
}

resource "null_resource" "write_kubeconfig" {
  count = var.ff_write_kubeconfig && var.rules_ssh_cidr != null ? 1 : 0

  triggers = {
    servers = join(",", flatten([for server in module.servers : server.ids]))
  }

  depends_on = [
    module.servers[0].id
  ]

  connection {
    host  = local.external_ip
    user  = var.servers[0].system_user
    agent = true
  }

  provisioner "local-exec" {
    interpreter = local.is_windows ? ["powershell", "-NoProfile", "-Command"] : ["/bin/sh", "-c"]
    command     = local.is_windows ? local.kubeconfig_cmd_windows : local.kubeconfig_cmd_unix
  }
}

resource "openstack_identity_application_credential_v3" "rke2" {
  name = "${var.name}-credentials"
}

