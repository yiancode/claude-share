#!/usr/bin/env bash
# common.sh — logging, error handling, root check, config loading
#
# Note: strict mode (set -Eeuo pipefail) is set by bin/claude-share, not
# here, so that this file is safe to source from tests.

# Colours (disabled when not a TTY)
if [[ -t 1 ]]; then
  CS_C_RED=$'\033[31m'
  CS_C_GREEN=$'\033[32m'
  CS_C_YELLOW=$'\033[33m'
  CS_C_BLUE=$'\033[34m'
  CS_C_RESET=$'\033[0m'
else
  CS_C_RED='' CS_C_GREEN='' CS_C_YELLOW='' CS_C_BLUE='' CS_C_RESET=''
fi

CS_TAG="[claude-share]"

log()      { printf '%s %s\n'    "${CS_C_BLUE}${CS_TAG}${CS_C_RESET}"   "$*"; }
ok()       { printf '%s %s %s\n' "${CS_C_BLUE}${CS_TAG}${CS_C_RESET}"   "${CS_C_GREEN}✓${CS_C_RESET}" "$*"; }
warn()     { printf '%s %s %s\n' "${CS_C_BLUE}${CS_TAG}${CS_C_RESET}"   "${CS_C_YELLOW}!${CS_C_RESET}" "$*" >&2; }
err()      { printf '%s %s %s\n' "${CS_C_BLUE}${CS_TAG}${CS_C_RESET}"   "${CS_C_RED}✗${CS_C_RESET}" "$*" >&2; }
die()      { err "$*"; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This command must be run as root (try: sudo $0 $*)"
  fi
}

# Config file path
CS_CONFIG_FILE="${CS_CONFIG_FILE:-/etc/claude-share/config}"

# Populated by load_config
SHARED_DIR=""
SHARE_GROUP=""
SOURCE_USER=""
SHARE_SETTINGS_LOCAL=""
MANAGED_USERS=()

load_config() {
  if [[ ! -f "$CS_CONFIG_FILE" ]]; then
    return 1
  fi
  # shellcheck disable=SC1090
  source "$CS_CONFIG_FILE"
  return 0
}

# Format-check a loaded config — everything came from our own save_config,
# but a corrupted or hand-edited file could leave us with missing globals.
# Called by require_initialized after load_config so downstream code can
# assume the globals are sane.
require_valid_config() {
  [[ -n "${SHARED_DIR:-}"    ]] || die "config: SHARED_DIR is empty ($CS_CONFIG_FILE)"
  [[ -n "${SHARE_GROUP:-}"   ]] || die "config: SHARE_GROUP is empty ($CS_CONFIG_FILE)"
  [[ -n "${SOURCE_USER:-}"   ]] || die "config: SOURCE_USER is empty ($CS_CONFIG_FILE)"
  [[ "$SHARED_DIR" == /* ]]     || die "config: SHARED_DIR must be absolute: $SHARED_DIR"
}

require_initialized() {
  if ! load_config; then
    die "claude-share is not initialized yet. Run: sudo claude-share init"
  fi
  require_valid_config
}

save_config() {
  local dir
  dir="$(dirname "$CS_CONFIG_FILE")"
  # The config file holds no secrets (paths, group name, list of managed
  # usernames) — everyone in the claudeshare group can already see all of
  # this via `id` and `ls -l`. Keep it world-readable so non-root users
  # can run `claude-share status` to self-diagnose without sudo.
  install -d -m 755 "$dir"
  {
    printf '# claude-share config — generated %s\n' "$(date -Iseconds)"
    printf 'SHARED_DIR=%q\n' "$SHARED_DIR"
    printf 'SHARE_GROUP=%q\n' "$SHARE_GROUP"
    printf 'SOURCE_USER=%q\n' "$SOURCE_USER"
    printf 'SHARE_SETTINGS_LOCAL=%q\n' "$SHARE_SETTINGS_LOCAL"
    printf 'MANAGED_USERS=('
    local first=1 u
    for u in "${MANAGED_USERS[@]}"; do
      if [[ $first -eq 1 ]]; then first=0; else printf ' '; fi
      printf '%q' "$u"
    done
    printf ')\n'
  } > "$CS_CONFIG_FILE"
  chmod 644 "$CS_CONFIG_FILE"
}

# Idempotently append a line to a file, marked so it can be reliably removed.
ensure_line_in_file() {
  local file="$1" line="$2" marker="$3"
  [[ -f "$file" ]] || : > "$file"
  if ! grep -qF "$marker" "$file"; then
    printf '\n# %s\n%s\n' "$marker" "$line" >> "$file"
  fi
}

# Get a user's home directory from /etc/passwd
user_home() {
  getent passwd "$1" | cut -d: -f6
}

# install -d with owner/group — but only when running as root AND the named
# user/group actually exist. Otherwise falls back to default ownership.
# This lets unit tests run against fake usernames without needing to create
# real accounts.
priv_install_dir() {
  local mode="$1" owner="$2" group="$3" path="$4"
  if [[ $EUID -eq 0 ]] && getent passwd "$owner" >/dev/null && getent group "$group" >/dev/null; then
    install -d -m "$mode" -o "$owner" -g "$group" "$path"
  else
    install -d -m "$mode" "$path"
  fi
}

_priv_spec_resolvable() {
  local spec="$1"
  local u="${spec%%:*}"
  local g="${spec#*:}"
  [[ $EUID -eq 0 ]] || return 1
  getent passwd "$u" >/dev/null || return 1
  [[ -z "$g" || "$g" == "$spec" ]] || getent group "$g" >/dev/null || return 1
  return 0
}

# chown — noop when not root or when the target user/group doesn't exist.
priv_chown() {
  local spec="$1" path="$2"
  if _priv_spec_resolvable "$spec"; then
    chown "$spec" "$path"
  fi
}

priv_chown_link() {
  local spec="$1" path="$2"
  if _priv_spec_resolvable "$spec"; then
    chown -h "$spec" "$path" 2>/dev/null || true
  fi
}
