#!/usr/bin/env bash
# commands/cs.sh — unified short workflow surface for daily use.

cmd_cs_usage() {
  cat <<'EOF'
Usage: cs <subcommand> [options]

Subcommands:
  live     Start a live session for the current directory and open remote Claude.
  add      Register an extra local directory for future live sessions.
  list     Show registered extra local directories.
  remove   Remove a registered extra local directory.
  where    Show the remote mount paths for the current live session.
  status   Show the saved client profile and current tunnel sessions.
  stop     Stop the latest active live session and unmount it remotely.
EOF
}

_cmd_cs_group_file() {
  printf '%s/group-sessions.tsv' "$(tunnel_local_session_dir "$1")"
}

_cmd_cs_live_root_marker() {
  printf '%s/live-root' "$(tunnel_local_session_dir "$1")"
}

_cmd_cs_json_escape() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//$'\n'/\\n}"
  text="${text//$'\r'/\\r}"
  text="${text//$'\t'/\\t}"
  printf '%s' "$text"
}

_cmd_cs_extra_mount_count() {
  [[ -f "$CS_CLIENT_EXTRA_MOUNTS_FILE" ]] || { printf '0\n'; return 0; }
  grep -cve '^[[:space:]]*$' "$CS_CLIENT_EXTRA_MOUNTS_FILE" || true
}

_cmd_cs_print_mount_map() {
  local session="$1"
  local group_file=""
  local line group_session group_workspace group_mount first=1

  group_file="$(_cmd_cs_group_file "$session")"
  [[ -f "$group_file" ]] || die "missing mount map for session: $session"
  printf '%s Live mount paths\n' "$CS_TAG"
  while IFS= read -r line; do
    group_session="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    group_workspace="${line%%$'\t'*}"
    group_mount="${line#*$'\t'}"
    if [[ $first -eq 1 ]]; then
      tunnel_print_kv "session" "$group_session"
      tunnel_print_kv "main" "$group_mount <= $group_workspace"
      first=0
    else
      tunnel_print_kv "extra" "$group_mount <= $group_workspace"
    fi
  done < "$group_file"
}

_cmd_cs_print_mount_map_json() {
  local session="$1"
  local group_file=""
  local line group_session group_workspace group_mount first=1 kind

  group_file="$(_cmd_cs_group_file "$session")"
  [[ -f "$group_file" ]] || die "missing mount map for session: $session"
  printf '['
  while IFS= read -r line; do
    group_session="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    group_workspace="${line%%$'\t'*}"
    group_mount="${line#*$'\t'}"
    if [[ $first -eq 1 ]]; then
      kind="main"
      first=0
    else
      kind="extra"
      printf ','
    fi
    printf '{"session":"%s","kind":"%s","local_path":"%s","remote_path":"%s"}' \
      "$(_cmd_cs_json_escape "$group_session")" \
      "$(_cmd_cs_json_escape "$kind")" \
      "$(_cmd_cs_json_escape "$group_workspace")" \
      "$(_cmd_cs_json_escape "$group_mount")"
  done < "$group_file"
  printf ']'
}

_cmd_cs_pick_remote_home() {
  local session="$1"
  local env_file=""
  local remote_dir=""

  env_file="$(tunnel_local_session_dir "$session")/session.env"
  [[ -f "$env_file" ]] || return 1
  # shellcheck disable=SC1090
  source "$env_file"
  remote_dir="${REMOTE_DIR:-}"
  [[ -n "$remote_dir" ]] || return 1
  printf '%s\n' "${remote_dir%%/.claude-share/remote/*}"
}

_cmd_cs_pick_session_name() {
  local workspace="$1" index="$2" main_session="$3"
  local slug
  slug="$(tunnel_slugify "$(basename "$workspace")")"
  [[ -n "$slug" ]] || slug="extra$index"
  printf '%s-x%s-%s\n' "${main_session:0:40}" "$index" "${slug:0:16}"
}

