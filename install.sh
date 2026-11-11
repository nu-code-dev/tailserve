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

echo "===> Installing dependencies (jq & curl)..."
if [ "$PROXMOX_MODE" -eq 1 ]; then
    apt update && apt install -y jq curl gpg
else
    sudo apt update && sudo apt install -y jq curl gpg
fi

echo "===> Installing Charm 'gum'..."
if [ "$PROXMOX_MODE" -eq 1 ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
    apt update && apt install -y gum
else
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install -y gum
fi

echo "===> Preparing script version..."
SCRIPT_PATH="/usr/local/bin/tailserve"

if [ "$PROXMOX_MODE" -eq 1 ]; then
    # Strip out sudo checks / replace with root verification for Proxmox
    sed 's/if \[ "\$EUID" -ne 0 \]; then/if [ "\$EUID" -ne 0 ]; then/' tailserve > "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "Successfully installed 'tailserve' for Proxmox mode (root execution)."
else
    cp tailserve "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "Successfully installed 'tailserve' for standard Linux environments."
done

echo ""
echo "Installation complete! Run your utility using: tailserve (or sudo tailserve)"
