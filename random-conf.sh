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
    echo "  --help          Show this help message"
    echo ""
    echo "  --get           Get the currently symlinked config file."
    echo ""
    echo "  --groups        List available groups"
    echo ""
    echo "  --exact-conf    Comma-separated list of conf files to randomly select from."
    echo ""
    echo "  --random-theme  Comma-separated list of group names to randomly select from."
    echo ""
    echo "  --all           Randomly select from all available config files."
    echo ""
    echo "  --blacklist-conf Comma-separated list of conf files to exclude from random selection."
    echo ""
    echo "  --blacklist-theme  Comma-separated list of group names whose members should be excluded from random selection."
    echo ""
    echo "  If no arguments are given, reads from .config/sddm-theme/theme.conf:"
    echo ""
    echo "  Both keys can coexist — all candidates are pooled except for blacklisted ones before the random pick."
    echo ""
    echo "  theme.conf keys: exact-conf, random-theme, all, blacklist-conf, blacklist-theme"
}

# ── Handle CLI Only args get, groups, help ─────────────────────────────────

if [ "${1:-}" = "--get" ]; then
    if [ -L "$SYMLINK" ]; then
        target=$(readlink "$SYMLINK")
        rel="${target#"$PROJECT_DIR/configs/"}"
        echo "$rel"
    else
        echo "No config currently symlinked at $SYMLINK"
        exit 1
    fi
    exit 0
elif [ "${1:-}" = "--groups" ]; then
    # print group names "\n".join(groups) to ", ".join(groups)
    echo "Available groups:"
    cut -d= -f1 "$GROUPS_FILE" | sed 's/^/  /' | paste -sd "," -
    exit 0
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# ── Parse Main CLI arguments ────────────────────────────────────────────────────────
exact_conf=""
random_theme=""
all_flag=false
blacklist_conf=""
blacklist_theme=""

for arg in "$@"; do
    case "$arg" in
        --exact-conf=*)      exact_conf="${arg#*=}" ;;
        --random-theme=*)    random_theme="${arg#*=}" ;;
        --all)               all_flag=true ;;
        --blacklist-conf=*)  blacklist_conf="${arg#*=}" ;;
        --blacklist-theme=*) blacklist_theme="${arg#*=}" ;;
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
    if grep -qE "^all=true$" "$THEME_CONF"; then
        all_flag=true
    fi
    blacklist_conf=$(grep -E "^blacklist-conf=" "$THEME_CONF" | cut -d= -f2- || true)
    blacklist_theme=$(grep -E "^blacklist-theme=" "$THEME_CONF" | cut -d= -f2- || true)
    
    # # Debug Line 1
    # echo "Loaded from theme.conf:"
    # echo "read exact_conf: '$exact_conf'"
    # echo "read random_theme: '$random_theme'"
    # echo "read all_flag: '$all_flag'"
    # echo "read blacklist_conf: '$blacklist_conf'"
    # echo "read blacklist_theme: '$blacklist_theme'"
fi

# ── Build candidate list ───────────────────────────────────────────────────────
candidates=()

# Expand --exact-conf entries (each is a direct path relative to configs/)
# Skipped when --all is set since it already pools everything
if [ "$all_flag" = false ] && [ -n "$exact_conf" ]; then
    IFS=',' read -ra parts <<< "$exact_conf"
    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"  # ltrim
        part="${part%"${part##*[![:space:]]}"}"  # rtrim
        [ -n "$part" ] && candidates+=("$part")
    done

    # Debug Line 2
    # echo "Candidates from exact-conf:"
    # for c in "${candidates[@]}"; do
    #     echo "  $c"
    # done
fi

# Expand --random-theme group names into their member files
# Skipped when --all is set since it already pools everything
if [ "$all_flag" = false ] && [ -n "$random_theme" ]; then
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

    # Debug Line 3
    # echo "Candidates from random-theme groups:"
    # for c in "${candidates[@]}"; do
    #     echo "  $c"
    # done
fi

# Expand --all: every .conf file under configs/ except groups.conf and random.conf
if [ "$all_flag" = true ]; then
    while IFS= read -r f; do
        rel="${f#"$PROJECT_DIR/configs/"}"
        candidates+=("$rel")
    done < <(find "$PROJECT_DIR/configs" -type f -name '*.conf' \
        ! -name 'groups.conf' ! -name 'random.conf')

    # Debug Line 4
    # echo "Candidates from --all:"
    # for c in "${candidates[@]}"; do
    #     echo "  $c"
    # done
fi

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "No configs found to select from."
    exit 1
fi

# ── Apply blacklist ────────────────────────────────────────────────────────────
blacklisted=()

if [ -n "$blacklist_conf" ]; then
    IFS=',' read -ra parts <<< "$blacklist_conf"
    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"  # ltrim
        part="${part%"${part##*[![:space:]]}"}"  # rtrim
        [ -n "$part" ] && blacklisted+=("$part")
    done

    # Debug Line 5
    # echo "Blacklisted configs from blacklist-conf:"
    # for b in "${blacklisted[@]}"; do
    #     echo "  $b"
    # done
fi

if [ -n "$blacklist_theme" ]; then
    IFS=',' read -ra groups <<< "$blacklist_theme"
    for group in "${groups[@]}"; do
        group="${group#"${group%%[![:space:]]*}"}"
        group="${group%"${group##*[![:space:]]}"}"
        [ -z "$group" ] && continue
        group_files=$(grep -E "^$group=" "$GROUPS_FILE" | cut -d= -f2- | tr ' ' '\n' || true)
        while IFS= read -r f; do
            [ -n "$f" ] && blacklisted+=("$f")
        done <<< "$group_files"
    done

    # Debug Line 6
    # echo "Blacklisted configs from blacklist-theme groups:"
    # for b in "${blacklisted[@]}"; do
    #     echo "  $b"
    # done
fi

if [ "${#blacklisted[@]}" -gt 0 ]; then
    filtered=()
    for c in "${candidates[@]}"; do
        skip=false
        for b in "${blacklisted[@]}"; do
            if [ "$c" = "$b" ]; then
                skip=true
                break
            fi
        done
        $skip || filtered+=("$c")
    done
    candidates=("${filtered[@]}")
    if [ "${#candidates[@]}" -eq 0 ]; then
        echo "No configs left after applying blacklist."
        exit 1
    fi

    # Debug Line 7
    # echo "Candidates after applying blacklist:"
    # for c in "${candidates[@]}"; do 
    #     echo "  $c"
    # done    
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
