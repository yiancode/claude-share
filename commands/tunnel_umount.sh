#!/usr/bin/env bash
# commands/tunnel_umount.sh — server-side session unmount.

cmd_tunnel_umount_usage() {
  cat <<'EOF'
Usage: claude-share tunnel umount --session <name>

Options:
  --session <name>  Session name to unmount.
  -h, --help        Show this help.
EOF
}

cmd_tunnel_umount() {
  local session="" session_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      -h|--help) cmd_tunnel_umount_usage; return 0 ;;
      *)         die "unknown flag: $1" ;;
    esac
  done

  [[ -n "$session" ]] || die "--session is required"
  tunnel_require_session_name "$session"

  session_dir="$(tunnel_remote_session_dir "$session")"
  tunnel_load_state_file "$session_dir/session.env" \
    || die "missing mounted session state: $session_dir/session.env"

  if tunnel_mount_is_active "$MOUNTPOINT"; then
    tunnel_unmount_path "$MOUNTPOINT"
  else
    warn "mountpoint is not active: $MOUNTPOINT"
  fi

  rm -rf "${session_dir:?}/bin"
  rm -f "$session_dir/env.sh" "$session_dir/enter-shell" "$session_dir/known_hosts"

  tunnel_write_state_files "$session_dir" \
    SESSION "$SESSION" \
    STATUS "closed" \
    SERVER "$SERVER" \
    WORKSPACE "$WORKSPACE" \
    MOUNTPOINT "$MOUNTPOINT" \
    LOCAL_USER "$LOCAL_USER" \
    REMOTE_PORT "$REMOTE_PORT" \
    IDENTITY_FILE "$IDENTITY_FILE" \
    KNOWN_HOSTS "$KNOWN_HOSTS" \
    MODE "$MODE"

  ok "Unmounted session: $SESSION"
}
