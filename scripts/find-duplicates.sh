#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
size()  { echo -e "${CYAN}[DUP]${NC}  $1"; }

# ──────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────
SCAN_DIR="${1:-$HOME}"
MIN_SIZE="${2:-1048576}"  # 1 Mo minimum par défaut (en octets)

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Détection de doublons par MD5 checksum${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Dossier scanné :  $SCAN_DIR"
echo -e "  Taille minimum :  $((MIN_SIZE / 1024)) Ko"
echo -e "  Exclusions :      images, iCloud, Photos, .Trash, Library/Caches"
echo ""

# ──────────────────────────────────────────────
# Étape 1 : Trouver les fichiers et grouper par taille
# ──────────────────────────────────────────────
info "Étape 1/3 — Scan des fichiers (par taille)..."

TMPDIR_WORK=$(mktemp -d)
SIZE_FILE="$TMPDIR_WORK/sizes.txt"
DUP_SIZES="$TMPDIR_WORK/dup_sizes.txt"
HASH_FILE="$TMPDIR_WORK/hashes.txt"
RESULTS="$TMPDIR_WORK/results.txt"

trap 'rm -rf "$TMPDIR_WORK"' EXIT

# Find all files, excluding unwanted directories and image files
# Note: pipeline may return non-zero on permission errors, so we catch it
find "$SCAN_DIR" -type f -size +"${MIN_SIZE}c" \
  -not -path "*/Library/Caches/*" \
  -not -path "*/Library/Logs/*" \
  -not -path "*/.Trash/*" \
  -not -path "*/Mobile Documents/*" \
  -not -path "*iCloud*" \
  -not -path "*/Photos Library.photoslibrary/*" \
  -not -path "*Pictures*" \
  -not -path "*Photos*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/CoreSimulator/*" \
  -not -iname "*.jpg" \
  -not -iname "*.jpeg" \
  -not -iname "*.png" \
  -not -iname "*.gif" \
  -not -iname "*.heic" \
  -not -iname "*.heif" \
  -not -iname "*.svg" \
  -not -iname "*.webp" \
  -not -iname "*.tiff" \
  -not -iname "*.bmp" \
  -not -iname "*.raw" \
  -not -iname "*.cr2" \
  -not -iname "*.ico" \
  -not -iname "*.psd" \
  -print0 2>/dev/null \
| xargs -0 stat -f '%z %N' 2>/dev/null \
| sort -n > "$SIZE_FILE" || true

TOTAL_FILES=$(wc -l < "$SIZE_FILE" 2>/dev/null | tr -d ' ')
TOTAL_FILES="${TOTAL_FILES:-0}"
info "  $TOTAL_FILES fichiers trouvés (> $((MIN_SIZE / 1024)) Ko)"

# Find sizes that appear more than once (potential duplicates)
awk '{print $1}' "$SIZE_FILE" | sort -n | uniq -d > "$DUP_SIZES"
DUP_SIZE_COUNT=$(wc -l < "$DUP_SIZES" | tr -d ' ')

if [[ "$DUP_SIZE_COUNT" -eq 0 ]]; then
  info "Aucun doublon potentiel trouvé."
  exit 0
fi

# Filter only files with duplicate sizes
DUP_CANDIDATES=0
while IFS= read -r fsize; do
  grep -E "^${fsize} " "$SIZE_FILE" >> "$HASH_FILE.candidates" 2>/dev/null || true
  count=$(grep -cE "^${fsize} " "$SIZE_FILE" 2>/dev/null || echo "0")
  DUP_CANDIDATES=$((DUP_CANDIDATES + count))
done < "$DUP_SIZES"

info "  $DUP_CANDIDATES fichiers partagent une taille identique ($DUP_SIZE_COUNT tailles)"

# ──────────────────────────────────────────────
# Étape 2 : Calculer les MD5 des candidats
# ──────────────────────────────────────────────
echo ""
info "Étape 2/3 — Calcul des checksums MD5..."

PROGRESS=0
> "$HASH_FILE"

while IFS= read -r line; do
  fsize="${line%% *}"
  fpath="${line#* }"
  PROGRESS=$((PROGRESS + 1))

  if [[ -f "$fpath" ]] && [[ -r "$fpath" ]]; then
    hash=$(md5 -q "$fpath" 2>/dev/null) || hash="ERROR"
    if [[ "$hash" != "ERROR" ]]; then
      echo "${hash} ${fsize} ${fpath}" >> "$HASH_FILE"
    fi
  fi

  # Progress every 100 files
  if (( PROGRESS % 100 == 0 )); then
    printf "\r  %d / %d fichiers traités..." "$PROGRESS" "$DUP_CANDIDATES"
  fi
done < "$HASH_FILE.candidates"

printf "\r  %d / %d fichiers traités.    \n" "$PROGRESS" "$DUP_CANDIDATES"

# ──────────────────────────────────────────────
# Étape 3 : Identifier les vrais doublons
# ──────────────────────────────────────────────
echo ""
info "Étape 3/3 — Identification des doublons..."

# Find duplicate hashes
awk '{print $1}' "$HASH_FILE" | sort | uniq -d > "$TMPDIR_WORK/dup_hashes.txt"
DUP_HASH_COUNT=$(wc -l < "$TMPDIR_WORK/dup_hashes.txt" | tr -d ' ')

if [[ "$DUP_HASH_COUNT" -eq 0 ]]; then
  echo ""
  info "Aucun doublon trouvé !"
  exit 0
fi

# Build results — store groups in temp files for interactive mode
TOTAL_WASTE=0
GROUP_NUM=0

sort -t' ' -k1,1 -k2,2rn "$HASH_FILE" > "$TMPDIR_WORK/sorted_hashes.txt"

echo "" > "$RESULTS"

# Store group data for interactive deletion
mkdir -p "$TMPDIR_WORK/groups"

while IFS= read -r dup_hash; do
  GROUP_NUM=$((GROUP_NUM + 1))

  # Get all files with this hash
  files=()
  fsize=0
  while IFS= read -r match; do
    hash_part="${match%% *}"
    rest="${match#* }"
    fsize="${rest%% *}"
    fpath="${rest#* }"
    files+=("$fpath")
  done < <(grep "^${dup_hash} " "$TMPDIR_WORK/sorted_hashes.txt")

  count=${#files[@]}
  waste=$(( (count - 1) * fsize ))
  TOTAL_WASTE=$((TOTAL_WASTE + waste))

  # Save group files for interactive mode
  printf "%s\n" "${files[@]}" > "$TMPDIR_WORK/groups/$GROUP_NUM.txt"
  echo "$fsize" > "$TMPDIR_WORK/groups/$GROUP_NUM.size"

  # Human-readable size
  if (( fsize > 1073741824 )); then
    hr_size=$(awk "BEGIN {printf \"%.1f Go\", $fsize / 1073741824}")
  elif (( fsize > 1048576 )); then
    hr_size=$(awk "BEGIN {printf \"%.1f Mo\", $fsize / 1048576}")
  else
    hr_size=$(awk "BEGIN {printf \"%.0f Ko\", $fsize / 1024}")
  fi

  waste_hr=""
  if (( waste > 1073741824 )); then
    waste_hr=$(awk "BEGIN {printf \"%.1f Go\", $waste / 1073741824}")
  elif (( waste > 1048576 )); then
    waste_hr=$(awk "BEGIN {printf \"%.1f Mo\", $waste / 1048576}")
  else
    waste_hr=$(awk "BEGIN {printf \"%.0f Ko\", $waste / 1024}")
  fi

  {
    echo -e "${CYAN}── Groupe $GROUP_NUM${NC} | ${BOLD}$hr_size${NC} x $count copies | gaspillé: ${RED}$waste_hr${NC} | md5: ${dup_hash:0:12}..."
    for f in "${files[@]}"; do
      echo "   $f"
    done
    echo ""
  } >> "$RESULTS"

done < "$TMPDIR_WORK/dup_hashes.txt"

# ──────────────────────────────────────────────
# Affichage des résultats (triés par taille gaspillée)
# ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Résultats : $DUP_HASH_COUNT groupes de doublons${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""

cat "$RESULTS"

# Summary
if (( TOTAL_WASTE > 1073741824 )); then
  total_hr=$(awk "BEGIN {printf \"%.1f Go\", $TOTAL_WASTE / 1073741824}")
elif (( TOTAL_WASTE > 1048576 )); then
  total_hr=$(awk "BEGIN {printf \"%.1f Mo\", $TOTAL_WASTE / 1048576}")
else
  total_hr=$(awk "BEGIN {printf \"%.0f Ko\", $TOTAL_WASTE / 1024}")
fi

echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "  Doublons trouvés :  ${BOLD}$DUP_HASH_COUNT groupes${NC}"
echo -e "  Espace gaspillé :   ${RED}${BOLD}$total_hr${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"

# ──────────────────────────────────────────────
# Étape 4 : Suppression interactive
# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Voulez-vous passer en mode suppression interactive ?${NC}"
echo -e "  Pour chaque groupe, vous choisirez le fichier à ${BOLD}garder${NC}."
echo -e "  Les autres copies seront supprimées."
echo ""
read -r -p "Lancer la suppression interactive ? [y/N] " do_delete < /dev/tty

if [[ ! "$do_delete" =~ ^[yY]$ ]]; then
  echo ""
  info "Mode rapport uniquement. Aucun fichier supprimé."
  echo -e "  Pour relancer avec suppression : $0 $SCAN_DIR $MIN_SIZE"
  echo ""
  exit 0
fi

DELETED_COUNT=0
FREED_BYTES=0

for g in $(seq 1 "$GROUP_NUM"); do
  group_file="$TMPDIR_WORK/groups/$g.txt"
  [[ -f "$group_file" ]] || continue

  # Read files into array (compatible bash 3.2 / macOS)
  gfiles=()
  while IFS= read -r gline; do
    [[ -n "$gline" ]] && gfiles+=("$gline")
  done < "$group_file"
  gsize=$(cat "$TMPDIR_WORK/groups/$g.size")
  gcount=${#gfiles[@]}

  # Human-readable size
  if (( gsize > 1073741824 )); then
    g_hr=$(awk "BEGIN {printf \"%.1f Go\", $gsize / 1073741824}")
  elif (( gsize > 1048576 )); then
    g_hr=$(awk "BEGIN {printf \"%.1f Mo\", $gsize / 1048576}")
  else
    g_hr=$(awk "BEGIN {printf \"%.0f Ko\", $gsize / 1024}")
  fi

  echo ""
  echo -e "${CYAN}━━━ Groupe $g/$GROUP_NUM${NC} | ${BOLD}$g_hr${NC} x $gcount copies"
  echo ""
  for i in "${!gfiles[@]}"; do
    echo -e "  ${BOLD}$((i + 1))${NC}) ${gfiles[$i]}"
  done
  echo ""
  echo -e "  ${BOLD}s${NC}) Passer ce groupe"
  echo -e "  ${BOLD}q${NC}) Quitter la suppression"
  echo ""
  read -r -p "  Numéro du fichier à GARDER (1-$gcount / s / q) : " choice < /dev/tty

  # Quit
  if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
    info "Arrêt de la suppression."
    break
  fi

  # Skip
  if [[ "$choice" == "s" || "$choice" == "S" ]]; then
    warn "Groupe $g ignoré."
    continue
  fi

  # Validate choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > gcount )); then
    warn "Choix invalide. Groupe $g ignoré."
    continue
  fi

  keep_idx=$((choice - 1))
  keep_file="${gfiles[$keep_idx]}"
  echo -e "  ${GREEN}Garder :${NC} $keep_file"

  for i in "${!gfiles[@]}"; do
    if [[ "$i" -ne "$keep_idx" ]]; then
      target="${gfiles[$i]}"
      if [[ -f "$target" ]]; then
        rm -f "$target"
        echo -e "  ${RED}Supprimé :${NC} $target"
        DELETED_COUNT=$((DELETED_COUNT + 1))
        FREED_BYTES=$((FREED_BYTES + gsize))
      else
        warn "  Fichier introuvable : $target"
      fi
    fi
  done
done

# ──────────────────────────────────────────────
# Bilan de la suppression
# ──────────────────────────────────────────────
if (( FREED_BYTES > 1073741824 )); then
  freed_hr=$(awk "BEGIN {printf \"%.1f Go\", $FREED_BYTES / 1073741824}")
elif (( FREED_BYTES > 1048576 )); then
  freed_hr=$(awk "BEGIN {printf \"%.1f Mo\", $FREED_BYTES / 1048576}")
else
  freed_hr=$(awk "BEGIN {printf \"%.0f Ko\", $FREED_BYTES / 1024}")
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "  Fichiers supprimés :  ${BOLD}$DELETED_COUNT${NC}"
echo -e "  Espace libéré :      ${GREEN}${BOLD}$freed_hr${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
