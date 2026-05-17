param(
    [string]$Registry = "localhost:5001",
    [string]$ImageName = "petclinic-app",
    [string]$ImageTag = "v1.0.1-local"
)

$ErrorActionPreference = "Stop"

$FullImageName = "${Registry}/${ImageName}:${ImageTag}"

Write-Host "Building Docker image: $FullImageName"

docker build -t $FullImageName -f docker/Dockerfile .

Write-Host "Pushing Docker image to local registry: $FullImageName"

docker push $FullImageName

Write-Host "Image build and push completed: $FullImageName"