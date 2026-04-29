#!/usr/bin/env bash
# commands/init.sh — first-time setup

cmd_init_usage() {
  cat <<'EOF'
Usage: claude-share init [options]

Options:
  --shared-dir <path>         Shared directory (default: /shared/claude-share)
  --group <name>              Shared POSIX group (default: claudeshare)
  --source-user <name>        User whose ~/.claude is the auth source
                              (default: invoking user, or SUDO_USER, or root)
  --user <name>               Non-interactive: create/link <name>, prompting
                              for password if the user doesn't exist.
                              May repeat.
  --users-from-file <path>    Non-interactive: read lines of the form
                              name:password (one per line, '#' comments ok)
                              from <path>. File must be mode 0600 and owned
                              by root. Safer than --user name:pw — passwords
                              never touch argv. May combine with --user.
  --no-settings-local         Do NOT share settings.local.json
  --yes                       Assume yes to confirmations
  -h, --help                  Show this help

Note: the legacy form --user name:password is still accepted for backwards
compatibility, but the password will briefly appear in the process argv and
be visible to `ps`. Prefer --users-from-file for automation.
EOF
}

# Names we'll pass to useradd/groupadd must match POSIX "portable" rules,
# otherwise we get confusing upstream errors. Locked down on purpose.
_cs_valid_unix_name() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}\$?$ ]]
}
_cs_valid_abs_path() {
  [[ "$1" == /* ]] && [[ "$1" != *$'\n'* ]]
}

cmd_init() {
  require_root

  local shared_dir="/shared/claude-share"
  local share_group="claudeshare"
  local source_user="${SUDO_USER:-root}"
  local share_settings_local="true"
  local assume_yes=0
  # User names to create/link. Passwords are NOT stored here — they're
  # either resolved interactively or read from a 0600 file on demand.
  local -a user_names=()
  # Parallel array of password sources: "prompt" | "file:<path>" | "argv:<pw>"
  # "argv" entries come from the legacy --user name:pw form and are
  # accepted under protest (warning printed at parse time).
  local -a user_pw_sources=()
  local users_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --shared-dir)
        shared_dir="$2"; shift 2 ;;
      --group)
        share_group="$2"; shift 2 ;;
      --source-user)
        source_user="$2"; shift 2 ;;
      --user)
        local spec="$2" uname upw_src
        if [[ "$spec" == *:* ]]; then
          uname="${spec%%:*}"
          upw_src="argv:${spec#*:}"
          warn "--user name:password is insecure (password visible to ps); prefer --users-from-file"
        else
          uname="$spec"
          upw_src="prompt"
        fi
        user_names+=("$uname")
        user_pw_sources+=("$upw_src")
        shift 2 ;;
      --users-from-file)
        users_file="$2"; shift 2 ;;
      --no-settings-local) share_settings_local="false"; shift ;;
      --yes|-y)           assume_yes=1; shift ;;
      -h|--help)          cmd_init_usage; return 0 ;;
      *)                  die "unknown flag: $1 (see --help)" ;;
    esac
  done

  # Validate identifiers before we use them as arguments to system tools.
  _cs_valid_abs_path "$shared_dir" \
    || die "--shared-dir must be an absolute path: $shared_dir"
  _cs_valid_unix_name "$share_group" \
    || die "invalid --group name: $share_group"
  _cs_valid_unix_name "$source_user" \
    || die "invalid --source-user: $source_user"
  local _uname
  for _uname in "${user_names[@]}"; do
    _cs_valid_unix_name "$_uname" \
      || die "invalid --user name: $_uname"
  done

  # --users-from-file: read name:password lines. File must be 0600 and
  # owned by root so we can be sure no other user saw its contents.
  if [[ -n "$users_file" ]]; then
    [[ -f "$users_file" ]] || die "--users-from-file: not a file: $users_file"
    local mode owner
    mode="$(stat -c '%a' "$users_file")" || die "cannot stat $users_file"
    owner="$(stat -c '%u' "$users_file")" || die "cannot stat $users_file"
    [[ "$mode" == "600" ]] || die "$users_file must be mode 0600 (got $mode)"
    [[ "$owner" == "0"  ]] || die "$users_file must be owned by root (uid 0)"
    local line uname_from_file
    while IFS= read -r line || [[ -n "$line" ]]; do
      # skip blanks and comments
      [[ -z "${line// }" ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" == *:* ]] || die "bad line in $users_file (expected name:password): $line"
      uname_from_file="${line%%:*}"
      _cs_valid_unix_name "$uname_from_file" \
        || die "invalid user name in $users_file: $uname_from_file"
      user_names+=("$uname_from_file")
      # Stash the raw line's password portion. This is only held until
      # the create loop consumes it, and the whole array is unset at the
      # end. We cannot avoid holding it in memory somewhere.
      user_pw_sources+=("file:${line#*:}")
    done < "$users_file"
  fi

  if [[ -f "$CS_CONFIG_FILE" ]]; then
    warn "claude-share is already initialized (config: $CS_CONFIG_FILE)"
    # Protect against silently orphaning an old shared dir by re-pointing
    # at a new one. Force the operator to uninstall first.
    if [[ -n "${SHARED_DIR:-}" && "${SHARED_DIR}" != "$shared_dir" ]]; then
      err "existing config points at shared-dir=$SHARED_DIR but --shared-dir=$shared_dir was given."
      err "That would orphan the old shared dir. Run 'claude-share uninstall --purge-shared-dir' first."
      die "refusing to silently re-point shared-dir"
    fi
    if [[ $assume_yes -eq 0 ]]; then
      prompt_yes_no "Reinitialize?" n || die "aborted"
    fi
  fi

  # Interactive setup for values that weren't provided on cmdline
  if [[ $assume_yes -eq 0 && ${#user_names[@]} -eq 0 ]]; then
    shared_dir="$(prompt_default "Shared directory" "$shared_dir")"
    share_group="$(prompt_default "Shared group" "$share_group")"
    source_user="$(prompt_default "Source user (holds current ~/.claude auth)" "$source_user")"
    _cs_valid_abs_path "$shared_dir" || die "shared-dir must be absolute: $shared_dir"
    _cs_valid_unix_name "$share_group" || die "invalid group name: $share_group"
    _cs_valid_unix_name "$source_user" || die "invalid source-user: $source_user"
  fi

  user_exists "$source_user" || die "source user does not exist: $source_user"
  local src_home
  src_home="$(user_home "$source_user")"
  if [[ ! -f "$src_home/.claude/.credentials.json" ]]; then
    # Refuse to seed a shared dir from a source user who has never logged
    # in. Historically we'd create a zero-byte placeholder and warn; in
    # practice that meant every managed user's first `claude` run tried
    # to parse an empty file as JSON. Fail-fast with actionable guidance.
    err "$source_user has no ~/.claude/.credentials.json yet."
    err "Run 'claude /login' as $source_user first, then re-run init."
    die "source user is not authenticated"
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

  # If neither --user nor --users-from-file was given, drop into the
  # interactive flow. We deliberately do NOT populate any array with
  # passwords — each prompt is consumed immediately.
  if [[ ${#user_names[@]} -eq 0 ]]; then
    local count
    count="$(prompt_default "How many users to create now?" "2")"
    local i iname
    for ((i=1; i<=count; i++)); do
      iname="$(prompt_default "  user $i name" "")"
      [[ -z "$iname" ]] && die "username cannot be empty"
      _cs_valid_unix_name "$iname" || die "invalid user name: $iname"
      user_names+=("$iname")
      user_pw_sources+=("prompt")
    done
  fi

  # Create users. The password (if any) lives in a single local variable
  # per iteration and is unset before the next loop runs. It never enters
  # a persistent array.
  local idx=0 uname src upw
  while (( idx < ${#user_names[@]} )); do
    uname="${user_names[$idx]}"
    src="${user_pw_sources[$idx]}"
    idx=$((idx + 1))

    if user_exists "$uname"; then
      case "$src" in
        prompt)
          log "user $uname already exists; linking without changing password"
          ;;
        *)
          warn "user $uname already exists; ignoring supplied password"
          ;;
      esac
      upw=""
    else
      case "$src" in
        prompt)
          upw="$(prompt_password "  password for $uname")" \
            || die "password entry failed"
          ;;
        file:*)
          upw="${src#file:}"
          ;;
        argv:*)
          upw="${src#argv:}"
          ;;
        *)
          die "internal: unknown password source: $src"
          ;;
      esac
      ensure_user "$uname"
      if [[ -n "$upw" ]]; then
        set_user_password "$uname" "$upw"
        ok "Set password for $uname"
      fi
    fi
    # Scrub the password and its source entry ASAP.
    unset upw
    user_pw_sources[$((idx - 1))]=""

    ensure_user_in_group "$uname" "$SHARE_GROUP"
    ensure_group_umask "$uname"
    link_user_to_shared "$uname"
    ok "Linked $uname to shared auth"
    MANAGED_USERS+=("$uname")
  done
  # Drop the password-source array entirely — nothing sensitive should
  # survive this point.
  unset user_pw_sources

  save_config
  ok "Wrote config: $CS_CONFIG_FILE"
  log "Done. Managed users: ${MANAGED_USERS[*]}"
  # usermod -aG only takes effect for NEW sessions. Warn loudly so the
  # operator doesn't spend an hour debugging why an already-logged-in
  # shell can't see the claudeshare group.
  warn "Managed users must log out and log back in before 'claude' will see the new group."
}
