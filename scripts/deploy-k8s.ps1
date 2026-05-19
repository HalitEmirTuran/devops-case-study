$ErrorActionPreference = "Stop"

$Namespace = "petclinic-prod"

Write-Host "Applying namespace..."

kubectl apply -f k8s/base/namespace.yaml

Write-Host "Validating local secret files..."

$RequiredSecretFiles = @(
    "secrets/postgres.db",
    "secrets/postgres.user",
    "secrets/postgres.password"
)

foreach ($File in $RequiredSecretFiles) {
    if (!(Test-Path $File)) {
        throw "Missing secret file: $File. Run .\scripts\init-secrets.ps1 first."
    }
}

Write-Host "Creating AND/or updating Kubernetes Secret..."

kubectl create secret generic petclinic-db-secret `
  --namespace $Namespace `
  --from-file=postgres.db=secrets/postgres.db `
  --from-file=postgres.user=secrets/postgres.user `
  --from-file=postgres.password=secrets/postgres.password `
  --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Applying Kubernetes manifests with Kustomize..."

kubectl apply -k k8s/base

Write-Host "Waiting for PostgreSQL pod to become ready..."

kubectl wait --for=condition=ready pod `
  -l app.kubernetes.io/name=postgres `
  -n $Namespace `
  --timeout=180s

# Sync the password inside PostgreSQL to match the current secret.
# PostgreSQL only reads POSTGRES_PASSWORD_FILE during first-time init.
# On subsequent runs the data volume already exists, so the DB keeps
# the old password. This ALTER USER command keeps them in sync.
Write-Host "Syncing database credentials with current secret..."

$DbUser = Get-Content "secrets/postgres.user" -Raw
$DbPassword = Get-Content "secrets/postgres.password" -Raw
$DbName = Get-Content "secrets/postgres.db" -Raw

kubectl exec postgres-0 -n $Namespace -- `
  psql -U $DbUser -d $DbName -c "ALTER USER $DbUser WITH PASSWORD '$DbPassword';"

Write-Host "Database credentials synced." -ForegroundColor Green

# Restart the app deployment so pods pick up the new secret values.
Write-Host "Restarting application pods to load updated credentials..."

kubectl rollout restart deployment/petclinic-app -n $Namespace

Write-Host "Waiting for Petclinic deployment rollout..."

kubectl rollout status deployment/petclinic-app `
  -n $Namespace `
  --timeout=180s

Write-Host "Deployment completed."

Write-Host "Current resources:"
kubectl get pods,svc,statefulset,deployment,hpa,pdb -n $Namespace