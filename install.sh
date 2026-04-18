#!/usr/bin/env bash
# install.sh — download and install claude-share
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yiancode/claude-share/main/install.sh | sudo bash
#
# Or, if you already have a local clone:
#   sudo ./install.sh

set -Eeuo pipefail

PREFIX="${PREFIX:-/usr/local}"
REPO_URL="${REPO_URL:-https://github.com/yiancode/claude-share.git}"
REF="${REF:-main}"
INSTALL_DIR="$PREFIX/lib/claude-share"
BIN_LINK="$PREFIX/bin/claude-share"
CS_LINK="$PREFIX/bin/cs"

if [[ $EUID -ne 0 ]]; then
  echo "install.sh must be run as root (try: sudo $0)" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$script_dir/bin/claude-share" ]]; then
  # Installing from a local checkout.
  src="$script_dir"
else
  # Fetch from GitHub.
  command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$tmp/claude-share"
  src="$tmp/claude-share"
fi

install -d -m 755 "$INSTALL_DIR"
cp -a "$src/bin" "$src/lib" "$src/commands" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/bin/claude-share"
chmod +x "$INSTALL_DIR/bin/cs"

install -d -m 755 "$(dirname "$BIN_LINK")"
ln -sfn "$INSTALL_DIR/bin/claude-share" "$BIN_LINK"
ln -sfn "$INSTALL_DIR/bin/cs" "$CS_LINK"

echo "Installed claude-share to $INSTALL_DIR"
echo "Symlinked $BIN_LINK"
echo "Symlinked $CS_LINK"
echo ""
echo "Next step:"
echo "  Server: sudo claude-share server init"
echo "  Client: claude-share client init <user@host>"
echo "  Daily : cd /your/project && cs live"
