#!/usr/bin/env bash
# tunnel_exec.sh — server-side wrapper bundle that proxies commands home.

TUNNEL_PROXY_COMMANDS=(
  bash sh zsh
  git
  node npm npx pnpm yarn bun
  python python3 pip pip3 pytest uv
  go cargo rustc
  make cmake
  java javac
  docker docker-compose
)

tunnel_write_remote_exec_bundle() {
  local session_dir="$1"
  local bin_dir="$session_dir/bin"
  local cmd

  tunnel_load_state_file "$session_dir/session.env" \
    || die "missing session state for exec bundle: $session_dir/session.env"
  install -d -m 700 "$bin_dir"

  cat > "$bin_dir/exec-proxy" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd -P "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
SESSION_DIR="$(cd -P "$SELF_DIR/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=/dev/null
source "$SESSION_DIR/session.env"

cmd="$(basename "$0")"
if [[ "$cmd" == "exec-proxy" ]]; then
  [[ $# -gt 0 ]] || {
    echo "usage: exec-proxy <command> [args...]" >&2
    exit 2
  }
  cmd="$1"
  shift
fi

cwd="${PWD:-$MOUNTPOINT}"
case "$cwd" in
  "$MOUNTPOINT")
    target_cwd="$WORKSPACE"
    ;;
  "$MOUNTPOINT"/*)
    target_cwd="$WORKSPACE/${cwd#"$MOUNTPOINT"/}"
    ;;
  *)
    target_cwd="$WORKSPACE"
    ;;
esac

known_hosts="${KNOWN_HOSTS:-$SESSION_DIR/known_hosts}"
ssh_tty_flag="-T"
quoted_remote_cmd="$(printf 'cd %q && exec %q' "$target_cwd" "$cmd")"

if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    quoted_remote_cmd+=" $(printf '%q' "$arg")"
  done
fi

case "$cmd" in
  bash|sh|zsh)
    if [[ -t 0 && -t 1 ]]; then
      ssh_tty_flag="-tt"
    fi
    ;;
esac

exec ssh \
  "$ssh_tty_flag" \
  -p "$REMOTE_PORT" \
  -i "$IDENTITY_FILE" \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$known_hosts" \
  -o LogLevel=ERROR \
  "${LOCAL_USER}@127.0.0.1" \
  "bash -lc $(printf '%q' "$quoted_remote_cmd")"
EOF
  chmod 755 "$bin_dir/exec-proxy"

  for cmd in "${TUNNEL_PROXY_COMMANDS[@]}"; do
    ln -sfn exec-proxy "$bin_dir/$cmd"
  done

  cat > "$session_dir/env.sh" <<EOF
# claude-share tunnel environment
export CLAUDE_SHARE_TUNNEL_SESSION=$(printf '%q' "$SESSION")
export CLAUDE_SHARE_TUNNEL_MOUNTPOINT=$(printf '%q' "$MOUNTPOINT")
export CLAUDE_SHARE_TUNNEL_WORKSPACE=$(printf '%q' "$WORKSPACE")
case ":\$PATH:" in
  *:$(printf '%q' "$bin_dir"):*) ;;
  *) export PATH=$(printf '%q' "$bin_dir")":\$PATH" ;;
esac
EOF
  chmod 644 "$session_dir/env.sh"

  cat > "$session_dir/enter-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SESSION_DIR="$(cd -P "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=/dev/null
source "$SESSION_DIR/env.sh"
cd "$CLAUDE_SHARE_TUNNEL_MOUNTPOINT"
exec "${SHELL:-bash}"
EOF
  chmod 755 "$session_dir/enter-shell"
}
