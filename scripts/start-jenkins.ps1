$ErrorActionPreference = "Stop"

$JenkinsHome = "C:/jenkins-home"
$ComposeFile = "compose/jenkins-controller.yml"
$ContainerName = "petclinic-jenkins-controller"
$JenkinsUrl = "http://localhost:18080"

Write-Host "Checking Jenkins data directory: $JenkinsHome"
if (-not (Test-Path $JenkinsHome)) {
    Write-Host "Creating Jenkins data directory: $JenkinsHome"
    New-Item -ItemType Directory -Force -Path $JenkinsHome | Out-Null
}

Write-Host "Starting Jenkins controller using Docker Compose..."
docker compose -f $ComposeFile up -d

Write-Host "Waiting for Jenkins to start up and become ready..."
$Ready = $false
$Attempts = 0
$MaxAttempts = 30

while (-not $Ready -and $Attempts -lt $MaxAttempts) {
    try {
        $Response = Invoke-WebRequest -Uri "$JenkinsUrl/login" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            $Ready = $true
        }
    } catch {
        # Silent retry
    }
    if (-not $Ready) {
        $Attempts++
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 5
    }
}
Write-Host ""

if ($Ready) {
    Write-Host "`nJenkins is UP and running at: $JenkinsUrl"
    
    Write-Host "`nRetrieving Initial Jenkins Admin Password..."
    Start-Sleep -Seconds 3
    try {
        $AdminPassword = docker exec $ContainerName cat /var/jenkins_home/secrets/initialAdminPassword
        Write-Host "--------------------------------------------------------" -ForegroundColor Green
        Write-Host "YOUR INITIAL ADMIN PASSWORD:" -ForegroundColor Green
        Write-Host $AdminPassword -ForegroundColor Yellow
        Write-Host "--------------------------------------------------------" -ForegroundColor Green
    } catch {
        Write-Host "Could not retrieve password automatically. It will be printed inside the Jenkins logs shortly." -ForegroundColor Red
    }
} else {
    Write-Host "`nJenkins startup timed out. Please check container status: docker ps" -ForegroundColor Red
}
