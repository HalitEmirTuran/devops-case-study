$ErrorActionPreference = "Stop"

$ComposeFile = "compose/jenkins-controller.yml"

Write-Host "Stopping and removing Jenkins controller container..."
docker compose -f $ComposeFile down

Write-Host "Jenkins container stopped successfully." -ForegroundColor Green
