#!/usr/bin/env bash
# commands/tunnel_mount.sh — server-side sshfs mount and exec wrapper setup.

cmd_tunnel_mount_usage() {
  cat <<'EOF'
Usage: claude-share tunnel mount --session <name> [--mountpoint <path>]

Options:
  --session <name>     Session name created by `tunnel serve`.
  --mountpoint <path>  Absolute mountpoint on the server.
  -h, --help           Show this help.
EOF
}

cmd_tunnel_mount() {
  local session="" mountpoint="" session_dir="" manifest=""
  local remote_spec="" mode="rw" read_only="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session)    session="$2"; shift 2 ;;
      --mountpoint) mountpoint="$2"; shift 2 ;;
      -h|--help)    cmd_tunnel_mount_usage; return 0 ;;
      *)            die "unknown flag: $1" ;;
    esac
  done

  [[ -n "$session" ]] || die "--session is required"
  tunnel_require_session_name "$session"
  tunnel_require_cmd ssh sshfs

  session_dir="$(tunnel_remote_session_dir "$session")"
  manifest="$session_dir/manifest.env"
  tunnel_load_state_file "$manifest" || die "missing manifest: $manifest"

  [[ -n "$mountpoint" ]] || mountpoint="${SUGGESTED_MOUNTPOINT:-$(tunnel_default_mount_root)/$session}"
  [[ "$mountpoint" == /* ]] || die "--mountpoint must be absolute"

  remote_spec="${LOCAL_USER}@127.0.0.1:${WORKSPACE}"
  mode="${MODE:-rw}"
  read_only="${READ_ONLY:-false}"

  mkdir -p "$(dirname "$mountpoint")"
  install -d -m 755 "$mountpoint"

  if tunnel_mount_is_active "$mountpoint"; then
    die "mountpoint is already active: $mountpoint"
  fi

  local -a sshfs_args=(
    -p "$REMOTE_PORT"
    -o "IdentityFile=$IDENTITY_FILE"
    -o IdentitiesOnly=yes
    -o "UserKnownHostsFile=${KNOWN_HOSTS:-$session_dir/known_hosts}"
    -o StrictHostKeyChecking=accept-new
    -o reconnect
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=3
  )
  if [[ "$read_only" == "true" ]]; then
    sshfs_args+=(-o ro)
  fi

  sshfs "$remote_spec" "$mountpoint" "${sshfs_args[@]}"
  tunnel_write_state_files "$session_dir" \
    SESSION "$session" \
    STATUS "mounted" \
    SERVER "${SERVER:-<unknown>}" \
    WORKSPACE "$WORKSPACE" \
    MOUNTPOINT "$mountpoint" \
    LOCAL_USER "$LOCAL_USER" \
    REMOTE_PORT "$REMOTE_PORT" \
    IDENTITY_FILE "$IDENTITY_FILE" \
    KNOWN_HOSTS "${KNOWN_HOSTS:-$session_dir/known_hosts}" \
    MODE "$mode"

  tunnel_write_remote_exec_bundle "$session_dir"

  printf '%s Mounted workspace\n' "$CS_TAG"
  tunnel_print_kv "session" "$session"
  tunnel_print_kv "mountpoint" "$mountpoint"
  tunnel_print_kv "workspace" "$WORKSPACE"
  tunnel_print_kv "mode" "$mode"
  printf '\n'
  log "Enable proxied execution in this shell:"
  printf '  source %q/env.sh\n' "$session_dir"
  log "Or jump into a prepared shell:"
  printf '  %q/enter-shell\n' "$session_dir"
}