_cmd_cs_pick_session() {
  local dir env_file pid
  [[ -d "$(tunnel_local_root)" ]] || return 1

  while IFS= read -r dir; do
    env_file="$(tunnel_local_session_dir "$dir")/session.env"
    [[ -f "$env_file" ]] || continue
    [[ -f "$(_cmd_cs_live_root_marker "$dir")" ]] || continue
    # shellcheck disable=SC1090
    source "$env_file"
    pid="${SSH_PID:-}"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
  done < <(ls -1t "$(tunnel_local_root)" 2>/dev/null)

  while IFS= read -r dir; do
    env_file="$(tunnel_local_session_dir "$dir")/session.env"
    [[ -f "$env_file" ]] || continue
    # shellcheck disable=SC1090
    source "$env_file"
    pid="${SSH_PID:-}"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
  done < <(ls -1t "$(tunnel_local_root)" 2>/dev/null)
  return 1
}

_cmd_cs_stop_single_session() {
  local session="$1"
  local env_file=""
  local parent_pid=""

  env_file="$(tunnel_local_session_dir "$session")/session.env"
  [[ -f "$env_file" ]] || die "missing session state: $env_file"
  # shellcheck disable=SC1090
  source "$env_file"
  client_require_profile

  ssh \
    -i "$CLIENT_IDENTITY_FILE" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$CLIENT_SERVER" \
    "\$HOME/.local/bin/claude-share tunnel umount --session $(printf '%q' "$SESSION") >/dev/null 2>&1 || true" || true

  if [[ -n "${SSH_PID:-}" ]] && kill -0 "$SSH_PID" >/dev/null 2>&1; then
    parent_pid="$(ps -o ppid= -p "$SSH_PID" | tr -d ' ' || true)"
    kill "$SSH_PID" >/dev/null 2>&1 || true
    if [[ -n "$parent_pid" ]] && kill -0 "$parent_pid" >/dev/null 2>&1; then
      kill "$parent_pid" >/dev/null 2>&1 || true
    fi
  fi
}

_cmd_cs_stop_session() {
  local session="$1"
  local group_file=""
  local line group_session

  group_file="$(_cmd_cs_group_file "$session")"
  if [[ -f "$group_file" ]]; then
    while IFS= read -r line; do
      group_session="${line%%$'\t'*}"
      [[ -n "$group_session" ]] || continue
      _cmd_cs_stop_single_session "$group_session"
    done < <(tac "$group_file" 2>/dev/null || awk '{ lines[NR]=$0 } END { for (i=NR; i>=1; i--) print lines[i] }' "$group_file")
  else
    _cmd_cs_stop_single_session "$session"
  fi
}

_cmd_cs_wait_session_ready() {
  local session="$1" launcher_pid="$2" log_file="$3"
  local session_env=""
  local status=""
  local _

  session_env="$(tunnel_local_session_dir "$session")/session.env"
  for _ in $(seq 1 45); do
    if [[ -f "$session_env" ]]; then
      # shellcheck disable=SC1090
      source "$session_env"
      status="${STATUS:-}"
      case "$status" in
        ready) return 0 ;;
        degraded|closed)
          sed -n '1,220p' "$log_file" >&2 || true
          die "session failed during startup: $session"
          ;;
      esac
    fi
    if [[ -n "$launcher_pid" ]] && ! kill -0 "$launcher_pid" >/dev/null 2>&1; then
      sed -n '1,220p' "$log_file" >&2 || true
      die "session exited before becoming ready: $session"
    fi
    sleep 1
  done

  die "session did not become ready in time: $session"
}

_cmd_cs_require_session() {
  local session=""
  session="${1:-$(_cmd_cs_pick_session || true)}"
  [[ -n "$session" ]] || die "no active local session found"
  printf '%s\n' "$session"
}

