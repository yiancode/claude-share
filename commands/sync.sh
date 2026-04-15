#!/usr/bin/env bash
# commands/sync.sh — re-apply symlinks for all managed users.
# Useful if a user accidentally broke one of the links, or if we added a new
# item to SHARED_ITEMS in an upgrade.

cmd_sync() {
  require_root
  require_initialized

  bootstrap_shared_dir
  seed_shared_from_source_user

  local u
  for u in "${MANAGED_USERS[@]}"; do
    if ! user_exists "$u"; then
      warn "skipping non-existent user $u"
      continue
    fi
    ensure_user_in_group "$u" "$SHARE_GROUP"
    ensure_group_umask "$u"
    link_user_to_shared "$u"
    ok "resynced $u"
  done
}
