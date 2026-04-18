#!/usr/bin/env bats

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "cmd_tunnel_serve cleans local key without remote cleanup before remote dir exists" {
  run env BATS_TEST_DIRNAME=tests/unit bash -lc '
    set -Eeuo pipefail
    source tests/unit/helper.bash
    setup_sandbox
    source "$REPO_ROOT/commands/tunnel_serve.sh"
    mkdir -p "$CS_TEST_ROOT/workspace"

    tunnel_port_open_localhost() { return 0; }
    tunnel_fetch_remote_home() { return 1; }
    tunnel_remote_remove_dir() { : > "$CS_TEST_ROOT/remote-cleanup-should-not-run"; }

    auth_file="$(tunnel_authorized_keys_file)"
    set +e
    (
      cmd_tunnel_serve \
        --workspace "$CS_TEST_ROOT/workspace" \
        --server tester@example.com \
        --session demo \
        --local-sshd-port 22
    )
    rc=$?
    set -e

    [[ $rc -ne 0 ]]
    if [[ -f "$auth_file" ]]; then
      ! grep -q "# claude-share:" "$auth_file"
    fi
    [[ ! -e "$CS_TEST_ROOT/remote-cleanup-should-not-run" ]]
    teardown_sandbox
  '
  [ "$status" -eq 0 ]
}

@test "cmd_tunnel_serve removes remote dir when upload fails after remote dir creation" {
  run env BATS_TEST_DIRNAME=tests/unit bash -lc '
    set -Eeuo pipefail
    source tests/unit/helper.bash
    setup_sandbox
    source "$REPO_ROOT/commands/tunnel_serve.sh"
    mkdir -p "$CS_TEST_ROOT/workspace"

    tunnel_port_open_localhost() { return 0; }
    tunnel_fetch_remote_home() { printf "/remote-home"; }
    tunnel_remote_install_dir() {
      printf "%s\n" "$2" > "$CS_TEST_ROOT/created-remote-dir"
    }
    tunnel_copy_file_to_remote() { return 1; }
    tunnel_remote_remove_dir() {
      printf "%s\n" "$2" > "$CS_TEST_ROOT/removed-remote-dir"
    }

    auth_file="$(tunnel_authorized_keys_file)"
    set +e
    (
      cmd_tunnel_serve \
        --workspace "$CS_TEST_ROOT/workspace" \
        --server tester@example.com \
        --session demo \
        --local-sshd-port 22
    )
    rc=$?
    set -e

    [[ $rc -ne 0 ]]
    [[ -f "$CS_TEST_ROOT/created-remote-dir" ]]
    [[ -f "$CS_TEST_ROOT/removed-remote-dir" ]]
    [[ "$(cat "$CS_TEST_ROOT/created-remote-dir")" == "/remote-home/.claude-share/remote/demo" ]]
    [[ "$(cat "$CS_TEST_ROOT/removed-remote-dir")" == "/remote-home/.claude-share/remote/demo" ]]
    if [[ -f "$auth_file" ]]; then
      ! grep -q "# claude-share:" "$auth_file"
    fi
    teardown_sandbox
  '
  [ "$status" -eq 0 ]
}
