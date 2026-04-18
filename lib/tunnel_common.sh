#!/usr/bin/env bash
# tunnel_common.sh — validation and small shell helpers for tunnel commands.

tunnel_require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
  done
}

tunnel_require_abs_dir() {
  local path="$1"
  [[ "$path" == /* ]] || die "path must be absolute: $path"
  [[ -d "$path" ]] || die "directory does not exist: $path"
}

tunnel_resolve_workspace() {
  local path="$1"
  tunnel_require_abs_dir "$path"
  (
    cd "$path" >/dev/null 2>&1 && pwd -P
  ) || die "failed to resolve workspace path: $path"
}

tunnel_port_open_localhost() {
  local port="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1
}

tunnel_mount_is_active() {
  local mountpoint="$1"
  if command -v findmnt >/dev/null 2>&1; then
    [[ "$(findmnt -rn --target "$mountpoint" -o TARGET 2>/dev/null || true)" == "$mountpoint" ]]
  else
    mount | grep -F " on $mountpoint " >/dev/null 2>&1
  fi
}

tunnel_unmount_path() {
  local mountpoint="$1"
  if command -v fusermount >/dev/null 2>&1; then
    fusermount -u "$mountpoint"
  elif command -v fusermount3 >/dev/null 2>&1; then
    fusermount3 -u "$mountpoint"
  else
    umount "$mountpoint"
  fi
}

tunnel_print_kv() {
  printf '  %-16s %s\n' "$1" "$2"
}

tunnel_pick_remote_port() {
  local server="$1" identity_file="$2"
  ssh \
    -i "$identity_file" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$server" \
    "bash -lc 'for p in \$(seq 43022 43122); do if ! (: < /dev/tcp/127.0.0.1/\$p) >/dev/null 2>&1; then echo \$p; exit 0; fi; done; exit 1'"
}
