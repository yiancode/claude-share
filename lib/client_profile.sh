#!/usr/bin/env bash
# client_profile.sh — local client config and optional extra mount registry.

CS_CLIENT_CONFIG_DIR="${CLAUDE_SHARE_CLIENT_CONFIG_DIR:-$CS_TUNNEL_HOME/client}"
CS_CLIENT_CONFIG_FILE="$CS_CLIENT_CONFIG_DIR/profile.env"
CS_CLIENT_EXTRA_MOUNTS_FILE="$CS_CLIENT_CONFIG_DIR/extra-mounts.txt"

client_ensure_config_dir() {
  install -d -m 700 "$CS_CLIENT_CONFIG_DIR"
}

client_save_profile() {
  local server="$1" identity_file="$2" local_prefix="$3" remote_prefix="$4"
  client_ensure_config_dir
  {
    printf 'CLIENT_SERVER=%q\n' "$server"
    printf 'CLIENT_IDENTITY_FILE=%q\n' "$identity_file"
    printf 'CLIENT_LOCAL_PREFIX=%q\n' "$local_prefix"
    printf 'CLIENT_REMOTE_PREFIX=%q\n' "$remote_prefix"
  } > "$CS_CLIENT_CONFIG_FILE"
  chmod 600 "$CS_CLIENT_CONFIG_FILE"
}

client_load_profile() {
  [[ -f "$CS_CLIENT_CONFIG_FILE" ]] || return 1
  # shellcheck disable=SC1090
  source "$CS_CLIENT_CONFIG_FILE"
}

client_require_profile() {
  client_load_profile || die "client is not initialized yet. Run: claude-share client init <user@host>"
  [[ -n "${CLIENT_SERVER:-}" ]] || die "client config is missing CLIENT_SERVER"
  [[ -n "${CLIENT_IDENTITY_FILE:-}" ]] || die "client config is missing CLIENT_IDENTITY_FILE"
}

client_add_extra_mount() {
  local path="$1" resolved existing
  resolved="$(tunnel_resolve_workspace "$path")"
  client_ensure_config_dir
  touch "$CS_CLIENT_EXTRA_MOUNTS_FILE"
  existing="$(cat "$CS_CLIENT_EXTRA_MOUNTS_FILE" 2>/dev/null || true)"
  if ! printf '%s\n' "$existing" | grep -qxF "$resolved"; then
    printf '%s\n' "$resolved" >> "$CS_CLIENT_EXTRA_MOUNTS_FILE"
  fi
}

client_list_extra_mounts() {
  [[ -f "$CS_CLIENT_EXTRA_MOUNTS_FILE" ]] || return 0
  sed -n '1,200p' "$CS_CLIENT_EXTRA_MOUNTS_FILE"
}

client_remove_extra_mount() {
  local path="$1" resolved tmp
  resolved="$(tunnel_resolve_workspace "$path")"
  [[ -f "$CS_CLIENT_EXTRA_MOUNTS_FILE" ]] || return 0
  tmp="${CS_CLIENT_EXTRA_MOUNTS_FILE}.tmp.$$"
  grep -vxF "$resolved" "$CS_CLIENT_EXTRA_MOUNTS_FILE" > "$tmp" || true
  mv "$tmp" "$CS_CLIENT_EXTRA_MOUNTS_FILE"
}
