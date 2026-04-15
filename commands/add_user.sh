#!/usr/bin/env bash
# commands/add_user.sh — add a new user to the shared setup

cmd_add_user_usage() {
  cat <<'EOF'
Usage: claude-share add-user <username> [--password <pw>]

If --password is omitted, you will be prompted (hidden input).
If the user already exists, the password step is skipped.
EOF
}

cmd_add_user() {
  require_root
  require_initialized

  local uname="" upw="" upw_given=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --password) upw="$2"; upw_given=1; shift 2 ;;
      -h|--help)  cmd_add_user_usage; return 0 ;;
      -*)         die "unknown flag: $1" ;;
      *)          if [[ -z "$uname" ]]; then uname="$1"; shift; else die "unexpected arg: $1"; fi ;;
    esac
  done
  [[ -n "$uname" ]] || { cmd_add_user_usage; die "username required"; }

  if user_exists "$uname"; then
    log "User $uname already exists; linking to shared setup"
  else
    if [[ $upw_given -eq 0 ]]; then
      upw="$(prompt_password "password for $uname")" || die "password entry failed"
    fi
    ensure_user "$uname"
    set_user_password "$uname" "$upw"
    ok "Set password for $uname"
    unset upw
  fi

  ensure_user_in_group "$uname" "$SHARE_GROUP"
  ensure_group_umask "$uname"
  link_user_to_shared "$uname"
  ok "Linked $uname to shared auth"

  # Update managed list (dedup)
  local u present=0
  for u in "${MANAGED_USERS[@]}"; do
    [[ "$u" == "$uname" ]] && present=1
  done
  if [[ $present -eq 0 ]]; then
    MANAGED_USERS+=("$uname")
    save_config
  fi
}
