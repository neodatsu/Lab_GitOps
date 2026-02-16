#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="lab-gitops"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${YELLOW}This will delete the k3d cluster '$CLUSTER_NAME' and all its data.${NC}"
read -r -p "Are you sure? [y/N] " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
  info "Aborted."
  exit 0
fi

# ──────────────────────────────────────────────
# 1. Delete k3d cluster
# ──────────────────────────────────────────────
if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  info "Deleting k3d cluster '$CLUSTER_NAME'..."
  k3d cluster delete "$CLUSTER_NAME"
else
  warn "Cluster '$CLUSTER_NAME' not found. Skipping."
fi

# ──────────────────────────────────────────────
# 2. Clean up Docker resources
# ──────────────────────────────────────────────
info "Cleaning up orphan Docker volumes and networks..."
docker volume prune -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true

# ──────────────────────────────────────────────
# 3. Confirmation
# ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Lab GitOps — Uninstall complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Cluster '$CLUSTER_NAME' has been deleted."
echo -e "  Docker volumes and networks have been pruned."
echo ""
echo -e "  To also remove CLI tools:"
echo -e "    brew uninstall k3d kubectl helm"
echo ""
