# Define the user and floating IP here
$user = "CloudServ17"
$floatingIP = "10.32.6.6"

winget install -e --id MikeFarah.yq
winget install -e --id Kubernetes.kubectl
winget install -e --id Helm.Helm

$server = "ubuntu@${floatingIP}"
$remoteFilePath = "/etc/rancher/rke2/rke2.yaml"
$localFilePath = ".\${user}.rke2.yaml"

# forget possibly previously stored host key
$sshKeygenCommand = "ssh-keygen -R ${floatingIP}"
Write-Host "Removing cached host key if it exists..."
Invoke-Expression ${sshKeygenCommand}

# Copying rke2.yaml kubeconfig file using SCP
$scpCommand = "scp ${server}:${remoteFilePath} ${localFilePath}"
Write-Host "Copying file from the instance using SCP..."
Invoke-Expression ${scpCommand}

Write-Host "Modifying the file using yq to use cluster and user name..."
$yqCommand = "yq eval --inplace '.clusters[0].name = ""${user}-cluster""' ${localFilePath}"
Invoke-Expression ${yqCommand}
$yqCommand = "yq eval --inplace '.clusters[0].cluster.server = ""https://${floatingIP}:6443""' ${localFilePath}"
Invoke-Expression ${yqCommand}
$yqCommand = "yq eval --inplace '.users[0].name = ""${user}-user""' ${localFilePath}"
Invoke-Expression ${yqCommand}
$yqCommand = "yq eval --inplace '.contexts[0].context.cluster = ""${user}-cluster""' ${localFilePath}"
Invoke-Expression ${yqCommand}
$yqCommand = "yq eval --inplace '.contexts[0].context.user = ""${user}-user""' ${localFilePath}"
Invoke-Expression ${yqCommand}
$yqCommand = "yq eval --inplace '.contexts[0].name = ""${user}""' ${localFilePath}"
Invoke-Expression ${yqCommand}:
$yqCommand = "yq eval --inplace '.current-context = ""${user}""' ${localFilePath}"
Invoke-Expression ${yqCommand}

Write-Host "Setting environment variable KUBECONFIG..."
Set-Variable -Name "KUBECONFIG" -Visibility Public -Value ".\CloudServ17.rke2.yaml"