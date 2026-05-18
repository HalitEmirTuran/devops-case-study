$ErrorActionPreference = "Stop"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "      SPRING PETCLINIC DEVOPS STACK BOOTSTRAPPER" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "This script will fully orchestrate the local infrastructure,"
Write-Host "configure security policies, compile the application,"
Write-Host "and deploy the stack to Kind Kubernetes."
Write-Host "========================================================" -ForegroundColor Cyan

# Step 1: Initialize local random secrets
Write-Host "`n[STEP 1/6] Initializing local secrets..." -ForegroundColor Green
.\scripts\init-secrets.ps1

# Step 2: Spin up Kind cluster with local registry
Write-Host "`n[STEP 2/6] Provisioning Kind Kubernetes Cluster and Registry..." -ForegroundColor Green
.\scripts\create-cluster-with-registry.ps1

# Step 3: Install platform add-ons
Write-Host "`n[STEP 3/6] Installing Ingress Controller and Metrics Server..." -ForegroundColor Green
Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Gray
.\scripts\install-ingress.ps1
Write-Host "Installing Metrics Server..." -ForegroundColor Gray
.\scripts\install-metrics-server.ps1

# Step 4: Build application image
Write-Host "`n[STEP 4/6] Building Spring Petclinic multi-stage Docker image..." -ForegroundColor Green
.\scripts\build-image.ps1

# Step 5: Deploy application and database to Kubernetes
Write-Host "`n[STEP 5/6] Deploying PostgreSQL StatefulSet and Spring Application..." -ForegroundColor Green
.\scripts\deploy-k8s.ps1

# Step 6: Offer to start Jenkins
Write-Host "`n[STEP 6/6] Pipeline Automation Option" -ForegroundColor Green
$StartJenkinsChoice = Read-Host "Do you want to start the local Jenkins CI/CD Controller and Agent? (y/n)"
if ($StartJenkinsChoice.Trim().ToLower() -eq 'y') {
    Write-Host "`nStarting Jenkins Controller..." -ForegroundColor Yellow
    .\scripts\start-jenkins.ps1
    
    Write-Host "`nStarting Jenkins Agent..." -ForegroundColor Yellow
    Write-Host "Please note: If this is the first execution, you will be prompted for your agent secret." -ForegroundColor Gray
    .\scripts\start-jenkins-agent.ps1
} else {
    Write-Host "`nSkipping Jenkins startup. You can start it later using: .\scripts\start-jenkins.ps1" -ForegroundColor Gray
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "      SUCCESS: DEVOPS CASE STUDY STACK IS FULLY LIVE!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Access URLs:" -ForegroundColor Gray
Write-Host "  - Petclinic Application (Ingress): http://localhost:8080" -ForegroundColor Yellow
Write-Host "  - Petclinic Application (Direct NodePort): http://localhost:30080" -ForegroundColor Yellow
if ($StartJenkinsChoice.Trim().ToLower() -eq 'y') {
    Write-Host "  - Jenkins CI/CD Controller: http://localhost:18080" -ForegroundColor Yellow
}
Write-Host "========================================================" -ForegroundColor Green
