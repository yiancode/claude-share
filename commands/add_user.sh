#!/usr/bin/env bash
# commands/add_user.sh — add a new user to the shared setup

cmd_add_user_usage() {
  cat <<'EOF'
Usage: claude-share add-user <username> [--password <pw>]
       claude-share add-user <username> --password-from-file <path>

If neither --password nor --password-from-file is given, you will be
prompted (hidden input). If the user already exists, the password step
is skipped.

--password <pw> works but the password is visible to `ps` while the
command runs. Prefer --password-from-file (0600, root-owned) for
automation.
EOF
}

cmd_add_user() {
  require_root
  require_initialized

  local uname="" upw="" upw_given=0 pw_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --password)
        upw="$2"; upw_given=1; shift 2
        warn "--password is insecure (visible to ps); prefer --password-from-file"
        ;;
      --password-from-file)
        pw_file="$2"; upw_given=1; shift 2 ;;
      -h|--help)  cmd_add_user_usage; return 0 ;;
      -*)         die "unknown flag: $1" ;;
      *)          if [[ -z "$uname" ]]; then uname="$1"; shift; else die "unexpected arg: $1"; fi ;;
    esac
  done
  [[ -n "$uname" ]] || { cmd_add_user_usage; die "username required"; }
  # Validate the username the same way init does — we're going to hand
  # it to useradd / usermod.
  if ! [[ "$uname" =~ ^[a-z_][a-z0-9_-]{0,31}\$?$ ]]; then
    die "invalid username: $uname"
  fi

  if [[ -n "$pw_file" ]]; then
    [[ -f "$pw_file" ]] || die "--password-from-file: not a file: $pw_file"
    local mode owner
    mode="$(stat -c '%a' "$pw_file")" || die "cannot stat $pw_file"
    owner="$(stat -c '%u' "$pw_file")" || die "cannot stat $pw_file"
    [[ "$mode" == "600" ]] || die "$pw_file must be mode 0600 (got $mode)"
    [[ "$owner" == "0"  ]] || die "$pw_file must be owned by root (uid 0)"
    # Read a single line, strip trailing newline.
    IFS= read -r upw < "$pw_file" || true
  fi

  if user_exists "$uname"; then
    log "User $uname already exists; linking to shared setup"
    unset upw
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
  warn "$uname must log out and log back in before 'claude' will see the new group."
}
