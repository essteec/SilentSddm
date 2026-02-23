#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"

CONFIG_DIR="$HOME/.config/sddm-theme"

GROUPS_FILE="$PROJECT_DIR/configs/groups.conf"
SYMLINK="$PROJECT_DIR/configs/random.conf"
THEME_CONF="$CONFIG_DIR/theme.conf"

usage() {
    echo "Usage: $(basename "$0") [--exact-conf=file1.conf,file2.conf] [--random-theme=group1,group2]"
    echo ""
    echo "  --exact-conf    Comma-separated list of conf files (relative to configs/)."
    echo "                  One is picked at random and symlinked."
    echo "  --random-theme  Comma-separated list of group names from groups.conf."
    echo "                  All files from each group are pooled; one is picked at random."
    echo "  --all           Pool every .conf file found recursively under configs/."
    echo ""
    echo "  If no arguments are given, reads from $THEME_CONF:"
    echo "    exact-conf=main/rose-right.conf,main/default.conf"
    echo "    random-theme=demon-slayer,animated"
    echo ""
    echo "  Both keys can coexist — all candidates are pooled before the random pick."
    echo ""
    echo "Available groups:"
    cut -d= -f1 "$GROUPS_FILE" | sed 's/^/  /'
}

# ── Parse CLI arguments ────────────────────────────────────────────────────────
exact_conf=""
random_theme=""
all_flag=false

for arg in "$@"; do
    case "$arg" in
        --exact-conf=*)   exact_conf="${arg#*=}" ;;
        --random-theme=*) random_theme="${arg#*=}" ;;
        --all)            all_flag=true ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

# ── Fall back to theme.conf if no CLI args ─────────────────────────────────────
if [ -z "$exact_conf" ] && [ -z "$random_theme" ] && [ "$all_flag" = false ]; then
    if [ ! -f "$THEME_CONF" ]; then
        echo "No arguments provided and no theme.conf found at $THEME_CONF"
        echo ""
        usage
        exit 1
    fi
    exact_conf=$(grep -E "^exact-conf=" "$THEME_CONF" | cut -d= -f2- || true)
    random_theme=$(grep -E "^random-theme=" "$THEME_CONF" | cut -d= -f2- || true)
fi

# ── Build candidate list ───────────────────────────────────────────────────────
candidates=()

# Expand --exact-conf entries (each is a direct path relative to configs/)
if [ -n "$exact_conf" ]; then
    IFS=',' read -ra parts <<< "$exact_conf"
    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"  # ltrim
        part="${part%"${part##*[![:space:]]}"}"  # rtrim
        [ -n "$part" ] && candidates+=("$part")
    done
fi

# Expand --random-theme group names into their member files
if [ -n "$random_theme" ]; then
    IFS=',' read -ra groups <<< "$random_theme"
    for group in "${groups[@]}"; do
        group="${group#"${group%%[![:space:]]*}"}"
        group="${group%"${group##*[![:space:]]}"}"
        [ -z "$group" ] && continue

        group_files=$(grep -E "^$group=" "$GROUPS_FILE" | cut -d= -f2- | tr ' ' '\n' || true)
        if [ -z "$group_files" ]; then
            echo "No group called '$group' in $GROUPS_FILE"
            echo ""
            echo "Available groups:"
            cut -d= -f1 "$GROUPS_FILE" | sed 's/^/  /'
            exit 1
        fi
        while IFS= read -r f; do
            [ -n "$f" ] && candidates+=("$f")
        done <<< "$group_files"
    done
fi

# Expand --all: every .conf file under configs/ except groups.conf and random.conf
if [ "$all_flag" = true ]; then
    while IFS= read -r f; do
        rel="${f#"$PROJECT_DIR/configs/"}"
        candidates+=("$rel")
    done < <(find "$PROJECT_DIR/configs" -type f -name '*.conf' \
        ! -name 'groups.conf' ! -name 'random.conf')
fi

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "No configs found to select from."
    exit 1
fi

# ── Pick one at random and create symlink ──────────────────────────────────────
selected=$(printf '%s\n' "${candidates[@]}" | shuf -n 1)
target="$PROJECT_DIR/configs/$selected"

if [ ! -f "$target" ]; then
    echo "Config file not found: $target"
    exit 1
fi

sudo ln -sf "$target" "$SYMLINK"
echo "Selected: $selected"
echo "Symlink:  $SYMLINK -> $target"

