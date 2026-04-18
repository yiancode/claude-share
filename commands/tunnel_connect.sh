#!/usr/bin/env bash
# commands/tunnel_connect.sh — one-shot bootstrap + serve on the local machine.

cmd_tunnel_connect_usage() {
  cat <<'EOF'
Usage: claude-share tunnel connect --server <user@host> [options]

This is a one-shot local command that runs:
  1. `claude-share tunnel bootstrap`
  2. `claude-share tunnel serve`

Options:
  --server <user@host>    Remote SSH destination.
  --workspace <path>      Local workspace to publish. Default: current directory.
  --password <password>   Optional bootstrap password for first-time setup.
  --identity-file <path>  SSH key used for bootstrap + serve.
                          Default: ~/.ssh/claude-share-<server-slug>
  --local-prefix <path>   Local install prefix for bootstrap. Default: ~/.local
  --remote-prefix <path>  Remote install prefix for bootstrap. Default: ~/.local
  --session <name>        Session name passed to `tunnel serve`.
  --remote-port <port>    Remote loopback port for reverse tunnel.
  --local-sshd-port <port>
                          Local sshd port. Default: 22
  --remote-mount <path>   Suggested remote mountpoint.
  --read-only             Ask the server to mount read-only.
  -h, --help              Show this help.
EOF
}

cmd_tunnel_connect() {
  local server="" workspace="$PWD" password="" identity_file=""
  local local_prefix="$HOME/.local" remote_prefix='$HOME/.local'
  local session="" remote_port="" local_sshd_port="" remote_mount=""
  local read_only=0
  local -a bootstrap_args=() serve_args=()

  # shellcheck source=../commands/tunnel_bootstrap.sh
  source "$CMD_DIR/tunnel_bootstrap.sh"
  # shellcheck source=../commands/tunnel_serve.sh
  source "$CMD_DIR/tunnel_serve.sh"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --server)          server="$2"; shift 2 ;;
      --workspace)       workspace="$2"; shift 2 ;;
      --password)        password="$2"; shift 2 ;;
      --identity-file)   identity_file="$2"; shift 2 ;;
      --local-prefix)    local_prefix="$2"; shift 2 ;;
      --remote-prefix)   remote_prefix="$2"; shift 2 ;;
      --session)         session="$2"; shift 2 ;;
      --remote-port)     remote_port="$2"; shift 2 ;;
      --local-sshd-port) local_sshd_port="$2"; shift 2 ;;
      --remote-mount)    remote_mount="$2"; shift 2 ;;
      --read-only)       read_only=1; shift ;;
      -h|--help)         cmd_tunnel_connect_usage; return 0 ;;
      *)                 die "unknown flag: $1" ;;
    esac
  done

  [[ -n "$server" ]] || die "--server is required"
  [[ -n "$identity_file" ]] || identity_file="$(cmd_tunnel_default_identity_file "$server")"

  bootstrap_args=(
    --server "$server"
    --identity-file "$identity_file"
    --local-prefix "$local_prefix"
    --remote-prefix "$remote_prefix"
  )
  [[ -n "$password" ]] && bootstrap_args+=(--password "$password")

  serve_args=(
    --workspace "$workspace"
    --server "$server"
    --ssh-arg -i
    --ssh-arg "$identity_file"
    --ssh-arg -o
    --ssh-arg StrictHostKeyChecking=no
    --ssh-arg -o
    --ssh-arg UserKnownHostsFile=/dev/null
  )
  [[ -n "$session" ]] && serve_args+=(--session "$session")
  [[ -n "$remote_port" ]] && serve_args+=(--remote-port "$remote_port")
  [[ -n "$local_sshd_port" ]] && serve_args+=(--local-sshd-port "$local_sshd_port")
  [[ -n "$remote_mount" ]] && serve_args+=(--remote-mount "$remote_mount")
  [[ $read_only -eq 1 ]] && serve_args+=(--read-only)

  log "Step 1/2: bootstrap"
  cmd_tunnel_bootstrap "${bootstrap_args[@]}"
  printf '\n'

  if [[ -z "$remote_port" ]]; then
    remote_port="$(tunnel_pick_remote_port "$server" "$identity_file")" \
      || die "failed to auto-pick a free remote port on $server"
    log "Auto-selected remote port: $remote_port"
  fi

  serve_args+=(--remote-port "$remote_port")
  log "Step 2/2: serve"
  cmd_tunnel_serve "${serve_args[@]}"
}
