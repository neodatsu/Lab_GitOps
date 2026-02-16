#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="lab-gitops"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
K3D_CONFIG="$PROJECT_DIR/k3d/cluster-config.yaml"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ──────────────────────────────────────────────
# 1. Check Docker is running
# ──────────────────────────────────────────────
info "Checking Docker..."
if ! docker info &>/dev/null; then
  error "Docker is not running. Start Docker Desktop first."
fi

# ──────────────────────────────────────────────
# 2. Install CLI tools via Homebrew if missing
# ──────────────────────────────────────────────
install_if_missing() {
  local cmd="$1"
  local formula="${2:-$1}"
  if ! command -v "$cmd" &>/dev/null; then
    info "Installing $cmd..."
    brew install "$formula"
  else
    info "$cmd is already installed."
  fi
}

if ! command -v brew &>/dev/null; then
  error "Homebrew is required. Install it from https://brew.sh"
fi

install_if_missing k3d
install_if_missing kubectl kubernetes-cli
install_if_missing helm

# ──────────────────────────────────────────────
# 3. Create k3d cluster
# ──────────────────────────────────────────────
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  warn "Cluster '$CLUSTER_NAME' already exists. Skipping creation."
else
  info "Creating k3d cluster '$CLUSTER_NAME'..."
  k3d cluster create --config "$K3D_CONFIG"
fi

info "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# ──────────────────────────────────────────────
# 4. Install ArgoCD
# ──────────────────────────────────────────────
info "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# Run ArgoCD server in insecure mode (TLS terminated by Traefik)
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type merge -p '{"data": {"server.insecure": "true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# Create Ingress for ArgoCD
kubectl apply -f - <<'ARGOCD_INGRESS'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: argocd.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
ARGOCD_INGRESS

# ──────────────────────────────────────────────
# 5. Install cert-manager (required by Rancher)
# ──────────────────────────────────────────────
info "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update jetstack

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait --timeout 300s

# ──────────────────────────────────────────────
# 6. Install Rancher
# ──────────────────────────────────────────────
info "Installing Rancher..."
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update
helm repo update rancher-latest

helm upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.localhost \
  --set bootstrapPassword=admin \
  --set replicas=1 \
  --set ingress.tls.source=rancher \
  --wait --timeout 600s

# ──────────────────────────────────────────────
# 7. Summary
# ──────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "not yet available")

echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Lab GitOps — Installation complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ArgoCD:"
echo -e "    URL:      http://argocd.localhost:8080"
echo -e "    User:     admin"
echo -e "    Password: ${ARGOCD_PASSWORD}"
echo ""
echo -e "  Rancher:"
echo -e "    URL:      https://rancher.localhost:8443"
echo -e "    Password: admin (bootstrap)"
echo -e "    Note:     accept the self-signed certificate warning in your browser"
echo ""
echo -e "  Useful commands:"
echo -e "    kubectl get nodes"
echo -e "    kubectl get pods -n argocd"
echo -e "    kubectl get pods -n cattle-system"
echo -e "    k3d cluster list"
echo ""
echo -e "  Disk usage:"
du -sh "$PROJECT_DIR" 2>/dev/null || true
echo ""
