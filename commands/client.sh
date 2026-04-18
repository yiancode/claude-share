#!/usr/bin/env bash
# commands/client.sh — local client initialization/profile workflow surface.

cmd_client_usage() {
  cat <<'EOF'
Usage: claude-share client <subcommand> [options]

Subcommands:
  init     Initialize local client config and bootstrap the remote host.
  status   Show the saved local client profile.
EOF
}

cmd_client_init_usage() {
  cat <<'EOF'
Usage: claude-share client init <user@host> [options]

Options:
  --password <password>   Optional bootstrap password for first-time setup.
  --identity-file <path>  Local SSH key to seed on the remote host.
  --local-prefix <path>   Local install prefix. Default: ~/.local
  --remote-prefix <path>  Remote install prefix. Default: ~/.local
EOF
}

cmd_client_init() {
  local server="" password="" identity_file="" local_prefix="$HOME/.local"
  local remote_prefix='$HOME/.local'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --password)      password="$2"; shift 2 ;;
      --identity-file) identity_file="$2"; shift 2 ;;
      --local-prefix)  local_prefix="$2"; shift 2 ;;
      --remote-prefix) remote_prefix="$2"; shift 2 ;;
      -h|--help)       cmd_client_init_usage; return 0 ;;
      -*)              die "unknown flag: $1" ;;
      *)               [[ -z "$server" ]] || die "unexpected arg: $1"; server="$1"; shift ;;
    esac
  done

  [[ -n "$server" ]] || { cmd_client_init_usage; die "server is required"; }

  # shellcheck source=../commands/tunnel_bootstrap.sh
  source "$CMD_DIR/tunnel_bootstrap.sh"
  [[ -n "$identity_file" ]] || identity_file="$(cmd_tunnel_default_identity_file "$server")"

  local -a args=(
    --server "$server"
    --identity-file "$identity_file"
    --local-prefix "$local_prefix"
    --remote-prefix "$remote_prefix"
  )
  [[ -n "$password" ]] && args+=(--password "$password")

  cmd_tunnel_bootstrap "${args[@]}"
  client_save_profile "$server" "$identity_file" "$local_prefix" "$remote_prefix"
  ok "Saved client profile: $CS_CLIENT_CONFIG_FILE"
}

cmd_client_status() {
  client_require_profile
  printf '%s Client profile\n' "$CS_TAG"
  tunnel_print_kv "server" "$CLIENT_SERVER"
  tunnel_print_kv "identity file" "$CLIENT_IDENTITY_FILE"
  tunnel_print_kv "local prefix" "${CLIENT_LOCAL_PREFIX:-$HOME/.local}"
  tunnel_print_kv "remote prefix" "${CLIENT_REMOTE_PREFIX:-$HOME/.local}"
  printf '\n'
  printf '%s Extra mounts\n' "$CS_TAG"
  if [[ -f "$CS_CLIENT_EXTRA_MOUNTS_FILE" ]]; then
    sed 's/^/  /' "$CS_CLIENT_EXTRA_MOUNTS_FILE"
  else
    printf '  <none>\n'
  fi
}

cmd_client() {
  local subcmd="${1:-}"
  [[ $# -gt 0 ]] && shift

  case "$subcmd" in
    init)
      cmd_client_init "$@"
      ;;
    status)
      cmd_client_status "$@"
      ;;
    help|--help|-h|"")
      cmd_client_usage
      ;;
    *)
      die "unknown client subcommand: $subcmd"
      ;;
  esac
}
