# tailserve 🚀

An interactive Terminal UI (TUI) manager for **Tailscale Serve** and **Tailscale Funnel**, complete with built-in boot persistence via systemd.

## Features
* **Interactive TUI:** Built with Charm's `gum` for clean, easy menu navigation.
* **Tailnet & Public Routing:** Easily proxy local ports internally (`tailscale serve`) or publicly (`tailscale funnel`).
* **Persistent Reboots:** Optionally bind any route to automatically restore on system startup using native systemd oneshot services.
* **Live Status Dashboard:** Instantly view all active routes, target ports, and persistence markers in real time.

---

## Installation Guide

Clone or download this repository onto your server or host:

```bash
git clone [https://github.com/yourusername/tailserve.git](https://github.com/yourusername/tailserve.git)
cd tailserve
