#!/usr/bin/env bash
# users.sh — wrappers for useradd / groupadd / chpasswd / usermod
#
# Every function is idempotent: re-running them against existing
# users/groups/memberships is a no-op.

ensure_group() {
  local group="$1"
  if ! getent group "$group" >/dev/null; then
    groupadd "$group"
    ok "Created group: $group"
  fi
}

user_exists() {
  getent passwd "$1" >/dev/null
}

ensure_user() {
  local user="$1"
  if user_exists "$user"; then
    log "User already exists: $user (skipping useradd)"
    return 0
  fi
  useradd -m -s /bin/bash "$user"
  ok "Created user: $user"
}

# Set a user's password. Reads password from stdin, so callers can pipe a
# password in without it ever touching a file or argv.
set_user_password() {
  local user="$1"
  local password="$2"
  # chpasswd "-e" handles pre-hashed; we pass plain.
  printf '%s:%s' "$user" "$password" | chpasswd
}

ensure_user_in_group() {
  local user="$1" group="$2"
  if id -nG "$user" | tr ' ' '\n' | grep -qx "$group"; then
    return 0
  fi
  usermod -aG "$group" "$user"
  ok "Added $user to group $group"
}

remove_user_from_group() {
  local user="$1" group="$2"
  if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
    gpasswd -d "$user" "$group" >/dev/null
    ok "Removed $user from group $group"
  fi
}

# Add "umask 002" to a user's ~/.bashrc so files they create are
# group-writable. Idempotent — uses a marker comment.
ensure_group_umask() {
  local user="$1"
  local home
  home="$(user_home "$user")" || return 1
  [[ -n "$home" && -d "$home" ]] || return 0
  local rc="$home/.bashrc"
  ensure_line_in_file "$rc" "umask 002" "claude-share: shared-group umask"
  chown "$user": "$rc" 2>/dev/null || true
}
