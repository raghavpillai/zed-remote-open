# Zed Remote Open (`zed .` over SSH)

Opens a Zed remote project from a remote SSH session, similar to `code .` with VS Code.

Built on top of [Zed's native remote development](https://zed.dev/docs/remote-development), which already supports `zed ssh://host/path` from the local CLI. This just bridges the gap so you can run `zed .` from the remote side too.

## How it works

```
You (SSH'd into my-server)
  │
  │  zed .
  │
  ▼
~/.local/bin/zed (on my-server)
  │  Sends "my-server:/current/dir" to localhost:7682
  │
  ▼
SSH Reverse Tunnel (RemoteForward 7682)
  │  Forwards remote:7682 → local Mac:7682
  │
  ▼
~/.local/bin/zed-listener (on Mac, launchd service)
  │  Receives request, runs: zed ssh://my-server/current/dir
  │
  ▼
Zed opens with a remote SSH project at that directory
```

## Usage

From an SSH session on your remote server:

```bash
zed .           # open current directory in Zed
zed /some/path  # open specific path in Zed
zed             # same as zed .
```

## All files

### Local Mac

#### 1. `~/.local/bin/zed-listener`

Python TCP server. Listens on port 7682 for `host:directory` messages and opens Zed remote projects.

```python
#!/usr/bin/env python3
"""Listener that opens Zed remote projects from SSH sessions.

Runs on the local Mac. Remote machines send requests via SSH reverse
port forwarding to open a Zed remote project at a specific directory.

Protocol: single line "host:directory\n" over TCP.
"""

import socket
import subprocess
import signal
import sys

PORT = 7682


def handle_request(data):
    data = data.strip()
    if ":" not in data:
        return
    host, directory = data.split(":", 1)
    if not host or not directory:
        return
    subprocess.Popen(["/usr/local/bin/zed", f"ssh://{host}{directory}"])


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", PORT))
    sock.listen(5)

    while True:
        conn, _ = sock.accept()
        try:
            data = conn.recv(4096).decode("utf-8", errors="replace")
            handle_request(data)
        except Exception:
            pass
        finally:
            conn.close()


if __name__ == "__main__":
    main()
```

#### 2. `~/Library/LaunchAgents/com.zed.remote-listener.plist`

Launchd service that auto-starts `zed-listener` on login and keeps it running.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.zed.remote-listener</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Users/raghav/.local/bin/zed-listener</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/zed-listener.err</string>
</dict>
</plist>
```

#### 3. `~/.ssh/config` (relevant addition)

The `RemoteForward` line creates a reverse tunnel: anything connecting to port 7682 on the remote server gets forwarded back to port 7682 on your Mac.

```
Host my-server
    HostName <ip-or-hostname>
    User <username>
    RemoteForward 7682 127.0.0.1:7682
```

### Remote server

#### 4. `~/.local/bin/zed`

The command you actually type. Resolves the target directory to an absolute path and sends it through the reverse tunnel via netcat.

```bash
#!/bin/bash
# Open a Zed remote project on the local machine via reverse SSH tunnel.
# Usage: zed [directory]  (defaults to current directory)
#
# ZED_SSH_HOST must be set to the SSH config alias for this server.
# Set it in your shell config, e.g.: export ZED_SSH_HOST="my-server"

dir="${1:-.}"
dir=$(cd "$dir" 2>/dev/null && pwd) || { echo "zed: cannot access '$1'"; exit 1; }

host="${ZED_SSH_HOST:-$(hostname)}"

echo "${host}:${dir}" | nc -q0 127.0.0.1 7682 2>/dev/null
if [ $? -ne 0 ]; then
    echo "zed: could not connect to local listener on port 7682" >&2
    echo "  Make sure zed-listener is running and SSH has RemoteForward 7682" >&2
    exit 1
fi
echo "Opening Zed at $dir"
```

## Adding another server

1. Add `RemoteForward 7682 127.0.0.1:7682` to that host in `~/.ssh/config`
2. Copy `zed-remote` to `~/.local/bin/zed` on the remote server
3. Set `export ZED_SSH_HOST="<ssh-alias>"` in the server's `.bashrc`

## Troubleshooting

**`zed: could not connect to local listener on port 7682`**
- Check the listener is running: `ps aux | grep zed-listener`
- Restart it: `launchctl kickstart -k gui/$(id -u)/com.zed.remote-listener`
- Check logs: `cat /tmp/zed-listener.err`

**`Warning: remote port forwarding failed for listen port 7682`**
- Harmless. Means another SSH session already has the tunnel. The existing tunnel still works.

**Zed opens but doesn't connect**
- Test directly: `zed ssh://your-host/home/user`
- Make sure Zed's remote development is working (see [Zed docs](https://zed.dev/docs/remote-development))

## Why it works this way

Zed already supports `zed ssh://host/path` natively, so the listener just calls that directly. No helper scripts needed on the local side.

The listener uses the full path `/usr/local/bin/zed` because launchd runs with a minimal PATH and won't find `zed` otherwise.

Port 7682 (one above the Ghostty listener at 7681). Change it in the listener, SSH config, and remote script if needed.
