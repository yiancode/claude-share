#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  # shellcheck source=../../commands/cs.sh
  source "$REPO_ROOT/commands/cs.sh"
  client_save_profile "st@example.com" "$CS_TEST_ROOT/id_ed25519" "$CS_TEST_ROOT/local" '$HOME/.local'
}

teardown() { teardown_sandbox; }

@test "cs where shows main and extra remote mount paths" {
  local session="demo-live"
  local dir
  dir="$(tunnel_local_session_dir "$session")"
  mkdir -p "$dir"
  cat > "$dir/group-sessions.tsv" <<'EOF'
main-session	/tmp/project	/home/st/.claude-share/mounts/main-session
extra-session	/tmp/data	/home/st/.claude-share/extras/main-session/1-data
EOF

  run cmd_cs_where "$session"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "main-session"
  echo "$output" | grep -q "/home/st/.claude-share/mounts/main-session <= /tmp/project"
  echo "$output" | grep -q "/home/st/.claude-share/extras/main-session/1-data <= /tmp/data"
}

@test "cs status --json emits client profile and mount data" {
  local session="demo-live"
  local dir
  dir="$(tunnel_local_session_dir "$session")"
  mkdir -p "$dir"
  cat > "$dir/session.env" <<'EOF'
SESSION=demo-live
STATUS=ready
SERVER=st@example.com
WORKSPACE=/tmp/project
REMOTE_PORT=43022
SSH_PID=999999
EOF
  : > "$dir/live-root"
  cat > "$dir/group-sessions.tsv" <<'EOF'
main-session	/tmp/project	/home/st/.claude-share/mounts/main-session
EOF

  kill() {
    if [[ "$1" == "-0" && "$2" == "999999" ]]; then
      return 0
    fi
    command kill "$@"
  }

  run cmd_cs_status --json
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"server":"st@example.com"'
  echo "$output" | grep -q '"active_session":"demo-live"'
  echo "$output" | grep -q '"remote_path":"/home/st/.claude-share/mounts/main-session"'
}

@test "cs status omits empty extra mounts section" {
  run cmd_cs_status
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Extra mounts"
}
