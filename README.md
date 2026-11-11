# tailserve 🚀

An interactive Terminal UI (TUI) manager for **Tailscale Serve** and **Tailscale Funnel**, complete with built-in boot persistence via systemd.

## Features
* **Interactive TUI:** Built with Charm's `gum` for clean, easy menu navigation.
* **Tailnet & Public Routing:** Easily proxy local ports internally (`tailscale serve`) or publicly (`tailscale funnel`).
* **Persistent Reboots:** Optionally bind any route to automatically restore on system startup using native systemd oneshot services.
* **Live Status Dashboard:** Instantly view all active routes, target ports, and persistence markers in real time.

---

## Installation Guide

Clone the repository onto your server or host and navigate into the folder:
```
git clone https://github.com/nu-code-dev/tailserve.git
cd tailserve
```

Give execution permissions to the installer script, then run it:
```
chmod +x install.sh
./install.sh
```

### Environment Options:
* **Standard Linux (Ubuntu / Debian with `sudo`):** Run `./install.sh` normally.
* **Proxmox Host (Root environment without `sudo`):** Pass the `--proxmox` flag to configure dependencies and paths correctly:
  ./install.sh --proxmox

---

## Usage

Once installed, you can launch the utility globally from any terminal window:

* **Standard Linux:** `sudo tailserve`
* **Proxmox Host:** `tailserve`

### Menu Options:
* **Add New Serve:** Proxy a local port securely across your private Tailnet.
* **Add New Funnel:** Expose a local port publicly to the open internet via Tailscale Funnel.
* **Toggle Persistence:** Switch active routes between temporary sessions and persistent boot-restored configurations.
* **Remove Route:** Safely tear down active proxies.
