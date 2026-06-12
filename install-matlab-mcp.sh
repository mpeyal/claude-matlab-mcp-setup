#!/usr/bin/env bash
# install-matlab-mcp.sh - one-click installer for macOS and Linux
# Connects Claude to MATLAB via the official MathWorks MCP server.
#   macOS : registers the server in Claude Desktop's config
#   Linux : registers the server in Claude Code (claude CLI), since
#           Claude Desktop is not available on Linux
# Usage:  bash install-matlab-mcp.sh
# Source: https://github.com/mpeyal/claude-matlab-mcp-setup
set -u

fail() { echo ""; echo "ERROR: $1" >&2; exit 1; }

OS=$(uname -s)
ARCH=$(uname -m)
echo "====================================================="
echo "  Claude + MATLAB MCP - installer ($OS $ARCH)"
echo "====================================================="

command -v python3 >/dev/null 2>&1 || fail "python3 is required (used to edit JSON safely)."
command -v curl    >/dev/null 2>&1 || fail "curl is required."

# --- 1. Pick the right binary pattern for this platform ----------------------
case "$OS" in
  Darwin)
    if [ "$ARCH" = "arm64" ]; then PAT='maca64|macos-arm64'; FALLBACK='matlab-mcp-core-server-maca64'
    else                           PAT='maci64|macos-x64';   FALLBACK='matlab-mcp-core-server-maci64'; fi ;;
  Linux)
    PAT='glnxa64|linux'; FALLBACK='matlab-mcp-core-server-glnxa64' ;;
  *) fail "Unsupported OS: $OS (use install-matlab-mcp.bat on Windows)" ;;
esac

# --- 2. Get the server binary (reuse if present, else download) --------------
INSTALL_DIR="$HOME/matlab-mcp"
mkdir -p "$INSTALL_DIR"
BIN=$(find "$INSTALL_DIR" -maxdepth 1 -type f -name 'matlab-mcp*' 2>/dev/null | head -1)

if [ -n "${BIN:-}" ]; then
  echo "Server binary already present: $BIN"
else
  echo "Downloading the official MathWorks MCP server from GitHub..."
  URL=$(curl -fsSL https://api.github.com/repos/matlab/matlab-mcp-core-server/releases/latest 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
        | grep -E "$PAT" | grep -v '\.exe' | head -1) || true
  [ -z "${URL:-}" ] && URL="https://github.com/matlab/matlab-mcp-core-server/releases/latest/download/$FALLBACK"
  BIN="$INSTALL_DIR/$(basename "$URL")"
  echo "  from: $URL"
  curl -fL --retry 3 -o "$BIN" "$URL" || fail "Download failed. Check your connection, or download the $OS binary manually from https://github.com/matlab/matlab-mcp-core-server/releases/latest into $INSTALL_DIR and rerun."
  SIZE=$(wc -c < "$BIN" | tr -d ' ')
  [ "$SIZE" -gt 5000000 ] || fail "Downloaded file looks too small ($SIZE bytes) - probably a failed download. Delete $BIN and rerun."
  chmod +x "$BIN"
  [ "$OS" = "Darwin" ] && xattr -d com.apple.quarantine "$BIN" 2>/dev/null
  echo "Downloaded: $BIN"
fi

# Sanity check
if "$BIN" --version >/dev/null 2>&1; then
  echo "Server check OK (version: $("$BIN" --version 2>/dev/null | head -1))"
else
  echo "Warning: could not verify the binary, continuing anyway."
fi

# --- 3. Locate MATLAB ---------------------------------------------------------
MATLAB_ROOT=""
if [ "$OS" = "Darwin" ]; then
  MATLAB_ROOT=$(ls -d /Applications/MATLAB_R20*.app 2>/dev/null | sort -r | head -1)
else
  MATLAB_ROOT=$(ls -d /usr/local/MATLAB/R20* 2>/dev/null | sort -r | head -1)
fi
if [ -n "$MATLAB_ROOT" ]; then
  echo "MATLAB found: $MATLAB_ROOT"
else
  echo "MATLAB not found in the default location."
  printf "Enter your MATLAB root folder (or press Enter to let the server search PATH): "
  read -r MATLAB_ROOT
fi

# --- 4. Register the server ----------------------------------------------------
if [ "$OS" = "Darwin" ]; then
  # Claude Desktop config
  CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  [ -f "$CONFIG" ] || fail "Claude Desktop config not found at: $CONFIG - is Claude Desktop installed and run at least once?"

  if pgrep -qi '^claude' 2>/dev/null || pgrep -qif 'Claude.app' 2>/dev/null; then
    echo "Claude is running and must be closed (it overwrites its config on exit)."
    printf "Quit Claude automatically now? (y/n) "
    read -r A
    if [ "$A" = "y" ]; then
      osascript -e 'quit app "Claude"' 2>/dev/null
      sleep 3
    else
      fail "Quit Claude, then rerun this script."
    fi
  fi

  cp "$CONFIG" "$CONFIG.backup"
  if python3 - "$CONFIG" "$BIN" "$MATLAB_ROOT" <<'PYEOF'
import json, sys
p, binp, root = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(p))
entry = {"command": binp, "args": (["--matlab-root", root] if root else [])}
cfg.setdefault("mcpServers", {})["MATLAB"] = entry
out = json.dumps(cfg, indent=2)
json.loads(out)  # validate
open(p, "w").write(out)
PYEOF
  then
    echo ""
    echo "SUCCESS: MATLAB MCP server registered in Claude Desktop."
    echo "  Server : $BIN"
    echo "  Config : $CONFIG (backup: $CONFIG.backup)"
    echo ""
    echo "Start Claude, check Settings -> Developer for MATLAB,"
    echo "then try in a chat: \"Run 2+2 in MATLAB\" (first call takes ~30 s)."
  else
    cp "$CONFIG.backup" "$CONFIG"
    fail "Failed to update the config. Your original config was restored."
  fi

else
  # Linux: Claude Desktop is not available - register with Claude Code instead
  if command -v claude >/dev/null 2>&1; then
    if [ -n "$MATLAB_ROOT" ]; then
      claude mcp add MATLAB -- "$BIN" --matlab-root "$MATLAB_ROOT" || fail "claude mcp add failed."
    else
      claude mcp add MATLAB -- "$BIN" || fail "claude mcp add failed."
    fi
    echo ""
    echo "SUCCESS: MATLAB MCP server registered in Claude Code."
    echo "Run 'claude' and try: \"Run 2+2 in MATLAB\""
  else
    echo ""
    echo "Claude Desktop is not available on Linux and the 'claude' CLI was not found."
    echo "The server binary is ready at: $BIN"
    echo "Add it to your MCP client's config manually, e.g.:"
    echo ""
    echo '  "mcpServers": {'
    echo '    "MATLAB": {'
    echo "      \"command\": \"$BIN\","
    if [ -n "$MATLAB_ROOT" ]; then
      echo "      \"args\": [\"--matlab-root\", \"$MATLAB_ROOT\"]"
    else
      echo '      "args": []'
    fi
    echo '    }'
    echo '  }'
  fi
fi
