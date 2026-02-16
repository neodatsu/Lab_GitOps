# Lab_GitOps - Project Guidelines

## Environment
- **Machine** : MacBook Air M1, 16 Go RAM
- **Contrainte disque** : le projet ne doit **jamais dépasser 5 Go** au total (code, dépendances, données, images Docker, etc.)

## Règles strictes
- Avant d'ajouter une dépendance ou de générer des fichiers volumineux, vérifier l'espace utilisé avec `du -sh .`
- Privilégier les images Docker légères (Alpine, distroless, slim)
- Ne pas committer de fichiers binaires, datasets ou artefacts de build dans le repo
- Utiliser un `.gitignore` rigoureux pour exclure : `node_modules/`, `vendor/`, `.venv/`, `__pycache__/`, fichiers temporaires, logs, artefacts de build
- Nettoyer régulièrement les images et conteneurs Docker inutilisés (`docker system prune`)

## Stack technique

- **Runtime** : Docker Desktop
- **Kubernetes** : k3d (k3s dans Docker) — cluster `lab-gitops`
- **GitOps** : ArgoCD (manifest officiel)
- **Management** : Rancher UI (Helm chart `rancher-latest`)
- **Prérequis** : cert-manager (Helm chart `jetstack`)
- **CLI** : k3d, kubectl, helm (installés via Homebrew)

## Scripts

- `scripts/install.sh` : installe tout le lab (cluster + ArgoCD + Rancher)
- `scripts/uninstall.sh` : supprime le cluster et nettoie Docker

## Conventions

- Langue du code et des commits : anglais
- Documentation projet : français (sauf README technique si besoin)
- Commits courts et descriptifs, format conventionnel (feat, fix, docs, chore, etc.)
