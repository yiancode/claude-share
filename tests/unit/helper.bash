#!/usr/bin/env bash
# Shared test helper. Sources lib/*.sh with a sandboxed $HOME so tests don't
# touch the real filesystem.

setup_sandbox() {
  CS_TEST_ROOT="$(mktemp -d)"
  export CS_TEST_ROOT
  export HOME="$CS_TEST_ROOT/home/tester"
  mkdir -p "$HOME"
  export CS_CONFIG_FILE="$CS_TEST_ROOT/etc/claude-share/config"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export REPO_ROOT
  # shellcheck source=../../lib/common.sh
  source "$REPO_ROOT/lib/common.sh"
  # shellcheck source=../../lib/paths.sh
  source "$REPO_ROOT/lib/paths.sh"
  # shellcheck source=../../lib/prompt.sh
  source "$REPO_ROOT/lib/prompt.sh"
  # shellcheck source=../../lib/sync.sh
  source "$REPO_ROOT/lib/sync.sh"
  # shellcheck source=../../lib/tunnel_state.sh
  source "$REPO_ROOT/lib/tunnel_state.sh"
  # shellcheck source=../../lib/tunnel_common.sh
  source "$REPO_ROOT/lib/tunnel_common.sh"
  # shellcheck source=../../lib/tunnel_ssh.sh
  source "$REPO_ROOT/lib/tunnel_ssh.sh"
  # shellcheck source=../../lib/tunnel_exec.sh
  source "$REPO_ROOT/lib/tunnel_exec.sh"
  # shellcheck source=../../lib/client_profile.sh
  source "$REPO_ROOT/lib/client_profile.sh"

  SHARED_DIR="$CS_TEST_ROOT/shared"
  SHARE_GROUP="$(id -gn)"   # current group, so chown works as non-root
  SOURCE_USER="$(id -un)"
  SHARE_SETTINGS_LOCAL="true"
  MANAGED_USERS=()

  # Override user_home AFTER sourcing common.sh so the real getent-based
  # version doesn't clobber us.
  eval '
    user_home() {
      printf "%s/home/%s" "$CS_TEST_ROOT" "$1"
    }
  '
}

teardown_sandbox() {
  [[ -n "${CS_TEST_ROOT:-}" && -d "$CS_TEST_ROOT" ]] && rm -rf "$CS_TEST_ROOT"
}
