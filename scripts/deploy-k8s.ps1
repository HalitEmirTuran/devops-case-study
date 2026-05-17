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

Write-Host "Creating or updating Kubernetes Secret..."

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

Write-Host "Waiting for Petclinic deployment rollout..."

kubectl rollout status deployment/petclinic-app `
  -n $Namespace `
  --timeout=180s

Write-Host "Deployment completed."

Write-Host "Current resources:"
kubectl get pods,svc,statefulset,deployment,hpa,pdb -n $Namespace