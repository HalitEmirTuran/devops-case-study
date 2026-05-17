param(
    [switch]$DeleteCluster
)

$ErrorActionPreference = "Stop"

$Namespace = "petclinic-prod"
$ClusterName = "petclinic-prod"

Write-Host "Deleting namespace: $Namespace"

kubectl delete namespace $Namespace --ignore-not-found=true

if ($DeleteCluster) {
    Write-Host "Deleting kind cluster: $ClusterName"
    kind delete cluster --name $ClusterName
} else {
    Write-Host "Namespace deleted. Kind cluster kept."
    Write-Host "To delete the cluster as well, run:"
    Write-Host ".\scripts\destroy-k8s.ps1 -DeleteCluster"
}