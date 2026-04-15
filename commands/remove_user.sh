#!/usr/bin/env bash
# commands/remove_user.sh — detach a user from the shared setup.
# Does NOT delete the Linux account by default.

cmd_remove_user_usage() {
  cat <<'EOF'
Usage: claude-share remove-user <username> [--delete-account]

Detaches the user:
  - unlinks shared symlinks and copies the current shared files into place,
  - removes user from the shared group,
  - updates config.

--delete-account  ALSO delete the Linux user account with userdel -r.
                  Destructive. Defaults to off.
EOF
}

cmd_remove_user() {
  require_root
  require_initialized

  local uname="" delete_account=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --delete-account) delete_account=1; shift ;;
      -h|--help)        cmd_remove_user_usage; return 0 ;;
      -*)               die "unknown flag: $1" ;;
      *)                if [[ -z "$uname" ]]; then uname="$1"; shift; else die "unexpected arg: $1"; fi ;;
    esac
  done
  [[ -n "$uname" ]] || { cmd_remove_user_usage; die "username required"; }

  if ! user_exists "$uname"; then
    warn "no such user: $uname"
    return 0
  fi

  unlink_user_from_shared "$uname"
  remove_user_from_group "$uname" "$SHARE_GROUP"
  ok "Detached $uname from shared auth"

  # Update managed list
  local -a kept=()
  local u
  for u in "${MANAGED_USERS[@]}"; do
    [[ "$u" == "$uname" ]] || kept+=("$u")
  done
  MANAGED_USERS=("${kept[@]}")
  save_config

  if [[ $delete_account -eq 1 ]]; then
    warn "Deleting Linux account $uname (userdel -r)"
    userdel -r "$uname" || warn "userdel failed (maybe active sessions?)"
  fi
}
