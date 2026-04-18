#!/usr/bin/env bash
# tunnel_state.sh — local/remote session paths and persisted state helpers.

CS_TUNNEL_HOME="${CLAUDE_SHARE_TUNNEL_HOME:-$HOME/.claude-share}"

tunnel_local_root() {
  printf '%s/tunnels' "$CS_TUNNEL_HOME"
}

tunnel_remote_root() {
  printf '%s/remote' "$CS_TUNNEL_HOME"
}

tunnel_default_mount_root() {
  printf '%s/mounts' "$CS_TUNNEL_HOME"
}

tunnel_local_session_dir() {
  printf '%s/%s' "$(tunnel_local_root)" "$1"
}

tunnel_remote_session_dir() {
  printf '%s/%s' "$(tunnel_remote_root)" "$1"
}

tunnel_validate_session_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
}

tunnel_require_session_name() {
  tunnel_validate_session_name "$1" || die "invalid session name: $1"
}

tunnel_slugify() {
  local input="$1" slug
  slug="$(printf '%s' "$input" | tr -cs 'A-Za-z0-9._-' '-')"
  slug="${slug#-}"
  slug="${slug%-}"
  [[ -n "$slug" ]] || slug="workspace"
  printf '%s' "$slug"
}

tunnel_generate_session_name() {
  local workspace="$1" base stamp
  base="$(basename "$workspace")"
  base="$(tunnel_slugify "$base")"
  stamp="$(date +%Y%m%d-%H%M%S)"
  printf '%s-%s' "$base" "$stamp"
}

tunnel_ensure_private_dir() {
  install -d -m 700 "$1"
}

tunnel_json_escape() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//$'\n'/\\n}"
  text="${text//$'\r'/\\r}"
  text="${text//$'\t'/\\t}"
  printf '%s' "$text"
}

tunnel_write_state_files() {
  local dir="$1"
  shift

  local env_file="$dir/session.env"
  local json_file="$dir/session.json"
  local i key value next_i

  tunnel_ensure_private_dir "$dir"

  : > "$env_file"
  chmod 600 "$env_file"
  for ((i=1; i<=$#; i+=2)); do
    next_i=$((i + 1))
    key="${!i}"
    value="${!next_i}"
    printf '%s=%q\n' "$key" "$value" >> "$env_file"
  done

  {
    printf '{\n'
    for ((i=1; i<=$#; i+=2)); do
      next_i=$((i + 1))
      key="${!i}"
      value="${!next_i}"
      printf '  "%s": "%s"' \
        "$(tunnel_json_escape "$key")" \
        "$(tunnel_json_escape "$value")"
      if (( next_i < $# )); then
        printf ','
      fi
      printf '\n'
    done
    printf '}\n'
  } > "$json_file"
  chmod 600 "$json_file"
}

tunnel_load_state_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  # shellcheck disable=SC1090
  source "$file"
}
