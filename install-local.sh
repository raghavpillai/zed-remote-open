#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing zed-listener (local Mac)..."

mkdir -p "$HOME/.local/bin"

cp "$SCRIPT_DIR/zed-listener" "$HOME/.local/bin/zed-listener"
chmod +x "$HOME/.local/bin/zed-listener"

# Install launchd service
cp "$SCRIPT_DIR/com.zed.remote-listener.plist" "$HOME/Library/LaunchAgents/com.zed.remote-listener.plist"

# Load/reload the service
launchctl bootout "gui/$(id -u)/com.zed.remote-listener" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.zed.remote-listener.plist"

echo "==> zed-listener is running."
echo ""
echo "Next steps:"
echo "  1. Add 'RemoteForward 7682 127.0.0.1:7682' to your SSH host in ~/.ssh/config"
echo "  2. Install zed-remote on your server (copy zed-remote to ~/.local/bin/zed)"
echo "  3. Set ZED_SSH_HOST on the server to your SSH config alias"
