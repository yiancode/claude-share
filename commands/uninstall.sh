#!/usr/bin/env bash
# commands/uninstall.sh — undo the shared-auth setup.
# Does NOT delete Linux users.

cmd_uninstall_usage() {
  cat <<'EOF'
Usage: claude-share uninstall [--yes] [--purge-shared-dir]

  --yes               Skip confirmations.
  --purge-shared-dir  Delete the shared directory after detaching users.
                      Off by default (keeps a backup of credentials).
EOF
}

cmd_uninstall() {
  require_root
  require_initialized

  local assume_yes=0 purge=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y)          assume_yes=1; shift ;;
      --purge-shared-dir) purge=1; shift ;;
      -h|--help)         cmd_uninstall_usage; return 0 ;;
      *)                 die "unknown flag: $1" ;;
    esac
  done

  if [[ $assume_yes -eq 0 ]]; then
    log "This will detach all managed users from the shared auth dir:"
    log "  managed users : ${MANAGED_USERS[*]:-<none>}"
    log "  shared dir    : $SHARED_DIR"
    prompt_yes_no "Continue?" n || die "aborted"
  fi

  local u
  for u in "${MANAGED_USERS[@]}"; do
    unlink_user_from_shared "$u"
    remove_user_from_group "$u" "$SHARE_GROUP"
    ok "detached $u"
  done

  if [[ $purge -eq 1 ]]; then
    if [[ -d "$SHARED_DIR" ]]; then
      rm -rf "$SHARED_DIR"
      ok "removed $SHARED_DIR"
    fi
    if getent group "$SHARE_GROUP" >/dev/null; then
      groupdel "$SHARE_GROUP" 2>/dev/null || warn "could not delete group $SHARE_GROUP"
    fi
  fi

  rm -f "$CS_CONFIG_FILE"
  ok "removed $CS_CONFIG_FILE"
  log "Uninstall complete. Linux user accounts were left in place."
}
