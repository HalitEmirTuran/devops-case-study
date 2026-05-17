$ErrorActionPreference = "Stop"

$ClusterName = "petclinic-prod"
$RegistryName = "kind-registry"
$RegistryPort = "5001"
$KindConfig = "k8s/kind-cluster.yaml"

Write-Host "Checking local Docker registry..."

$RegistryExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $RegistryName }

if ($RegistryExists) {
    $RegistryRunning = docker inspect -f "{{.State.Running}}" $RegistryName

    if ($RegistryRunning -ne "true") {
        Write-Host "Starting existing registry container..."
        docker start $RegistryName
    } else {
        Write-Host "Local registry is already running."
    }
} else {
    Write-Host "Creating local registry on localhost:$RegistryPort..."
    docker run -d `
      --restart=always `
      -p "127.0.0.1:${RegistryPort}:5000" `
      --name $RegistryName `
      registry:2
}

Write-Host "Checking kind cluster: $ClusterName"

$ExistingClusters = kind get clusters 2>$null

if ($ExistingClusters -contains $ClusterName) {
    Write-Host "Kind cluster '$ClusterName' already exists. Skipping creation."
} else {
    Write-Host "Creating kind cluster '$ClusterName'..."
    kind create cluster --config $KindConfig
}

Write-Host "Connecting registry to kind network..."

$RegistryNetwork = docker inspect -f "{{json .NetworkSettings.Networks.kind}}" $RegistryName 2>$null

if ($RegistryNetwork -eq "null" -or [string]::IsNullOrWhiteSpace($RegistryNetwork)) {
    docker network connect kind $RegistryName
} else {
    Write-Host "Registry is already connected to kind network."
}

Write-Host "Configuring kind nodes to use local registry..."

$Nodes = kind get nodes --name $ClusterName

foreach ($Node in $Nodes) {
    $RegistryDir = "/etc/containerd/certs.d/localhost:${RegistryPort}"

    docker exec $Node mkdir -p $RegistryDir

    $HostsToml = @"
[host."http://${RegistryName}:5000"]
"@

    $HostsToml | docker exec -i $Node sh -c "cat > ${RegistryDir}/hosts.toml"
}

Write-Host "Documenting local registry inside the cluster..."

@"
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${RegistryPort}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
"@ | kubectl apply -f -

Write-Host "Cluster and local registry are ready."
Write-Host "Registry: localhost:$RegistryPort"
Write-Host "Cluster: $ClusterName"

kubectl get nodes