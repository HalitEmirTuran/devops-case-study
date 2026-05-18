$ErrorActionPreference = "Stop"

$JenkinsUrl = "http://localhost:18080"
$AgentName = "windows-docker-agent"
$AgentDir = "C:\jenkins-agent"
$JarPath = "$AgentDir\agent.jar"
$SecretFile = "secrets/jenkins-agent.secret"

# Ensure secrets directory exists
if (-not (Test-Path "secrets")) {
    New-Item -ItemType Directory -Force -Path "secrets" | Out-Null
}

# Ensure agent directory exists
if (-not (Test-Path $AgentDir)) {
    Write-Host "Creating agent directory: $AgentDir"
    New-Item -ItemType Directory -Force -Path $AgentDir | Out-Null
}

# Download agent.jar if missing
if (-not (Test-Path $JarPath)) {
    Write-Host "Downloading agent.jar from Jenkins Controller..."
    try {
        Invoke-WebRequest -Uri "$JenkinsUrl/jnlpJars/agent.jar" -OutFile $JarPath -UseBasicParsing
        Write-Host "agent.jar downloaded successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to download agent.jar. Is Jenkins Controller running at $JenkinsUrl?" -ForegroundColor Red
        exit 1
    }
}

# Retrieve or ask for Secret Key
$Secret = ""
if (Test-Path $SecretFile) {
    $Secret = (Get-Content $SecretFile).Trim()
    Write-Host "Found cached Jenkins Agent Secret in: $SecretFile"
} else {
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "First-time Jenkins Agent Setup" -ForegroundColor Cyan
    Write-Host "Please enter the Inbound Agent Secret from your Jenkins UI" -ForegroundColor Cyan
    Write-Host " (Manage Jenkins -> Nodes -> $AgentName)" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    $Secret = Read-Host "Enter Secret Key"
    if ([string]::IsNullOrWhiteSpace($Secret)) {
        Write-Host "Secret key cannot be empty." -ForegroundColor Red
        exit 1
    }
    $Secret = $Secret.Trim()
    Set-Content -Path $SecretFile -Value $Secret
    Write-Host "Saved agent secret to: $SecretFile (gitignored)" -ForegroundColor Green
}

Write-Host "`nStarting Jenkins Agent..."
Write-Host "Connecting to $JenkinsUrl via WebSocket..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop the agent." -ForegroundColor Gray

# Change directory to C:\jenkins-agent and run the jar
Push-Location $AgentDir
try {
    java -jar agent.jar -url $JenkinsUrl/ -secret $Secret -name $AgentName -webSocket -workDir $AgentDir
} finally {
    Pop-Location
}
