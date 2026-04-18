#!/usr/bin/env bash
# commands/server.sh — server-side multi-user workflow surface.

cmd_server_usage() {
  cat <<'EOF'
Usage: claude-share server <subcommand> [options]

Subcommands:
  init         Initialize shared Claude auth and managed users.
  add-user     Add another managed Linux user.
  remove-user  Remove a managed user from the shared setup.
  status       Show server-side status and health checks.
  sync         Re-apply shared links for all managed users.
  uninstall    Undo the shared-auth server setup.
EOF
}

cmd_server() {
  local subcmd="${1:-}"
  [[ $# -gt 0 ]] && shift

  case "$subcmd" in
    init)
      # shellcheck source=../commands/init.sh
      source "$CMD_DIR/init.sh"
      cmd_init "$@"
      ;;
    add-user|add_user)
      # shellcheck source=../commands/add_user.sh
      source "$CMD_DIR/add_user.sh"
      cmd_add_user "$@"
      ;;
    remove-user|remove_user)
      # shellcheck source=../commands/remove_user.sh
      source "$CMD_DIR/remove_user.sh"
      cmd_remove_user "$@"
      ;;
    status)
      # shellcheck source=../commands/status.sh
      source "$CMD_DIR/status.sh"
      cmd_status "$@"
      ;;
    sync)
      # shellcheck source=../commands/sync.sh
      source "$CMD_DIR/sync.sh"
      cmd_sync "$@"
      ;;
    uninstall)
      # shellcheck source=../commands/uninstall.sh
      source "$CMD_DIR/uninstall.sh"
      cmd_uninstall "$@"
      ;;
    help|--help|-h|"")
      cmd_server_usage
      ;;
    *)
      die "unknown server subcommand: $subcmd"
      ;;
  esac
}
