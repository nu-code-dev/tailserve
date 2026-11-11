#!/usr/bin/env bash
set -euo pipefail

PROXMOX_MODE=0

for arg in "$@"; do
    case "$arg" in
        --proxmox)
            PROXMOX_MODE=1
            shift
            ;;
    esac
done

echo "===> Detecting operating system..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
else
    OS_ID="unknown"
fi

echo "Detected OS: $OS_ID"

echo "===> Installing dependencies (jq & curl)..."
if [ "$PROXMOX_MODE" -eq 1 ]; then
    apt update && apt install -y jq curl gpg
elif [ "$OS_ID" = "arch" ]; then
    sudo pacman -Syu --noconfirm jq curl
elif [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ] || [ "$OS_ID" = "proxmox" ]; then
    sudo apt update && sudo apt install -y jq curl gpg
else
    echo "Warning: Unsupported or unknown OS '$OS_ID'. Attempting standard apt/pacman commands..."
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y jq curl gpg
    elif command -v pacman &>/dev/null; then
        sudo pacman -Syu --noconfirm jq curl
    else
        echo "Error: Could not automatically install dependencies. Please install jq and curl manually."
        exit 1
    fi
fi

echo "===> Installing Charm 'gum'..."
if [ "$PROXMOX_MODE" -eq 1 ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
    apt update && apt install -y gum
elif [ "$OS_ID" = "arch" ]; then
    sudo pacman -S --noconfirm gum
else
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install -y gum
fi

echo "===> Installing tailserve binary..."
SCRIPT_PATH="/usr/local/bin/tailserve"

# Select the correct source script based on mode
if [ "$PROXMOX_MODE" -eq 1 ]; then
    SRC_SCRIPT="tailserve-proxmox.sh"
else
    SRC_SCRIPT="tailserve.sh"
fi

if [ ! -f "$SRC_SCRIPT" ]; then
    echo "Error: Source script '$SRC_SCRIPT' not found in current directory."
    exit 1
fi

if [ "$PROXMOX_MODE" -eq 1 ]; then
    cp "$SRC_SCRIPT" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
else
    sudo cp "$SRC_SCRIPT" "$SCRIPT_PATH"
    sudo chmod +x "$SCRIPT_PATH"
fi

echo "===> Checking shell environments..."
CURRENT_SHELL="$(basename "$SHELL")"
if [ "$CURRENT_SHELL" = "fish" ]; then
    echo "Detected fish shell. Setting up global executable path lookup..."
    fish -c "set -l" >/dev/null 2>&1 || true
fi

echo ""
echo "Installation complete! Run your utility using: tailserve (or sudo tailserve)"
