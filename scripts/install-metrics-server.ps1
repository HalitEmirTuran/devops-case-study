$ErrorActionPreference = "Stop"

Write-Host "Installing Metrics Server..."

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

Write-Host "Configuring Metrics Server for local kind cluster..."

kubectl patch deployment metrics-server `
  -n kube-system `
  --type='json' `
  -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/args",
      "value": [
        "--cert-dir=/tmp",
        "--secure-port=10250",
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
        "--kubelet-use-node-status-port",
        "--metric-resolution=15s",
        "--kubelet-insecure-tls"
      ]
    }
  ]'

Write-Host "Waiting for Metrics Server rollout..."

kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s

Write-Host "Metrics Server installed successfully."

kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl top nodes