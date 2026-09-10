#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# MacDraw installer — downloads the latest release and opens a native
# drag-and-drop installer window.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/aadityakumarsah/macdraw/main/install.sh)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── colours & helpers ────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
WHITE='\033[97m'
BG_INDIGO='\033[48;5;57m'

SPIN=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

cleanup() { rm -rf "$TMP_DIR" 2>/dev/null; }
trap cleanup EXIT

TMP_DIR=$(mktemp -d "/tmp/macdraw-install.XXXXXX")
ZIP_PATH="$TMP_DIR/macdraw.zip"
EXTRACT_DIR="$TMP_DIR/macdraw-extract"

# ── logo ─────────────────────────────────────────────────────────────────────
print_logo() {
    echo ""
    echo -e "${BG_INDIGO}                                                                              ${RESET}"
    echo -e "${BG_INDIGO}  ${WHITE}${BOLD}                          ▀█▀ █▀▀ ▀█▀ █▀▄▀█   █▀▄▀█ █▀█ █▀█ █▄░█${RESET}  ${BG_INDIGO}  ${RESET}"
    echo -e "${BG_INDIGO}  ${WHITE}${BOLD}                           █  ██▄  █  █░▀░█   █░▀░█ █▄█ █▀▄ █░▀█${RESET}  ${BG_INDIGO}  ${RESET}"
    echo -e "${BG_INDIGO}                                                                              ${RESET}"
    echo -e "${BG_INDIGO}  ${DIM}${CYAN}                     draw over anything · macOS 13+ · free forever${RESET}       ${BG_INDIGO}  ${RESET}"
    echo -e "${BG_INDIGO}                                                                              ${RESET}"
    echo ""
}

# ── progress bar ─────────────────────────────────────────────────────────────
# Usage: draw_bar <percent> <width>
draw_bar() {
    local pct=$1
    local width=${2:-40}
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf "\r  ${CYAN}│${WHITE}%s${CYAN}│${RESET} %3d%%" "$bar" "$pct"
}

# ── spinner ──────────────────────────────────────────────────────────────────
spinner_pid=""
spinner_frame=0

spinner_start() {
    local msg="$1"
    (
        while true; do
            for s in "${SPIN[@]}"; do
                printf "\r  ${MAGENTA}%s${RESET} %s" "$s" "$msg"
                sleep 0.08
            done
        done
    ) &
    spinner_pid=$!
}

spinner_stop() {
    if [[ -n "$spinner_pid" ]] && kill -0 "$spinner_pid" 2>/dev/null; then
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
    fi
    spinner_pid=""
    printf "\r\033[K"
}

# ── step indicator ───────────────────────────────────────────────────────────
step_num=0
step() {
    step_num=$((step_num + 1))
    echo -e "\n  ${GREEN}${BOLD}[$step_num]${RESET} $1"
}

# ── main ─────────────────────────────────────────────────────────────────────
print_logo

# Step 1 — resolve latest release
step "Checking latest release…"
API_URL="https://api.github.com/repos/aadityakumarsah/macdraw/releases/latest"
RELEASE_JSON=$(curl -fsSL "$API_URL" 2>/dev/null) || {
    echo -e "\n  ${RED}✗ Could not reach GitHub. Are you online?${RESET}"
    exit 1
}
TAG=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null)
ZIP_NAME=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
assets = json.load(sys.stdin)['assets']
zips = [a for a in assets if a['name'].endswith('.zip')]
print(zips[0]['name'] if zips else '')
" 2>/dev/null)
ZIP_URL=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
assets = json.load(sys.stdin)['assets']
zips = [a for a in assets if a['name'].endswith('.zip')]
print(zips[0]['browser_download_url'] if zips else '')
" 2>/dev/null)

if [[ -z "$TAG" || -z "$ZIP_URL" ]]; then
    echo -e "\n  ${RED}✗ Could not parse the latest release.${RESET}"
    exit 1
fi

VERSION="${TAG#v}"
echo -e "  ${DIM}Latest: ${CYAN}${VERSION}${RESET}"

# Step 2 — download
step "Downloading MacDraw ${CYAN}${VERSION}${RESET}…"

# Get file size for progress (in bytes)
CONTENT_LENGTH=$(curl -sI -L "$ZIP_URL" 2>/dev/null | grep -i content-length | tail -1 | tr -d '\r' | awk '{print $2}')
TOTAL=${CONTENT_LENGTH:-0}

# Download with a custom progress bar
if [[ "$TOTAL" -gt 0 ]] 2>/dev/null; then
    curl -L -s -o "$ZIP_PATH" --write-out '' "$ZIP_URL" &
    CURL_PID=$!
    while kill -0 "$CURL_PID" 2>/dev/null; do
        if [[ -f "$ZIP_PATH" ]]; then
            CURRENT=$(stat -f%z "$ZIP_PATH" 2>/dev/null || echo 0)
            PCT=$(( CURRENT * 100 / TOTAL ))
            [[ $PCT -gt 100 ]] && PCT=100
            draw_bar "$PCT"
        fi
        sleep 0.1
    done
    wait "$CURL_PID" 2>/dev/null
    draw_bar 100
    echo ""
else
    # Fallback: no content-length, use indeterminate spinner
    spinner_start "Downloading…"
    curl -L -s -o "$ZIP_PATH" "$ZIP_URL"
    spinner_stop
    echo -e "  ${GREEN}✓${RESET} Downloaded"
fi

if [[ ! -f "$ZIP_PATH" ]] || [[ ! -s "$ZIP_PATH" ]]; then
    echo -e "\n  ${RED}✗ Download failed.${RESET}"
    exit 1
fi

SIZE_KB=$(( $(stat -f%z "$ZIP_PATH" 2>/dev/null || echo 0) / 1024 ))
echo -e "  ${DIM}Saved: ${SIZE_KB} KB${RESET}"

# Step 3 — extract
step "Extracting…"
spinner_start "Unzipping…"
mkdir -p "$EXTRACT_DIR"
unzip -q -o "$ZIP_PATH" -d "$EXTRACT_DIR" 2>/dev/null
spinner_stop

# Find the .app bundle inside the extract directory
APP_PATH=$(find "$EXTRACT_DIR" -name "*.app" -maxdepth 2 -type d | head -1)
if [[ -z "$APP_PATH" ]]; then
    echo -e "\n  ${RED}✗ Could not find MacDraw.app inside the archive.${RESET}"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} Extracted"

# Step 4 — launch the native installer
step "Launching installer…"
echo -e "  ${DIM}A window will open — click Install to add MacDraw to Applications.${RESET}"
echo ""

# Launch in --install mode
"$APP_PATH/Contents/MacOS/macdraw" --install &
INSTALLER_PID=$!

# Wait for the installer window to close
wait "$INSTALLER_PID" 2>/dev/null

echo ""
echo -e "  ${GREEN}${BOLD}✓ Done!${RESET} MacDraw is installed.${RESET}"
echo ""
