#!/usr/bin/env bash
# paths.sh — canonical list of files Claude Code stores under $HOME
#
# SHARED_ITEMS are paths (relative to $HOME) that hold auth/global config and
# should be sharable across users via symlinks into $SHARED_DIR/home/.
#
# LOCAL_ITEMS are per-session / per-project runtime state that must NOT be
# shared. They are documented here so status/uninstall can verify nothing
# leaked into the shared dir.

# Always shared
SHARED_ITEMS_ALWAYS=(
  ".claude/.credentials.json"
  ".claude.json"
  ".claude/settings.json"
)

# Optionally shared (controlled by SHARE_SETTINGS_LOCAL in config)
SHARED_ITEMS_OPTIONAL=(
  ".claude/settings.local.json"
)

# Per-user only (here for documentation + status checks; referenced by tests)
# shellcheck disable=SC2034
LOCAL_ITEMS=(
  ".claude/projects"
  ".claude/sessions"
  ".claude/history.jsonl"
  ".claude/shell-snapshots"
  ".claude/plans"
  ".claude/todos"
  ".claude/statsig"
  ".claude/ide"
)

# Return the full list of shared items given current config.
shared_items() {
  local item
  for item in "${SHARED_ITEMS_ALWAYS[@]}"; do
    printf '%s\n' "$item"
  done
  if [[ "${SHARE_SETTINGS_LOCAL:-true}" == "true" ]]; then
    for item in "${SHARED_ITEMS_OPTIONAL[@]}"; do
      printf '%s\n' "$item"
    done
  fi
}
