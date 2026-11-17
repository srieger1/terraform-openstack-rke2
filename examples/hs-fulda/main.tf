###########################################################
#
# Author: Lucas Immanuel Nickel, Sebastian Rieger
# Date: November 16, 2024
# Remark: This code is not production ready as it disables certificate checks by default
# and sets kubeconfig file access to 644 instead of default 600
#
###########################################################

locals {
  ###########################################################
  #
  # Config parameters
  #
  # also add terraform.tfvars, see README at:
  #
  # https://github.com/srieger1/terraform-openstack-rke2/tree/hsfulda-example-2023-10/examples/hs-fulda
  #
  ###########################################################

  insecure = false
  # /v3/ is required for now to prevent gophercloud (which openstack terraform provider is based
  # on, to request the version from keystone, ending up in using our VIP instead of
  # private-cloud.informatik.hs-fulda.de and the valid cert, from keystone public endpoint
  auth_url         = "https://private-cloud.informatik.hs-fulda.de:5000/v3/"
  object_store_url = "https://s3.private-cloud.informatik.hs-fulda.de"
  region           = "RegionOne"

  cluster_name = lower("${var.project}-k8s")
  # v6 targets Ubuntu 26.04 and RKE2 v1.37; adjust to the image available in your cloud
  image_name       = "ubuntu-26.04-resolute-server-cloud-image-amd64"
  flavor_name      = "m1.medium"
  system_user      = "ubuntu"
  floating_ip_pool = "ext_net"
  #ssh_pubkey_file  = "~/.ssh/id_rsa.pub"
  ssh_pubkey_file = "~/.ssh/id_ed25519.pub"
  dns_server      = "10.33.16.100"
  # v6 supports RKE2 v1.37 only
  rke2_version = "v1.37.1+rke2r1"

  ###########################################################
}

module "rke2" {
  # use module source from zifeo in terraform registry:
  # source = "zifeo/rke2/openstack"
  # version = ""

  # use module source from our fork's hsfulda-example branch
  #source = "git::https://github.com/srieger1/terraform-openstack-rke2.git?ref=hsfulda-example"

  # v6 has no module-level insecure; TLS handling lives in the openstack provider block below
  # use module source locally from this repo (../.. dir from this example)
  source = "../.."

  # must be true for single server cluster or
  # only on the first run for high-availability cluster
  # v6: a single server always starts the cluster alone, no bootstrap needed
  name                = local.cluster_name
  ssh_authorized_keys = [local.ssh_pubkey_file]
  floating_pool       = local.floating_ip_pool
  # should be restricted to secure bastion
  rules_ssh_cidr = ["0.0.0.0/0"]
  rules_k8s_cidr = ["0.0.0.0/0"]

  servers = [{
    name               = "controller"
    flavor_name        = local.flavor_name
    image_name         = local.image_name
    system_user        = local.system_user
    boot_volume_size   = 6
    rke2_version       = local.rke2_version
    rke2_volume_size   = 8
    rke2_volume_device = "/dev/vdb"
    # https://docs.rke2.io/install/install_options/server_config/
    rke2_config = <<EOF
# https://docs.rke2.io/install/install_options/server_config/
write-kubeconfig-mode: "0644"
EOF
  }]

  agents = [
    {
      name        = "worker"
      nodes_count = 1
      #nodes_count = 3
      flavor_name = local.flavor_name
      image_name  = local.image_name
      # if you want a fixed version
      # image_uuid = "..."
      system_user        = local.system_user
      boot_volume_size   = 6
      rke2_version       = local.rke2_version
      rke2_volume_size   = 8
      rke2_volume_device = "/dev/vdb"
    }
  ]

  backup_schedule  = "0 6 1 * *" # once a month
  backup_retention = 20

  kube_apiserver_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube_scheduler_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube_controller_manager_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  etcd_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }
  #vip_interface       = "ens2"
  dns_nameservers4 = [local.dns_server]
  # enable automatically agent removal of the cluster (wait max for 30s)
  agent_removal_timeout = "30s"
  # rewrite kubeconfig
  ff_write_kubeconfig = true
  # deploy etcd backup
  etcd_snapshots_in_object_store = true
  # wait for the cluster to be ready when deploying
  ff_wait_ready = true

  identity_endpoint     = local.auth_url
  object_store_endpoint = local.object_store_url

  registries = {
    mirrors = {
      "*" : {
        endpoint = [
          "https://harbor.cs.hs-fulda.de"
        ]
      }
    }
  }
}

variable "project" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type = string
}

output "floating_ip" {
  value = module.rke2.external_ip
}

provider "openstack" {
  # change to ca_path
  insecure    = local.insecure
  tenant_name = var.project
  user_name   = var.username
  # checkov:skip=CKV_OPENSTACK_1
  password = var.password
  auth_url = local.auth_url
  region   = local.region

  # required as long as out keystone public endpoint still used a VIP as this
  # bypasses nginx reverse proxy and uses vault ca internal cert
  endpoint_overrides = {
    "identity" = local.auth_url
  }
}

terraform {
  # v6 module needs >= 1.10 (removed blocks, random_password for the servers' token)
  required_version = ">= 1.10.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }
}
