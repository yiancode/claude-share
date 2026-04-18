#!/usr/bin/env bash
# commands/tunnel_status.sh — local/remote tunnel status display.

cmd_tunnel_status_usage() {
  cat <<'EOF'
Usage: claude-share tunnel status [--session <name>]

Without --session, lists discovered local and remote session directories.
With --session, prints the most relevant local and/or remote state.
EOF
}

_cmd_tunnel_status_show_local() {
  local session_dir="$1"
  tunnel_load_state_file "$session_dir/session.env" || return 1

  printf '%s Local session\n' "$CS_TAG"
  tunnel_print_kv "session" "$SESSION"
  tunnel_print_kv "status" "$STATUS"
  tunnel_print_kv "server" "$SERVER"
  tunnel_print_kv "workspace" "$WORKSPACE"
  tunnel_print_kv "remote port" "$REMOTE_PORT"
  if [[ -n "${SSH_PID:-}" ]] && kill -0 "$SSH_PID" >/dev/null 2>&1; then
    tunnel_print_kv "ssh pid" "$SSH_PID (running)"
  else
    tunnel_print_kv "ssh pid" "${SSH_PID:-<none>}"
  fi
}

_cmd_tunnel_status_show_remote() {
  local session_dir="$1"
  if ! tunnel_load_state_file "$session_dir/session.env"; then
    tunnel_load_state_file "$session_dir/manifest.env" || return 1
  fi

  printf '%s Remote session\n' "$CS_TAG"
  tunnel_print_kv "session" "$SESSION"
  tunnel_print_kv "workspace" "$WORKSPACE"
  tunnel_print_kv "remote port" "$REMOTE_PORT"
  if [[ -n "${MOUNTPOINT:-}" ]]; then
    tunnel_print_kv "mountpoint" "$MOUNTPOINT"
    if tunnel_mount_is_active "$MOUNTPOINT"; then
      tunnel_print_kv "mount status" "mounted"
    else
      tunnel_print_kv "mount status" "not-mounted"
    fi
  else
    tunnel_print_kv "mount status" "manifest-only"
  fi
}

cmd_tunnel_status() {
  local session="" local_dir="" remote_dir="" found=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      -h|--help) cmd_tunnel_status_usage; return 0 ;;
      *)         die "unknown flag: $1" ;;
    esac
  done

  if [[ -z "$session" ]]; then
    printf '%s Known local sessions\n' "$CS_TAG"
    if [[ -d "$(tunnel_local_root)" ]]; then
      find "$(tunnel_local_root)" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
      found=1
    else
      printf '  <none>\n'
    fi
    printf '\n'
    printf '%s Known remote sessions\n' "$CS_TAG"
    if [[ -d "$(tunnel_remote_root)" ]]; then
      find "$(tunnel_remote_root)" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
      found=1
    else
      printf '  <none>\n'
    fi
    return 0
  fi

  tunnel_require_session_name "$session"
  local_dir="$(tunnel_local_session_dir "$session")"
  remote_dir="$(tunnel_remote_session_dir "$session")"

  if [[ -f "$local_dir/session.env" ]]; then
    _cmd_tunnel_status_show_local "$local_dir"
    printf '\n'
    found=1
  fi

  if [[ -f "$remote_dir/session.env" || -f "$remote_dir/manifest.env" ]]; then
    _cmd_tunnel_status_show_remote "$remote_dir"
    found=1
  fi

  [[ $found -eq 1 ]] || die "no session state found for: $session"
}