_cmd_cs_start_session_bg() {
  local server="$1" identity_file="$2" local_prefix="$3" workspace="$4"
  local session="$5" remote_port="$6" local_sshd_port="$7" remote_mount="$8" read_only="$9"
  local session_dir log_file
  local -a cmd=(
    "$local_prefix/bin/claude-share" tunnel serve
    --workspace "$workspace"
    --server "$server"
    --session "$session"
    --remote-port "$remote_port"
    --ssh-arg -i
    --ssh-arg "$identity_file"
    --ssh-arg -o
    --ssh-arg StrictHostKeyChecking=no
    --ssh-arg -o
    --ssh-arg UserKnownHostsFile=/dev/null
  )

  [[ -n "$local_sshd_port" ]] && cmd+=(--local-sshd-port "$local_sshd_port")
  [[ -n "$remote_mount" ]] && cmd+=(--remote-mount "$remote_mount")
  [[ "$read_only" == "true" ]] && cmd+=(--read-only)

  session_dir="$(tunnel_local_session_dir "$session")"
  tunnel_ensure_private_dir "$session_dir"
  log_file="$session_dir/live-serve.log"

  "${cmd[@]}" > "$log_file" 2>&1 &
  printf '%s\t%s\n' "$!" "$log_file"
}

_cmd_cs_remote_mount_session() {
  local server="$1" identity_file="$2" session="$3" mountpoint="$4"
  local remote_cmd=""
  remote_cmd="\$HOME/.local/bin/claude-share tunnel mount --session $(printf '%q' "$session")"

  if [[ -n "$mountpoint" ]]; then
    remote_cmd+=" --mountpoint $(printf '%q' "$mountpoint")"
  fi
  remote_cmd+=" >/dev/null"

  ssh \
    -i "$identity_file" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$server" \
    "bash -lc $(printf '%q' "$remote_cmd")"
}

cmd_cs_live() {
  local workspace="$PWD" session="" remote_port="" local_sshd_port="" remote_mount=""
  local read_only=0 server="" identity_file="" local_prefix=""
  local session_dir="" remote_cmd="" remote_home="" main_mount=""
  local start_result="" launcher_pid="" log_file="" extra_workspace="" extra_port=""
  local extra_session="" extra_mount="" extra_index=0 extra_slug=""
  local group_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)       workspace="$2"; shift 2 ;;
      --session)         session="$2"; shift 2 ;;
      --remote-port)     remote_port="$2"; shift 2 ;;
      --local-sshd-port) local_sshd_port="$2"; shift 2 ;;
      --remote-mount)    remote_mount="$2"; shift 2 ;;
      --read-only)       read_only=1; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: cs live [options]

Options:
  --workspace <path>       Local workspace to publish. Default: current directory.
  --session <name>         Explicit session name.
  --remote-port <port>     Explicit remote loopback port.
  --local-sshd-port <port> Local sshd port. Default: 22.
  --remote-mount <path>    Suggested remote mountpoint.
  --read-only              Ask the server to mount read-only.
