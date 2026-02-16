#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
size()  { echo -e "${CYAN}[SIZE]${NC} $1"; }
skip()  { echo -e "       $1 — absent, skip"; }
sep()   { echo ""; echo -e "${CYAN}────────────────────────────────────────────${NC}"; }

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  warn "Mode dry-run : aucune suppression ne sera effectuée."
  echo ""
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Mac Cleanup — Analyse & Nettoyage exhaustif${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""

info "Espace disque actuel :"
df -h / | tail -1 | awk '{printf "  Total: %s | Utilisé: %s | Libre: %s (%s utilisé)\n", $2, $3, $4, $5}'

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
TOTAL_FREED=0

check_and_clean() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    local sz bytes
    sz=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "0")
    bytes=$(du -sk "$path" 2>/dev/null | cut -f1 || echo "0")
    bytes="${bytes:-0}"
    if [[ "$bytes" -gt 0 ]] 2>/dev/null; then
      size "$label : $sz  ($path)"
      TOTAL_FREED=$((TOTAL_FREED + bytes))
      if [[ "$DRY_RUN" == false ]]; then
        rm -rf "$path" 2>/dev/null || warn "  Impossible de supprimer (protégé)"
      fi
    fi
  fi
}

check_and_clean_contents() {
  local label="$1"
  local path="$2"
  if [[ -d "$path" ]] && [[ -n "$(ls -A "$path" 2>/dev/null || true)" ]]; then
    local sz bytes
    sz=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "0")
    bytes=$(du -sk "$path" 2>/dev/null | cut -f1 || echo "0")
    bytes="${bytes:-0}"
    if [[ "$bytes" -gt 0 ]] 2>/dev/null; then
      size "$label : $sz  ($path)"
      TOTAL_FREED=$((TOTAL_FREED + bytes))
      if [[ "$DRY_RUN" == false ]]; then
        rm -rf "${path:?}"/* 2>/dev/null || warn "  Certains fichiers protégés n'ont pas pu être supprimés"
      fi
    fi
  fi
}

# ══════════════════════════════════════════════
# 1. CACHES & LOGS macOS
# ══════════════════════════════════════════════
sep
info "${BOLD}1/15 — Caches & logs macOS${NC}"

check_and_clean_contents "User cache" "$HOME/Library/Caches"
check_and_clean_contents "User logs" "$HOME/Library/Logs"
check_and_clean "CrashReporter" "$HOME/Library/Logs/DiagnosticReports"
check_and_clean "Saved Application State" "$HOME/Library/Saved Application State"
check_and_clean "QuickLook cache" "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"
check_and_clean "QuickLook thumbnails" "$HOME/Library/QuickLook"
check_and_clean "Font cache" "$HOME/Library/Caches/com.apple.fontd"

# ══════════════════════════════════════════════
# 2. macOS SYSTEM UPDATES & INSTALLERS
# ══════════════════════════════════════════════
sep
info "${BOLD}2/15 — Mises à jour macOS & installeurs${NC}"

check_and_clean "macOS Software Update" "$HOME/Library/Caches/com.apple.SoftwareUpdate"
# Old macOS installers in /Applications
for installer in "/Applications/Install macOS"*".app"; do
  [[ -e "$installer" ]] && check_and_clean "macOS installer" "$installer"
done
check_and_clean "Apple update staging" "/Library/Updates"

# ══════════════════════════════════════════════
# 3. iOS BACKUPS
# ══════════════════════════════════════════════
sep
info "${BOLD}3/15 — Sauvegardes iOS (iTunes/Finder)${NC}"

BACKUP_DIR="$HOME/Library/Application Support/MobileSync/Backup"
if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null || true)" ]]; then
  sz=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "?")
  bytes=$(du -sk "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")
  bytes="${bytes:-0}"
  size "iOS backups : $sz  ($BACKUP_DIR)"
  TOTAL_FREED=$((TOTAL_FREED + bytes))
  if [[ "$DRY_RUN" == false ]]; then
    read -r -p "  Supprimer toutes les sauvegardes iOS ? [y/N] " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
      rm -rf "${BACKUP_DIR:?}"/* 2>/dev/null || warn "  Erreur lors de la suppression."
    else
      info "  Ignoré."
    fi
  fi
else
  info "  Pas de backup iOS trouvé."
fi

# ══════════════════════════════════════════════
# 4. NAVIGATEURS
# ══════════════════════════════════════════════
sep
info "${BOLD}4/15 — Caches navigateurs${NC}"

# Safari
check_and_clean "Safari cache" "$HOME/Library/Caches/com.apple.Safari"
check_and_clean "Safari WebKit cache" "$HOME/Library/Caches/com.apple.WebKit.WebContent"
check_and_clean "Safari favicon cache" "$HOME/Library/Safari/Favicon Cache"
check_and_clean "Safari service worker" "$HOME/Library/Caches/com.apple.Safari.SafeBrowsing"

# Chrome
check_and_clean "Chrome cache" "$HOME/Library/Caches/Google/Chrome"
check_and_clean "Chrome profile cache" "$HOME/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage"
check_and_clean "Chrome GPU cache" "$HOME/Library/Application Support/Google/Chrome/ShaderCache"
check_and_clean "Chrome crash reports" "$HOME/Library/Application Support/Google/Chrome/Crashpad"

# Firefox
check_and_clean "Firefox cache" "$HOME/Library/Caches/Firefox"

# Arc
check_and_clean "Arc cache" "$HOME/Library/Caches/company.thebrowser.Browser"

# Brave
check_and_clean "Brave cache" "$HOME/Library/Caches/BraveSoftware"

# Edge
check_and_clean "Edge cache" "$HOME/Library/Caches/com.microsoft.edgemac"

# ══════════════════════════════════════════════
# 5. APPS DE COMMUNICATION
# ══════════════════════════════════════════════
sep
info "${BOLD}5/15 — Apps de communication${NC}"

# Slack
check_and_clean "Slack cache" "$HOME/Library/Caches/com.tinyspeck.slackmacgap"
check_and_clean "Slack storage" "$HOME/Library/Application Support/Slack/Cache"
check_and_clean "Slack Service Worker" "$HOME/Library/Application Support/Slack/Service Worker/CacheStorage"

# Discord
check_and_clean "Discord cache" "$HOME/Library/Caches/com.hnc.Discord"
check_and_clean "Discord storage" "$HOME/Library/Application Support/discord/Cache"

# Teams
check_and_clean "Teams cache" "$HOME/Library/Caches/com.microsoft.teams2"
check_and_clean "Teams old cache" "$HOME/Library/Application Support/Microsoft/Teams/Cache"

# Zoom
check_and_clean "Zoom cache" "$HOME/Library/Caches/us.zoom.xos"
check_and_clean "Zoom data" "$HOME/Library/Application Support/zoom.us/data"

# Telegram
check_and_clean "Telegram cache" "$HOME/Library/Caches/ru.keepcoder.Telegram"
check_and_clean "Telegram cache (App Store)" "$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/account-*"

# WhatsApp
check_and_clean "WhatsApp cache" "$HOME/Library/Caches/net.whatsapp.WhatsApp"

# ══════════════════════════════════════════════
# 6. APPS MEDIA & CRÉATIVES
# ══════════════════════════════════════════════
sep
info "${BOLD}6/15 — Apps media & créatives${NC}"

# Spotify
check_and_clean "Spotify cache" "$HOME/Library/Caches/com.spotify.client"
check_and_clean "Spotify storage" "$HOME/Library/Application Support/Spotify/PersistentCache"

# Apple Music / Podcasts downloads
check_and_clean "Podcasts cache" "$HOME/Library/Caches/com.apple.podcasts"
check_and_clean "Apple Music cache" "$HOME/Library/Caches/com.apple.AMPArtworkAgent"

# Adobe
check_and_clean "Adobe cache" "$HOME/Library/Caches/Adobe"
check_and_clean "Adobe common" "$HOME/Library/Application Support/Adobe/Common"

# Figma
check_and_clean "Figma cache" "$HOME/Library/Caches/com.figma.Desktop"
check_and_clean "Figma storage" "$HOME/Library/Application Support/Figma/Cache"

# ══════════════════════════════════════════════
# 7. IDE & ÉDITEURS
# ══════════════════════════════════════════════
sep
info "${BOLD}7/15 — IDEs & éditeurs de code${NC}"

# VS Code
check_and_clean "VS Code cache" "$HOME/Library/Caches/com.microsoft.VSCode"
check_and_clean "VS Code CachedData" "$HOME/Library/Application Support/Code/CachedData"
check_and_clean "VS Code CachedExtensions" "$HOME/Library/Application Support/Code/CachedExtensionVSIXs"
check_and_clean "VS Code logs" "$HOME/Library/Application Support/Code/logs"
check_and_clean "VS Code crash reports" "$HOME/Library/Application Support/Code/Crashpad"
check_and_clean "VS Code workspaceStorage" "$HOME/Library/Application Support/Code/User/workspaceStorage"

# Cursor
check_and_clean "Cursor cache" "$HOME/Library/Caches/com.todesktop.230313mzl4w4u92"
check_and_clean "Cursor CachedData" "$HOME/Library/Application Support/Cursor/CachedData"
check_and_clean "Cursor logs" "$HOME/Library/Application Support/Cursor/logs"

# JetBrains (IntelliJ, WebStorm, PyCharm, GoLand, etc.)
if [[ -d "$HOME/Library/Caches/JetBrains" ]]; then
  for ide_dir in "$HOME/Library/Caches/JetBrains"/*; do
    [[ -d "$ide_dir" ]] && check_and_clean "JetBrains cache: $(basename "$ide_dir")" "$ide_dir"
  done
fi
check_and_clean "JetBrains logs" "$HOME/Library/Logs/JetBrains"

# Sublime Text
check_and_clean "Sublime cache" "$HOME/Library/Caches/com.sublimetext.4"

# ══════════════════════════════════════════════
# 8. HOMEBREW
# ══════════════════════════════════════════════
sep
info "${BOLD}8/15 — Homebrew${NC}"

if command -v brew &>/dev/null; then
  BREW_CACHE=$(brew --cache 2>/dev/null || echo "")
  if [[ -n "$BREW_CACHE" && -d "$BREW_CACHE" ]]; then
    sz=$(du -sh "$BREW_CACHE" 2>/dev/null | cut -f1)
    bytes=$(du -sk "$BREW_CACHE" 2>/dev/null | cut -f1)
    size "Homebrew cache : $sz  ($BREW_CACHE)"
    TOTAL_FREED=$((TOTAL_FREED + bytes))
    if [[ "$DRY_RUN" == false ]]; then
      brew cleanup --prune=all -s 2>/dev/null || true
    fi
  fi
  # Old brew downloads
  check_and_clean "Homebrew old downloads" "$HOME/Library/Caches/Homebrew"
else
  info "  Homebrew non installé, skip."
fi

# ══════════════════════════════════════════════
# 9. DOCKER
# ══════════════════════════════════════════════
sep
info "${BOLD}9/15 — Docker${NC}"

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  docker system df 2>/dev/null || true
  echo ""
  if [[ "$DRY_RUN" == false ]]; then
    info "Nettoyage Docker (images, build cache, volumes orphelins)..."
    docker system prune -a -f --volumes 2>/dev/null || true
    docker builder prune -a -f 2>/dev/null || true
  else
    info "  (docker system prune -a --volumes serait exécuté)"
  fi
else
  info "  Docker non actif, skip."
fi

# ══════════════════════════════════════════════
# 10. CACHES DÉVELOPPEMENT — LANGAGES
# ══════════════════════════════════════════════
sep
info "${BOLD}10/15 — Caches développement (langages & packages)${NC}"

# Node.js / JavaScript
check_and_clean "npm cache" "$HOME/.npm/_cacache"
check_and_clean "npm logs" "$HOME/.npm/_logs"
check_and_clean "yarn cache" "$HOME/.cache/yarn"
check_and_clean "yarn berry cache" "$HOME/.yarn/berry/cache"
check_and_clean "pnpm store" "$HOME/Library/pnpm/store"
check_and_clean "pnpm cache" "$HOME/.cache/pnpm"
check_and_clean "bun cache" "$HOME/.bun/install/cache"

# Python
check_and_clean "pip cache" "$HOME/Library/Caches/pip"
check_and_clean "pip alt cache" "$HOME/.cache/pip"
check_and_clean "pipenv cache" "$HOME/.cache/pipenv"
check_and_clean "poetry cache" "$HOME/Library/Caches/pypoetry"
check_and_clean "mypy cache" "$HOME/.cache/mypy"
check_and_clean "ruff cache" "$HOME/.cache/ruff"
check_and_clean "pre-commit cache" "$HOME/.cache/pre-commit"

# Ruby
check_and_clean "Ruby gem cache" "$HOME/.gem"
check_and_clean "Bundler cache" "$HOME/.bundle/cache"

# Go
check_and_clean "Go module cache" "$HOME/go/pkg/mod/cache"
check_and_clean "Go build cache" "$HOME/Library/Caches/go-build"

# Rust
check_and_clean "Cargo registry cache" "$HOME/.cargo/registry/cache"
check_and_clean "Cargo registry src" "$HOME/.cargo/registry/src"
check_and_clean "Cargo git db" "$HOME/.cargo/git/db"

# Java / JVM
check_and_clean "Gradle cache" "$HOME/.gradle/caches"
check_and_clean "Gradle wrapper" "$HOME/.gradle/wrapper/dists"
check_and_clean "Gradle daemon logs" "$HOME/.gradle/daemon"
check_and_clean "Maven cache" "$HOME/.m2/repository"
check_and_clean "sbt cache" "$HOME/.sbt"
check_and_clean "Coursier cache" "$HOME/Library/Caches/Coursier"

# PHP
check_and_clean "Composer cache" "$HOME/.composer/cache"

# .NET
check_and_clean "NuGet cache" "$HOME/.nuget/packages"
check_and_clean "dotnet HTTP cache" "$HOME/.local/share/NuGet"

# ══════════════════════════════════════════════
# 11. CACHES DÉVELOPPEMENT — OUTILS
# ══════════════════════════════════════════════
sep
info "${BOLD}11/15 — Caches développement (outils)${NC}"

# Kubernetes / DevOps
check_and_clean "Helm cache" "$HOME/Library/Caches/helm"
check_and_clean "Helm plugins" "$HOME/.cache/helm"
check_and_clean "kubectl cache" "$HOME/.kube/cache"
check_and_clean "kubectl http-cache" "$HOME/.kube/http-cache"
check_and_clean "Minikube cache" "$HOME/.minikube/cache"
check_and_clean "Terraform plugin cache" "$HOME/.terraform.d/plugin-cache"

# API clients
check_and_clean "Postman cache" "$HOME/Library/Caches/com.postmanlabs.mac"
check_and_clean "Insomnia cache" "$HOME/Library/Caches/com.insomnia.app"

# Git
check_and_clean "Git credential cache" "$HOME/.cache/git"

# CocoaPods
check_and_clean "CocoaPods cache" "$HOME/Library/Caches/CocoaPods"

# ccache
check_and_clean "ccache" "$HOME/.ccache"

# Bazel
check_and_clean "Bazel cache" "$HOME/.cache/bazel"
check_and_clean "Bazel output" "/private/var/tmp/_bazel_$(whoami)"

# ══════════════════════════════════════════════
# 12. XCODE & APPLE DEV
# ══════════════════════════════════════════════
sep
info "${BOLD}12/15 — Xcode & Apple développement${NC}"

check_and_clean "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"
check_and_clean "Xcode Archives" "$HOME/Library/Developer/Xcode/Archives"
check_and_clean "Xcode iOS DeviceSupport" "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
check_and_clean "Xcode watchOS DeviceSupport" "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
check_and_clean "Xcode macOS DeviceSupport" "$HOME/Library/Developer/Xcode/macOS DeviceSupport"
check_and_clean "Xcode tvOS DeviceSupport" "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
check_and_clean "CoreSimulator Caches" "$HOME/Library/Developer/CoreSimulator/Caches"
check_and_clean "CoreSimulator Devices" "$HOME/Library/Developer/CoreSimulator/Devices"
check_and_clean "Xcode Previews" "$HOME/Library/Developer/Xcode/UserData/Previews"
check_and_clean "Playground products" "$HOME/Library/Developer/XCPGDevices"
check_and_clean "Swift Package Manager" "$HOME/Library/Caches/org.swift.swiftpm"
check_and_clean "SwiftUI previews" "$HOME/Library/Developer/Xcode/UserData/Previews/Simulator Devices"

# Android
check_and_clean "Android SDK cache" "$HOME/.android/cache"
check_and_clean "Android AVD" "$HOME/.android/avd"
check_and_clean "Android build cache" "$HOME/.android/build-cache"

# ══════════════════════════════════════════════
# 13. CORBEILLE
# ══════════════════════════════════════════════
sep
info "${BOLD}13/15 — Corbeille${NC}"

if [[ -d "$HOME/.Trash" ]] && [[ -n "$(ls -A "$HOME/.Trash" 2>/dev/null || true)" ]]; then
  sz=$(du -sh "$HOME/.Trash" 2>/dev/null | cut -f1 || echo "?")
  bytes=$(du -sk "$HOME/.Trash" 2>/dev/null | cut -f1 || echo "0")
  bytes="${bytes:-0}"
  size "Corbeille : $sz"
  TOTAL_FREED=$((TOTAL_FREED + bytes))
  if [[ "$DRY_RUN" == false ]]; then
    rm -rf "$HOME/.Trash"/* 2>/dev/null || true
  fi
else
  info "  Corbeille vide."
fi

# ══════════════════════════════════════════════
# 14. FICHIERS TEMPORAIRES & DOWNLOADS
# ══════════════════════════════════════════════
sep
info "${BOLD}14/15 — Fichiers temporaires & node_modules orphelins${NC}"

# Temp files
check_and_clean "User tmp" "$TMPDIR"
check_and_clean "/var/tmp cleanup" "/private/var/tmp/com.apple.installer"

# node_modules orphans in home (not in projects)
NM_COUNT=0
NM_TOTAL=0
while IFS= read -r nm_dir; do
  if [[ -d "$nm_dir" ]]; then
    nm_bytes=$(du -sk "$nm_dir" 2>/dev/null | cut -f1)
    NM_TOTAL=$((NM_TOTAL + nm_bytes))
    NM_COUNT=$((NM_COUNT + 1))
  fi
done < <(find "$HOME" -maxdepth 5 -name "node_modules" -type d \
  -not -path "*/.*" \
  -not -path "*/Library/*" \
  -not -path "*Mobile Documents*" \
  -not -path "*Pictures*" \
  -not -path "*Photos*" \
  2>/dev/null || true)

if [[ "$NM_COUNT" -gt 0 ]]; then
  NM_MB=$((NM_TOTAL / 1024))
  size "node_modules trouvés : $NM_COUNT dossiers (~${NM_MB} Mo)"
  if [[ "$DRY_RUN" == false ]]; then
    read -r -p "  Lister et choisir lesquels supprimer ? [y/N] " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
      while IFS= read -r nm_dir; do
        if [[ -d "$nm_dir" ]]; then
          nm_sz=$(du -sh "$nm_dir" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "    Supprimer $nm_dir ($nm_sz) ? [y/N] " nm_confirm < /dev/tty
          if [[ "$nm_confirm" =~ ^[yY]$ ]]; then
            rm -rf "$nm_dir" 2>/dev/null || warn "    Impossible de supprimer"
            info "    Supprimé."
          fi
        fi
      done < <(find "$HOME" -maxdepth 5 -name "node_modules" -type d \
        -not -path "*/.*" \
        -not -path "*/Library/*" \
        -not -path "*Mobile Documents*" \
        -not -path "*Pictures*" \
        -not -path "*Photos*" \
        2>/dev/null || true)
    fi
  fi
fi

# ══════════════════════════════════════════════
# 15. ANALYSE — TOP GROS DOSSIERS
# ══════════════════════════════════════════════
sep
info "${BOLD}15/15 — Top 20 des plus gros dossiers (hors images & iCloud)${NC}"
echo ""

du -sh \
  "$HOME"/*/ \
  "$HOME"/Library/*/ \
  "$HOME"/Library/Application\ Support/*/ \
  "$HOME"/Library/Developer/*/ \
  2>/dev/null \
  | grep -v -i "Photos" \
  | grep -v -i "Pictures" \
  | grep -v -i "Mobile Documents" \
  | grep -v -i "iCloud" \
  | grep -v -i "PhotoKit" \
  | sort -hr \
  | head -20

# ══════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"

TOTAL_MB=$((TOTAL_FREED / 1024))
TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MB / 1024}")

if [[ "$DRY_RUN" == true ]]; then
  echo -e "${YELLOW}  Mode dry-run : ~${TOTAL_MB} Mo (${TOTAL_GB} Go) pourraient être libérés.${NC}"
  echo -e "${YELLOW}  Relance sans --dry-run pour effectuer le nettoyage.${NC}"
else
  echo -e "${GREEN}  Nettoyage terminé ! ~${TOTAL_MB} Mo (${TOTAL_GB} Go) libérés.${NC}"
  echo ""
  info "Espace disque après nettoyage :"
  df -h / | tail -1 | awk '{printf "  Total: %s | Utilisé: %s | Libre: %s (%s utilisé)\n", $2, $3, $4, $5}'
fi
echo ""
