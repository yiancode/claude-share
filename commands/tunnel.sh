#!/usr/bin/env bash
# commands/tunnel.sh — reverse SSH tunnel command group.

cmd_tunnel_usage() {
  cat <<'EOF'
Usage: claude-share tunnel <subcommand> [options]

Subcommands:
  bootstrap Install/update claude-share on both ends, seed an SSH key for the
            remote host, and verify the local sshd + remote prerequisites.
  connect  Run bootstrap and then immediately start serve with the generated
           key-based SSH arguments.
  serve    Run on your local machine. Opens the reverse SSH tunnel and
           publishes a workspace to the server.
  mount    Run on the server. Mounts the local workspace via sshfs and
           prepares command wrappers that proxy execution back home.
  umount   Run on the server. Unmounts a mounted workspace session.
  status   Show local or server-side tunnel session status.
EOF
}

cmd_tunnel() {
  local subcmd="${1:-}"
  [[ $# -gt 0 ]] && shift

  case "$subcmd" in
    bootstrap)
      # shellcheck source=../commands/tunnel_bootstrap.sh
      source "$CMD_DIR/tunnel_bootstrap.sh"
      cmd_tunnel_bootstrap "$@"
      ;;
    connect)
      # shellcheck source=../commands/tunnel_connect.sh
      source "$CMD_DIR/tunnel_connect.sh"
      cmd_tunnel_connect "$@"
      ;;
    serve)
      # shellcheck source=../commands/tunnel_serve.sh
      source "$CMD_DIR/tunnel_serve.sh"
      cmd_tunnel_serve "$@"
      ;;
    mount)
      # shellcheck source=../commands/tunnel_mount.sh
      source "$CMD_DIR/tunnel_mount.sh"
      cmd_tunnel_mount "$@"
      ;;
    umount|unmount)
      # shellcheck source=../commands/tunnel_umount.sh
      source "$CMD_DIR/tunnel_umount.sh"
      cmd_tunnel_umount "$@"
      ;;
    status)
      # shellcheck source=../commands/tunnel_status.sh
      source "$CMD_DIR/tunnel_status.sh"
      cmd_tunnel_status "$@"
      ;;
    help|--help|-h|"")
      cmd_tunnel_usage
      ;;
    *)
      die "unknown tunnel subcommand: $subcmd"
      ;;
  esac
}