EOF
        return 0
        ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  client_require_profile
  server="$CLIENT_SERVER"
  identity_file="$CLIENT_IDENTITY_FILE"
  local_prefix="${CLIENT_LOCAL_PREFIX:-$HOME/.local}"
  workspace="$(tunnel_resolve_workspace "$workspace")"
  [[ -n "$session" ]] || session="$(tunnel_generate_session_name "$workspace")"
  tunnel_require_session_name "$session"

  if [[ -z "$remote_port" ]]; then
    remote_port="$(tunnel_pick_remote_port "$server" "$identity_file")" \
      || die "failed to auto-pick a free remote port on $server"
  fi

  session_dir="$(tunnel_local_session_dir "$session")"
  tunnel_ensure_private_dir "$session_dir"
  : > "$(_cmd_cs_live_root_marker "$session")"
  group_file="$(_cmd_cs_group_file "$session")"
  : > "$group_file"

  start_result="$(_cmd_cs_start_session_bg \
    "$server" "$identity_file" "$local_prefix" "$workspace" "$session" \
    "$remote_port" "$local_sshd_port" "$remote_mount" "$([[ $read_only -eq 1 ]] && echo true || echo false)")"
  launcher_pid="${start_result%%$'\t'*}"
  log_file="${start_result#*$'\t'}"
  _cmd_cs_wait_session_ready "$session" "$launcher_pid" "$log_file"

  remote_home="$(_cmd_cs_pick_remote_home "$session")"
  [[ -n "$remote_home" ]] || die "failed to resolve remote home for session: $session"
  main_mount="${remote_mount:-$remote_home/.claude-share/mounts/$session}"
  _cmd_cs_remote_mount_session "$server" "$identity_file" "$session" "$main_mount"
  printf '%s\t%s\t%s\n' "$session" "$workspace" "$main_mount" >> "$group_file"

  while IFS= read -r extra_workspace; do
    [[ -n "$extra_workspace" ]] || continue
    [[ -d "$extra_workspace" ]] || { warn "skipping missing extra mount: $extra_workspace"; continue; }
    extra_workspace="$(tunnel_resolve_workspace "$extra_workspace")"
    [[ "$extra_workspace" == "$workspace" ]] && continue
    extra_index=$((extra_index + 1))
    extra_session="$(_cmd_cs_pick_session_name "$extra_workspace" "$extra_index" "$session")"
    extra_port="$(tunnel_pick_remote_port "$server" "$identity_file")" \
      || die "failed to auto-pick a free remote port for extra mount: $extra_workspace"
    extra_slug="$(tunnel_slugify "$(basename "$extra_workspace")")"
    [[ -n "$extra_slug" ]] || extra_slug="extra$extra_index"
    extra_mount="$remote_home/.claude-share/extras/$session/${extra_index}-${extra_slug}"

    start_result="$(_cmd_cs_start_session_bg \
      "$server" "$identity_file" "$local_prefix" "$extra_workspace" "$extra_session" \
      "$extra_port" "$local_sshd_port" "$extra_mount" "$([[ $read_only -eq 1 ]] && echo true || echo false)")"
    launcher_pid="${start_result%%$'\t'*}"
    log_file="${start_result#*$'\t'}"
    _cmd_cs_wait_session_ready "$extra_session" "$launcher_pid" "$log_file"
    _cmd_cs_remote_mount_session "$server" "$identity_file" "$extra_session" "$extra_mount"
    printf '%s\t%s\t%s\n' "$extra_session" "$extra_workspace" "$extra_mount" >> "$group_file"
  done < <(client_list_extra_mounts)

  printf '\n'
  _cmd_cs_print_mount_map "$session"
  printf '\n'

  remote_cmd="set -Eeuo pipefail; "
  remote_cmd+="source ~/.claude-share/remote/$(printf '%q' "$session")/env.sh; "
  remote_cmd+="printf '%s\\n' $(printf '%q' 'claude-share live session ready'); "
  remote_cmd+="printf '%s\\n' $(printf '%q' "server: $server"); "
  remote_cmd+="printf '%s\\n' $(printf '%q' "session: $session"); "
  remote_cmd+="printf '%s\\n' $(printf '%q' "main: $main_mount <= $workspace"); "
  extra_index=0
  while IFS= read -r extra_workspace; do
    [[ -n "$extra_workspace" ]] || continue
    [[ -d "$extra_workspace" ]] || continue
    extra_workspace="$(tunnel_resolve_workspace "$extra_workspace")"
    [[ "$extra_workspace" == "$workspace" ]] && continue
    extra_index=$((extra_index + 1))
    extra_slug="$(tunnel_slugify "$(basename "$extra_workspace")")"
    [[ -n "$extra_slug" ]] || extra_slug="extra$extra_index"
    extra_mount="$remote_home/.claude-share/extras/$session/${extra_index}-${extra_slug}"
    remote_cmd+="printf '%s\\n' $(printf '%q' "extra: $extra_mount <= $extra_workspace"); "
  done < <(client_list_extra_mounts)
  remote_cmd+="printf '%s\\n' $(printf '%q' 'stop from local: cs stop'); "
  remote_cmd+="printf '%s\\n' ''; "
  remote_cmd+="cd $(printf '%q' "$main_mount"); "
  remote_cmd+="exec claude"

  local rc=0
  set +e
  ssh \
    -tt \
    -i "$identity_file" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$server" \
    "bash -lc $(printf '%q' "$remote_cmd")"
  rc=$?
  set -e
  _cmd_cs_stop_session "$SESSION"
  return "$rc"
}

