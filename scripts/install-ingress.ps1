$ErrorActionPreference = "Stop"

Write-Host "Installing NGINX Ingress Controller for kind..."

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

Write-Host "Waiting for ingress-nginx controller to become ready..."

kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=180s

Write-Host "NGINX Ingress Controller is ready."
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx