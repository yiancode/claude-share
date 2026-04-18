#!/usr/bin/env bash
# commands/tunnel_serve.sh — local foreground reverse tunnel session.

cmd_tunnel_serve_usage() {
  cat <<'EOF'
Usage: claude-share tunnel serve --workspace <abs-path> --server <user@host> [options]

Options:
  --workspace <path>        Absolute local workspace path to publish.
  --server <user@host>      SSH destination for the server.
  --session <name>          Session name (default: derived from workspace + time).
  --remote-port <port>      Remote loopback port on the server (default: 43022).
  --local-sshd-port <port>  Local sshd port (default: 22).
  --remote-mount <path>     Suggested server-side mountpoint.
  --ssh-arg <arg>           Extra SSH arg. May repeat.
  --read-only               Ask the server to mount read-only.
  -h, --help                Show this help.
EOF
}

cmd_tunnel_serve() {
  local workspace="" server="" session="" remote_port="43022"
  local local_sshd_port="22" suggested_mount="" read_only="false"
  local remote_home="" remote_dir="" local_dir="" key_file="" ssh_pid=""
  local mode="rw" ssh_log="" local_user="" rc=0
  CS_TUNNEL_SERVE_SSH_ARGS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)       workspace="$2"; shift 2 ;;
      --server)          server="$2"; shift 2 ;;
      --session)         session="$2"; shift 2 ;;
      --remote-port)     remote_port="$2"; shift 2 ;;
      --local-sshd-port) local_sshd_port="$2"; shift 2 ;;
      --remote-mount)    suggested_mount="$2"; shift 2 ;;
      --ssh-arg)         CS_TUNNEL_SERVE_SSH_ARGS+=("$2"); shift 2 ;;
      --read-only)       read_only="true"; mode="ro"; shift ;;
      -h|--help)         cmd_tunnel_serve_usage; return 0 ;;
      *)                 die "unknown flag: $1" ;;
    esac
  done

  [[ -n "$workspace" ]] || die "--workspace is required"
  [[ -n "$server" ]] || die "--server is required"
  workspace="$(tunnel_resolve_workspace "$workspace")"
  [[ -n "$session" ]] || session="$(tunnel_generate_session_name "$workspace")"
  tunnel_require_session_name "$session"
  if [[ -n "$suggested_mount" && "$suggested_mount" != /* ]]; then
    die "--remote-mount must be absolute"
  fi
  [[ "$remote_port" =~ ^[0-9]+$ ]] || die "--remote-port must be numeric"
  [[ "$local_sshd_port" =~ ^[0-9]+$ ]] || die "--local-sshd-port must be numeric"

  tunnel_require_cmd ssh ssh-keygen
  tunnel_port_open_localhost "$local_sshd_port" \
    || die "local sshd is not reachable on 127.0.0.1:$local_sshd_port"

  local_user="${USER:-$(id -un)}"
  local_dir="$(tunnel_local_session_dir "$session")"
  tunnel_ensure_private_dir "$(tunnel_local_root)"
  tunnel_ensure_private_dir "$local_dir"
  ssh_log="$local_dir/ssh.log"

  CS_TUNNEL_SERVE_CLEANUP_RAN=0
  CS_TUNNEL_SERVE_CLEANUP_SESSION="$session"
  CS_TUNNEL_SERVE_CLEANUP_SERVER="$server"
  CS_TUNNEL_SERVE_CLEANUP_REMOTE_DIR=""
  CS_TUNNEL_SERVE_CLEANUP_SSH_PID=""
  CS_TUNNEL_SERVE_CLEANUP_STARTUP_COMPLETE=0

  _cmd_tunnel_serve_invoke_ssh_helper() {
    local fn="$1"
    shift
    if (( ${#CS_TUNNEL_SERVE_SSH_ARGS[@]} > 0 )); then
      "$fn" "$@" "${CS_TUNNEL_SERVE_SSH_ARGS[@]}"
    else
      "$fn" "$@"
    fi
  }

  _cmd_tunnel_serve_cleanup() {
    [[ "${CS_TUNNEL_SERVE_CLEANUP_RAN:-0}" -eq 1 ]] && return 0
    CS_TUNNEL_SERVE_CLEANUP_RAN=1
    if [[ -n "${CS_TUNNEL_SERVE_CLEANUP_SSH_PID:-}" ]] && kill -0 "${CS_TUNNEL_SERVE_CLEANUP_SSH_PID}" >/dev/null 2>&1; then
      kill "${CS_TUNNEL_SERVE_CLEANUP_SSH_PID}" >/dev/null 2>&1 || true
      wait "${CS_TUNNEL_SERVE_CLEANUP_SSH_PID}" >/dev/null 2>&1 || true
    fi
    if [[ "${CS_TUNNEL_SERVE_CLEANUP_STARTUP_COMPLETE:-0}" -eq 0 && -n "${CS_TUNNEL_SERVE_CLEANUP_REMOTE_DIR:-}" ]]; then
      _cmd_tunnel_serve_invoke_ssh_helper \
        tunnel_remote_remove_dir \
        "${CS_TUNNEL_SERVE_CLEANUP_SERVER}" \
        "${CS_TUNNEL_SERVE_CLEANUP_REMOTE_DIR}" || true
    fi
    if [[ -n "${CS_TUNNEL_SERVE_CLEANUP_SESSION:-}" ]]; then
      tunnel_remove_authorized_key "${CS_TUNNEL_SERVE_CLEANUP_SESSION}"
    fi
  }

  trap _cmd_tunnel_serve_cleanup EXIT INT TERM

  key_file="$(tunnel_prepare_keypair "$local_dir" "$session")"
  tunnel_install_authorized_key "$session" "$key_file.pub"

  remote_home="$(_cmd_tunnel_serve_invoke_ssh_helper tunnel_fetch_remote_home "$server")" \
    || die "failed to query remote home via ssh: $server"
  remote_dir="$remote_home/.claude-share/remote/$session"
  CS_TUNNEL_SERVE_CLEANUP_REMOTE_DIR="$remote_dir"
  [[ -n "$suggested_mount" ]] || suggested_mount="$remote_home/.claude-share/mounts/$session"
  _cmd_tunnel_serve_invoke_ssh_helper tunnel_remote_install_dir "$server" "$remote_dir" \
    || die "failed to prepare remote session dir: $remote_dir"

  cat > "$local_dir/manifest.env" <<EOF
SESSION=$(printf '%q' "$session")
WORKSPACE=$(printf '%q' "$workspace")
LOCAL_USER=$(printf '%q' "$local_user")
REMOTE_PORT=$(printf '%q' "$remote_port")
READ_ONLY=$(printf '%q' "$read_only")
MODE=$(printf '%q' "$mode")
SUGGESTED_MOUNTPOINT=$(printf '%q' "$suggested_mount")
IDENTITY_FILE=$(printf '%q' "$remote_dir/id_ed25519")
KNOWN_HOSTS=$(printf '%q' "$remote_dir/known_hosts")
SERVER=$(printf '%q' "$server")
EOF
  chmod 600 "$local_dir/manifest.env"
  _cmd_tunnel_serve_invoke_ssh_helper tunnel_copy_file_to_remote "$server" "$key_file" "$remote_dir/id_ed25519" \
    || die "failed to copy tunnel private key to remote host"
  _cmd_tunnel_serve_invoke_ssh_helper tunnel_copy_file_to_remote "$server" "$key_file.pub" "$remote_dir/id_ed25519.pub" \
    || die "failed to copy tunnel public key to remote host"
  _cmd_tunnel_serve_invoke_ssh_helper tunnel_copy_file_to_remote "$server" "$local_dir/manifest.env" "$remote_dir/manifest.env" \
    || die "failed to copy tunnel manifest to remote host"

  tunnel_write_state_files "$local_dir" \
    SESSION "$session" \
    STATUS "starting" \
    SERVER "$server" \
    WORKSPACE "$workspace" \
    REMOTE_PORT "$remote_port" \
    LOCAL_SSHD_PORT "$local_sshd_port" \
    REMOTE_DIR "$remote_dir" \
    MODE "$mode" \
    SSH_PID ""

  if (( ${#CS_TUNNEL_SERVE_SSH_ARGS[@]} > 0 )); then
    tunnel_start_reverse_ssh \
      "$server" "$remote_port" "$local_sshd_port" "$ssh_log" \
      "${CS_TUNNEL_SERVE_SSH_ARGS[@]}"
  else
    tunnel_start_reverse_ssh \
      "$server" "$remote_port" "$local_sshd_port" "$ssh_log"
  fi
  ssh_pid="$CS_TUNNEL_LAST_SSH_PID"
  CS_TUNNEL_SERVE_CLEANUP_SSH_PID="$ssh_pid"
  printf '%s\n' "$ssh_pid" > "$local_dir/ssh.pid"

  sleep 1
  kill -0 "$ssh_pid" >/dev/null 2>&1 || die "reverse tunnel exited early; see $ssh_log"
  _cmd_tunnel_serve_invoke_ssh_helper tunnel_wait_for_remote_port "$server" "$remote_port" \
    || die "reverse tunnel did not become reachable on the server"

  tunnel_write_state_files "$local_dir" \
    SESSION "$session" \
    STATUS "ready" \
    SERVER "$server" \
    WORKSPACE "$workspace" \
    REMOTE_PORT "$remote_port" \
    LOCAL_SSHD_PORT "$local_sshd_port" \
    REMOTE_DIR "$remote_dir" \
    MODE "$mode" \
    SSH_PID "$ssh_pid"
  CS_TUNNEL_SERVE_CLEANUP_STARTUP_COMPLETE=1

  printf '%s Tunnel ready\n' "$CS_TAG"
  tunnel_print_kv "session" "$session"
  tunnel_print_kv "workspace" "$workspace"
  tunnel_print_kv "server" "$server"
  tunnel_print_kv "remote port" "$remote_port"
  tunnel_print_kv "mode" "$mode"
  printf '\n'
  log "On the server, run:"
  printf '  claude-share tunnel mount --session %q\n' "$session"
  printf '\n'
  log "Then enable proxy wrappers in that shell:"
  printf '  source %q/env.sh && cd %q && claude\n' "$remote_dir" "$suggested_mount"
  printf '\n'
  warn "Keep this process running. When it exits, the reverse tunnel closes."

  wait "$ssh_pid" || rc=$?
  trap - EXIT INT TERM
  _cmd_tunnel_serve_cleanup

  if [[ $rc -eq 0 ]]; then
    tunnel_write_state_files "$local_dir" \
      SESSION "$session" \
      STATUS "closed" \
      SERVER "$server" \
      WORKSPACE "$workspace" \
      REMOTE_PORT "$remote_port" \
      LOCAL_SSHD_PORT "$local_sshd_port" \
      REMOTE_DIR "$remote_dir" \
      MODE "$mode" \
      SSH_PID ""
  else
    tunnel_write_state_files "$local_dir" \
      SESSION "$session" \
      STATUS "degraded" \
      SERVER "$server" \
      WORKSPACE "$workspace" \
      REMOTE_PORT "$remote_port" \
      LOCAL_SSHD_PORT "$local_sshd_port" \
      REMOTE_DIR "$remote_dir" \
      MODE "$mode" \
      SSH_PID ""
    err "reverse tunnel stopped unexpectedly; see $ssh_log"
  fi

  return "$rc"
}