cmd_cs_add() {
  [[ $# -eq 1 ]] || die "usage: cs add <directory>"
  client_require_profile
  client_add_extra_mount "$1"
  ok "Registered extra mount: $(tunnel_resolve_workspace "$1")"
}

cmd_cs_list() {
  client_require_profile
  printf '%s Extra mounts\n' "$CS_TAG"
  if [[ -f "$CS_CLIENT_EXTRA_MOUNTS_FILE" ]]; then
    sed 's/^/  /' "$CS_CLIENT_EXTRA_MOUNTS_FILE"
  else
    printf '  <none>\n'
  fi
}

cmd_cs_remove() {
  [[ $# -eq 1 ]] || die "usage: cs remove <directory>"
  client_require_profile
  client_remove_extra_mount "$1"
  ok "Removed extra mount: $(tunnel_resolve_workspace "$1")"
}

cmd_cs_status() {
  local active_session=""
  local json=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: cs status [--json]

Show the saved client profile and the current active live session.
EOF
        return 0
        ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  client_require_profile
  active_session="$(_cmd_cs_pick_session || true)"

  if [[ $json -eq 1 ]]; then
    printf '{'
    printf '"server":"%s",' "$(_cmd_cs_json_escape "$CLIENT_SERVER")"
    printf '"identity_file":"%s",' "$(_cmd_cs_json_escape "$CLIENT_IDENTITY_FILE")"
    printf '"extra_mounts":['
    if [[ -f "$CS_CLIENT_EXTRA_MOUNTS_FILE" ]]; then
      local first=1 mount
      while IFS= read -r mount; do
        [[ -n "$mount" ]] || continue
        [[ $first -eq 1 ]] || printf ','
        printf '"%s"' "$(_cmd_cs_json_escape "$mount")"
        first=0
      done < "$CS_CLIENT_EXTRA_MOUNTS_FILE"
    fi
    printf '],'
    if [[ -n "$active_session" ]]; then
      printf '"active_session":"%s",' "$(_cmd_cs_json_escape "$active_session")"
      printf '"mounts":'
      if [[ -f "$(_cmd_cs_group_file "$active_session")" ]]; then
        _cmd_cs_print_mount_map_json "$active_session"
      else
        printf '[]'
      fi
    else
      printf '"active_session":null,"mounts":[]'
    fi
    printf '}\n'
    return 0
  fi

  printf '%s Client profile\n' "$CS_TAG"
  tunnel_print_kv "server" "$CLIENT_SERVER"
  tunnel_print_kv "identity file" "$CLIENT_IDENTITY_FILE"

  if [[ "$(_cmd_cs_extra_mount_count)" -gt 0 ]]; then
    printf '\n'
    printf '%s Extra mounts\n' "$CS_TAG"
    sed 's/^/  /' "$CS_CLIENT_EXTRA_MOUNTS_FILE"
  fi

  printf '\n'
  printf '%s Active live session\n' "$CS_TAG"
  if [[ -n "$active_session" ]]; then
    tunnel_print_kv "session" "$active_session"
    if [[ -f "$(_cmd_cs_group_file "$active_session")" ]]; then
      printf '\n'
      _cmd_cs_print_mount_map "$active_session"
    fi
  else
    printf '  <none>\n'
  fi
}

cmd_cs_where() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: cs where [session]

Show the remote mount paths for the active live session, or for the named
session if one is provided.
EOF
    return 0
  fi
  local session=""
  session="$(_cmd_cs_require_session "${1:-}")"
  _cmd_cs_print_mount_map "$session"
}

cmd_cs_stop() {
  local session=""
  session="$(_cmd_cs_require_session "${1:-}")"
  _cmd_cs_stop_session "$session"
  ok "Stopped session: $session"
}

cmd_cs() {
  local subcmd="${1:-}"
  [[ $# -gt 0 ]] && shift

  case "$subcmd" in
    live)   cmd_cs_live "$@" ;;
    add)    cmd_cs_add "$@" ;;
    list|ls) cmd_cs_list "$@" ;;
    remove|rm) cmd_cs_remove "$@" ;;
    where)  cmd_cs_where "$@" ;;
    status) cmd_cs_status "$@" ;;
    stop)   cmd_cs_stop "$@" ;;
    help|--help|-h|"") cmd_cs_usage ;;
    *) die "unknown cs subcommand: $subcmd" ;;
  esac
}
