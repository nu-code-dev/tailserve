# tailserve 🚀

An interactive Terminal UI (TUI) manager for **Tailscale Serve** and **Tailscale Funnel**, complete with built-in boot persistence via systemd.

## Features
* **Interactive TUI:** Built with Charm's `gum` for clean, easy menu navigation.
* **Tailnet & Public Routing:** Easily proxy local ports internally (`tailscale serve`) or publicly (`tailscale funnel`).
* **Persistent Reboots:** Optionally bind any route to automatically restore on system startup using native systemd oneshot services.
* **Live Status Dashboard:** Instantly view all active routes, target ports, and persistence markers in real time.

---

## Prerequisites

Make sure you have the following packages installed on your Linux system:
* [Tailscale](https://tailscale.com/) (logged in and running)
* [`gum`](https://github.com/charmbracelet/gum) (for interactive prompts)
* [`jq`](https://jqlang.github.io/jq/) (for parsing JSON status responses)

### Quick Dependency Install (Debian / Ubuntu)
```bash
# Install jq
sudo apt update && sudo apt install -y jq

# Install Charm gum
sudo mkdir -p /etc/apt/keyrings
curl -fsSL [https://repo.charm.sh/apt/gpg.key](https://repo.charm.sh/apt/gpg.key) | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] [https://repo.charm.sh/apt/](https://repo.charm.sh/apt/) * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install -y gum
