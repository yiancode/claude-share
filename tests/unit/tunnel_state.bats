#!/usr/bin/env bats

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "tunnel_generate_session_name slugifies workspace basename" {
  run tunnel_generate_session_name "/tmp/My Project"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^My-Project-[0-9]{8}-[0-9]{6}$ ]]
}

@test "tunnel_write_state_files writes env and json state" {
  local dir
  dir="$(tunnel_local_session_dir "demo")"

  tunnel_write_state_files "$dir" SESSION "demo" STATUS "ready" WORKSPACE "/tmp/demo"

  [ -f "$dir/session.env" ]
  [ -f "$dir/session.json" ]
  run grep -q "SESSION=demo" "$dir/session.env"
  [ "$status" -eq 0 ]
  run grep -q '"STATUS": "ready"' "$dir/session.json"
  [ "$status" -eq 0 ]
}

@test "tunnel_install_authorized_key appends and removes session marker" {
  local session_dir auth_file
  session_dir="$(tunnel_local_session_dir "demo")"
  tunnel_ensure_private_dir "$session_dir"
  ssh-keygen -q -t ed25519 -N '' -C demo -f "$session_dir/id_ed25519" >/dev/null

  tunnel_install_authorized_key "demo" "$session_dir/id_ed25519.pub"
  auth_file="$(tunnel_authorized_keys_file)"
  [ -f "$auth_file" ]
  run grep -q "# claude-share:demo" "$auth_file"
  [ "$status" -eq 0 ]

  tunnel_remove_authorized_key "demo"
  run grep -q "# claude-share:demo" "$auth_file"
  [ "$status" -ne 0 ]
}

@test "tunnel_write_remote_exec_bundle creates proxy bin and shell helpers" {
  local session_dir
  session_dir="$(tunnel_remote_session_dir "demo")"
  tunnel_write_state_files "$session_dir" \
    SESSION "demo" \
    STATUS "mounted" \
    WORKSPACE "/src/project" \
    MOUNTPOINT "$CS_TEST_ROOT/mount/demo" \
    LOCAL_USER "tester" \
    REMOTE_PORT "43022" \
    IDENTITY_FILE "$session_dir/id_ed25519" \
    KNOWN_HOSTS "$session_dir/known_hosts" \
    MODE "rw" \
    SERVER "demo@example.com"

  tunnel_write_remote_exec_bundle "$session_dir"

  [ -x "$session_dir/bin/exec-proxy" ]
  [ -L "$session_dir/bin/bash" ]
  [ -f "$session_dir/env.sh" ]
  [ -x "$session_dir/enter-shell" ]
}

@test "tunnel_write_remote_exec_bundle makes env hook source-safe" {
  local session_dir
  session_dir="$(tunnel_remote_session_dir "demo")"
  tunnel_write_state_files "$session_dir" \
    SESSION "demo" \
    STATUS "mounted" \
    WORKSPACE "/src/project" \
    MOUNTPOINT "$CS_TEST_ROOT/mount/demo" \
    LOCAL_USER "tester" \
    REMOTE_PORT "43022" \
    IDENTITY_FILE "$session_dir/id_ed25519" \
    KNOWN_HOSTS "$session_dir/known_hosts" \
    MODE "rw" \
    SERVER "demo@example.com"

  tunnel_write_remote_exec_bundle "$session_dir"

  run grep -q 'set -Eeuo pipefail' "$session_dir/env.sh"
  [ "$status" -ne 0 ]
  run grep -q 'BASH_SOURCE' "$session_dir/env.sh"
  [ "$status" -ne 0 ]
}

@test "tunnel_write_remote_exec_bundle uses tty-aware shell proxy without heredoc stdin" {
  local session_dir
  session_dir="$(tunnel_remote_session_dir "demo")"
  tunnel_write_state_files "$session_dir" \
    SESSION "demo" \
    STATUS "mounted" \
    WORKSPACE "/src/project" \
    MOUNTPOINT "$CS_TEST_ROOT/mount/demo" \
    LOCAL_USER "tester" \
    REMOTE_PORT "43022" \
    IDENTITY_FILE "$session_dir/id_ed25519" \
    KNOWN_HOSTS "$session_dir/known_hosts" \
    MODE "rw" \
    SERVER "demo@example.com"

  tunnel_write_remote_exec_bundle "$session_dir"

  run grep -q 'ssh_tty_flag="-tt"' "$session_dir/bin/exec-proxy"
  [ "$status" -eq 0 ]
  run grep -q "bash -lc" "$session_dir/bin/exec-proxy"
  [ "$status" -eq 0 ]
  run grep -q "<<'INNER'" "$session_dir/bin/exec-proxy"
  [ "$status" -ne 0 ]
}
