$ErrorActionPreference = "Stop"

$ClusterName = "petclinic-prod"
$KindConfig = "k8s/kind-cluster.yaml"

Write-Host "Checking kind cluster: $ClusterName"

$ExistingClusters = kind get clusters

if ($ExistingClusters -contains $ClusterName) {
    Write-Host "Kind cluster '$ClusterName' already exists. Skipping creation."
} else {
    Write-Host "Creating kind cluster '$ClusterName'..."
    kind create cluster --config $KindConfig
}

Write-Host "Cluster info:"
kubectl cluster-info

Write-Host "Nodes:"
kubectl get nodes