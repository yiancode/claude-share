#!/usr/bin/env bash
# commands/init.sh — first-time setup

cmd_init_usage() {
  cat <<'EOF'
Usage: claude-share init [options]

Options:
  --shared-dir <path>     Shared directory (default: /shared/claude-share)
  --group <name>          Shared POSIX group (default: claudeshare)
  --source-user <name>    User whose ~/.claude is the auth source
                          (default: invoking user, or SUDO_USER, or root)
  --user <name>:<pw>      Non-interactive user creation. May repeat.
                          Password may be omitted (will prompt).
  --no-settings-local     Do NOT share settings.local.json
  --yes                   Assume yes to confirmations
  -h, --help              Show this help
EOF
}

cmd_init() {
  require_root

  local shared_dir="/shared/claude-share"
  local share_group="claudeshare"
  local source_user="${SUDO_USER:-root}"
  local share_settings_local="true"
  local assume_yes=0
  local -a user_specs=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --shared-dir)       shared_dir="$2"; shift 2 ;;
      --group)            share_group="$2"; shift 2 ;;
      --source-user)      source_user="$2"; shift 2 ;;
      --user)             user_specs+=("$2"); shift 2 ;;
      --no-settings-local) share_settings_local="false"; shift ;;
      --yes|-y)           assume_yes=1; shift ;;
      -h|--help)          cmd_init_usage; return 0 ;;
      *)                  die "unknown flag: $1 (see --help)" ;;
    esac
  done

  if [[ -f "$CS_CONFIG_FILE" ]]; then
    warn "claude-share is already initialized (config: $CS_CONFIG_FILE)"
    if [[ $assume_yes -eq 0 ]]; then
      prompt_yes_no "Reinitialize?" n || die "aborted"
    fi
  fi

  # Interactive setup for values that weren't provided on cmdline
  if [[ $assume_yes -eq 0 && ${#user_specs[@]} -eq 0 ]]; then
    shared_dir="$(prompt_default "Shared directory" "$shared_dir")"
    share_group="$(prompt_default "Shared group" "$share_group")"
    source_user="$(prompt_default "Source user (holds current ~/.claude auth)" "$source_user")"
  fi

  user_exists "$source_user" || die "source user does not exist: $source_user"
  local src_home
  src_home="$(user_home "$source_user")"
  if [[ ! -f "$src_home/.claude/.credentials.json" ]]; then
    warn "$source_user has no ~/.claude/.credentials.json yet"
    warn "You will need to run 'claude /login' as $source_user at least once"
    warn "before other users can use the shared credentials."
  fi

  # Export for lib/sync.sh and save_config
  SHARED_DIR="$shared_dir"
  SHARE_GROUP="$share_group"
  SOURCE_USER="$source_user"
  # shellcheck disable=SC2034
  SHARE_SETTINGS_LOCAL="$share_settings_local"
  MANAGED_USERS=()

  log "Creating shared group and directory..."
  ensure_group "$SHARE_GROUP"
  ensure_user_in_group "$SOURCE_USER" "$SHARE_GROUP"
  ensure_group_umask "$SOURCE_USER"

  bootstrap_shared_dir
  seed_shared_from_source_user
  # The source user's own files just got moved into the shared dir. Link
  # them back so "claude" as $SOURCE_USER still finds its config.
  link_user_to_shared "$SOURCE_USER"
  ok "Shared dir ready: $SHARED_DIR"

  # Collect users to create
  if [[ ${#user_specs[@]} -eq 0 ]]; then
    local count
    count="$(prompt_default "How many users to create now?" "2")"
    local i
    for ((i=1; i<=count; i++)); do
      local uname upw
      uname="$(prompt_default "  user $i name" "")"
      [[ -z "$uname" ]] && die "username cannot be empty"
      if user_exists "$uname"; then
        warn "user $uname already exists; will link to shared dir without changing password"
        user_specs+=("$uname:")
      else
        upw="$(prompt_password "  user $i password")" || die "password entry failed"
        user_specs+=("$uname:$upw")
        # Unset local variable as soon as it's consumed
        unset upw
      fi
    done
  fi

  # Create users
  local spec uname upw
  for spec in "${user_specs[@]}"; do
    uname="${spec%%:*}"
    upw="${spec#*:}"
    [[ "$uname" == "$spec" ]] && upw=""  # no colon
    ensure_user "$uname"
    if [[ -n "$upw" ]]; then
      set_user_password "$uname" "$upw"
      ok "Set password for $uname"
    fi
    ensure_user_in_group "$uname" "$SHARE_GROUP"
    ensure_group_umask "$uname"
    link_user_to_shared "$uname"
    ok "Linked $uname to shared auth"
    MANAGED_USERS+=("$uname")
    unset upw
  done

  save_config
  ok "Wrote config: $CS_CONFIG_FILE"
  log "Done. Managed users: ${MANAGED_USERS[*]}"
}
