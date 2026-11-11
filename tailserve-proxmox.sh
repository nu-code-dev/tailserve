#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PERSIST_DIR="/etc/tailscale-serve-persistent"
SERVICE_FILE="/etc/systemd/system/tailscale-serve-persistent.service"
RESTORE_SCRIPT="$PERSIST_DIR/restore.sh"

mkdir -p "$PERSIST_DIR"

for dep in tailscale gum jq; do
    if ! command -v "$dep" &>/dev/null; then
        echo "Error: '$dep' is required but not installed."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

list_web_routes() {
    tailscale serve status --json 2>/dev/null | jq -r '
    (.Web // {}) as $web |
    (.AllowFunnel // {}) as $allow |
    $web | to_entries[] |
    .key as $hostport |
    (($hostport | split(":") | .[-1]) // "443") as $port |
    ((.value.Handlers // {}) | to_entries[]) |
    [ (if ($allow[$hostport] == true) then "funnel" else "serve" end),
      $hostport, $port, .key, (.value.Proxy // .value.Text // "") ] | @tsv
    ' 2>/dev/null || true
}

build_cmd() { # $1 = serve|funnel, $2 = https port, $3 = path, $4 = target ip, $5 = target port
    local bin="$1" port="$2" path="$3" tip="$4" tport="$5"
    local cmd="tailscale $bin --bg"
    if [ -n "$port" ] && [ "$port" != "443" ]; then
        cmd="$cmd --https=$port"
    fi
    cmd="$cmd --set-path=$path http://$tip:$tport"
    printf '%s\n' "$cmd"
}

sanitize_id() {
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9_'
}

update_systemd_service() {
    local content marker cmd
    content=$'#!/usr/bin/env bash\n# Managed by tproxy (serve + funnel boot restore)\nset -u\n'

    for marker in "$PERSIST_DIR"/route_*.enabled "$PERSIST_DIR"/funnel_*.enabled; do
        if [ -f "$marker" ]; then
            cmd=$(cat "$marker")
            content+="$cmd"$'\n'
        fi
    done

    printf '%s' "$content" > "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"

    tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Tailscale Serve + Funnel Boot Restore
After=tailscaled.service
Wants=tailscaled.service

[Service]
Type=oneshot
ExecStart=$RESTORE_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tailscale-serve-persistent.service >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

add_route() { # $1 = serve|funnel, $2 = human label, $3 = marker prefix
    local bin="$1" human="$2" prefix="$3"
    local target_ip target_port route_path https_port cmd safe_id

    target_ip=$(gum input --placeholder "Target IP/host to forward to (default: 127.0.0.1):" || true)
    if [ -z "$target_ip" ]; then
        target_ip="127.0.0.1"
    fi

    target_port=$(gum input --placeholder "Target local port to proxy (e.g. 8000 or 3100):" || true)
    if [ -z "$target_port" ]; then
        echo "Cancelled."
        sleep 1
        return
    fi

    route_path=$(gum input --placeholder "URL path/name (Optional, press Enter for default '/'):" || true)
    if [ -z "$route_path" ]; then
        route_path="/"
    fi
    if [[ "$route_path" != /* ]]; then
        route_path="/$route_path"
    fi

    if [ "$bin" = "funnel" ]; then
        https_port=$(gum input --placeholder "Public HTTPS port: 443 (default), 8443, or 10000:" || true)
    else
        https_port=$(gum input --placeholder "Custom HTTPS port (Optional, press Enter for standard 443):" || true)
    fi

    cmd=$(build_cmd "$bin" "${https_port:-443}" "$route_path" "$target_ip" "$target_port")

    echo "Executing: $cmd"
    if ! eval "$cmd"; then
        echo "Failed to run: $cmd"
        echo "Tip: funnel requires HTTPS + funnel to be enabled for this node."
        sleep 2
        return
    fi

    safe_id=$(sanitize_id "${route_path}_${https_port:-443}_${target_ip}_${target_port}")

    if gum confirm "Make this $human persistent across reboots?"; then
        printf '%s\n' "$cmd" > "$PERSIST_DIR/${prefix}_${safe_id}.enabled"
        update_systemd_service
        echo "$human set to persistent!"
    else
        echo "Added as temporary $human."
    fi
    sleep 1.5
}

remove_route() { # $1 = serve|funnel, $2 = human label, $3 = marker prefix
    local bin="$1" human="$2" prefix="$3"
    local all choice rest hostport path port target target_clean target_ip target_port safe_id

    all=$(list_web_routes | awk -F'\t' -v k="$bin" '$1==k')
    if [ -z "$all" ]; then
        echo "No active $human routes to remove."
        sleep 1.5
        return
    fi

    choice=$(printf '%s\n' "$all" | \
        awk -F'\t' '{printf "%s | https://%s%s | %s\n", $1, $2, $4, $5}' | \
        gum choose --header="Select a $human route to stop:" || true)
    if [ -z "$choice" ]; then
        return
    fi

    rest=$(printf '%s\n' "$choice" | awk -F' \\| ' '{print $2}' | sed 's#^https://##')
    target=$(printf '%s\n' "$choice" | awk -F' \\| ' '{print $3}')

    hostport="${rest%%/*}"
    if [[ "$rest" == */* ]]; then
        path="/${rest#*/}"
    else
        path="/"
    fi
    port="${hostport##*:}"

    target_clean="${target#http://}"
    target_clean="${target_clean#https://}"
    target_ip="${target_clean%%:*}"
    target_port="${target_clean##*:}"

    if gum confirm "Stop $human on https://$hostport$path?"; then
        if [ "$bin" = "serve" ]; then
            tailscale serve --https="$port" --set-path="$path" off 2>/dev/null \
                || tailscale serve reset
        else
            tailscale funnel --https="$port" --set-path="$path" off 2>/dev/null \
                || tailscale funnel reset
        fi

        safe_id=$(sanitize_id "${path}_${port}_${target_ip}_${target_port}")
        rm -f "$PERSIST_DIR/${prefix}_${safe_id}.enabled"
        update_systemd_service
        echo "Removed $human route $path."
        sleep 1.5
    fi
}

toggle_persistence() { # $1 = serve|funnel, $2 = human label, $3 = marker prefix
    local bin="$1" human="$2" prefix="$3"
    local all choice rest hostport path port target target_clean target_ip target_port safe_id marker cmd

    all=$(list_web_routes | awk -F'\t' -v k="$bin" '$1==k')
    if [ -z "$all" ]; then
        echo "No active $human routes found."
        sleep 1.5
        return
    fi

    choice=$(printf '%s\n' "$all" | \
        awk -F'\t' '{printf "%s | https://%s%s | %s\n", $1, $2, $4, $5}' | \
        gum choose --header="Select a $human route to toggle boot persistence:" || true)
    if [ -z "$choice" ]; then
        return
    fi

    rest=$(printf '%s\n' "$choice" | awk -F' \\| ' '{print $2}' | sed 's#^https://##')
    target=$(printf '%s\n' "$choice" | awk -F' \\| ' '{print $3}')

    hostport="${rest%%/*}"
    if [[ "$rest" == */* ]]; then
        path="/${rest#*/}"
    else
        path="/"
    fi
    port="${hostport##*:}"

    target_clean="${target#http://}"
    target_clean="${target_clean#https://}"
    target_ip="${target_clean%%:*}"
    target_port="${target_clean##*:}"

    safe_id=$(sanitize_id "${path}_${port}_${target_ip}_${target_port}")
    marker="$PERSIST_DIR/${prefix}_${safe_id}.enabled"

    if [ -f "$marker" ]; then
        rm -f "$marker"
        echo "$human route set to TEMPORARY (will not restore on reboot)."
    else
        cmd=$(build_cmd "$bin" "$port" "$path" "$target_ip" "$target_port")
        printf '%s\n' "$cmd" > "$marker"
        echo "$human route set to PERSISTENT (will auto-start on reboot)."
    fi

    update_systemd_service
    sleep 1.5
}

print_status() {
    local routes serve_lines funnel_lines

    routes=$(list_web_routes)

    serve_lines=$(printf '%s\n' "$routes" | \
        awk -F'\t' '$1=="serve" {printf "  https://%s%s  ->  %s\n", $2, $4, $5}')
    funnel_lines=$(printf '%s\n' "$routes" | \
        awk -F'\t' '$1=="funnel" {printf "  https://%s%s  ->  %s   [PUBLIC]\n", $2, $4, $5}')

    if [ -n "$serve_lines" ]; then
        echo "SERVE ROUTES (tailnet only):"
        echo "$serve_lines"
    else
        echo "No active 'tailscale serve' proxies running."
    fi
    echo ""

    if [ -n "$funnel_lines" ]; then
        echo "FUNNEL ROUTES (public internet):"
        echo "$funnel_lines"
    else
        echo "No active 'tailscale funnel' routes running."
    fi
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

while true; do
    clear
    echo "================================================================="
    echo "            TAILSCALE SERVE + FUNNEL MANAGER                 "
    echo "================================================================="
    echo ""

    print_status

    echo ""
    echo "-----------------------------------------------------------------"
    echo "PERSISTENCE STATUS (Boot Auto-Start):"

    PERSIST_FOUND=0
    for f in "$PERSIST_DIR"/route_*.enabled "$PERSIST_DIR"/funnel_*.enabled; do
        if [ -f "$f" ]; then
            CMD=$(cat "$f")
            echo "  • $CMD [PERSISTENT]"
            PERSIST_FOUND=1
        fi
    done
    if [ "$PERSIST_FOUND" -eq 0 ]; then
        echo "  (No serve or funnel routes set to auto-start on boot)"
    fi

    echo "================================================================="
    echo ""

    ACTION=$(gum choose \
        "a) Add New Serve (Tailnet Only)" \
        "b) Add New Funnel (Public Internet)" \
        "p) Toggle Serve Persistence" \
        "F) Toggle Funnel Persistence" \
        "d) Remove a Serve Route" \
        "D) Remove a Funnel Route" \
        "r) Refresh Status" \
        "x) Reset ALL (Serve + Funnel)" \
        "q) Quit" || true)

    case "$ACTION" in
        "a) Add New Serve"*)
            add_route serve "serve route" "route"
            ;;
        "b) Add New Funnel"*)
            add_route funnel "funnel" "funnel"
            ;;
        "p) Toggle Serve"*)
            toggle_persistence serve "serve" "route"
            ;;
        "F) Toggle Funnel"*)
            toggle_persistence funnel "funnel" "funnel"
            ;;
        "d) Remove a Serve"*)
            remove_route serve "serve" "route"
            ;;
        "D) Remove a Funnel"*)
            remove_route funnel "funnel" "funnel"
            ;;
        "r) Refresh"*)
            continue
            ;;
        "x) Reset"*)
            if gum confirm "Stop ALL active tailscale serve AND funnel routes?"; then
                tailscale serve reset || true
                tailscale funnel reset || true
                rm -f "$PERSIST_DIR"/route_*.enabled "$PERSIST_DIR"/funnel_*.enabled
                update_systemd_service
                echo "Cleared all serves, funnels, and persistence."
                sleep 1.5
            fi
            ;;
        "q) Quit"|"")
            clear
            exit 0
            ;;
    esac
done
