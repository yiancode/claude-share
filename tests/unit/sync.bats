#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  # Fake "source user" home with a credentials file
  mkdir -p "$CS_TEST_ROOT/home/$SOURCE_USER/.claude"
  echo '{"claudeAiOauth":{"accessToken":"xxx","expiresAt":9999999999000}}' \
    > "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/.credentials.json"
  echo '{"numStartups":1}' > "$CS_TEST_ROOT/home/$SOURCE_USER/.claude.json"
  echo '{"effortLevel":"high"}' > "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/settings.json"
  echo '{"permissions":{}}' > "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/settings.local.json"
}
teardown() { teardown_sandbox; }

@test "bootstrap_shared_dir creates the tree" {
  run bootstrap_shared_dir
  [ "$status" -eq 0 ]
  [ -d "$SHARED_DIR" ]
  [ -d "$SHARED_DIR/home" ]
}

@test "seed_shared_from_source_user copies real files to the shared dir" {
  bootstrap_shared_dir
  seed_shared_from_source_user
  [ -f "$SHARED_DIR/home/.claude/.credentials.json" ]
  [ -f "$SHARED_DIR/home/.claude.json" ]
  [ -f "$SHARED_DIR/home/.claude/settings.json" ]
  [ -f "$SHARED_DIR/home/.claude/settings.local.json" ]
}

@test "seed_shared_from_source_user preserves the source files (no mv)" {
  bootstrap_shared_dir
  seed_shared_from_source_user
  # Source files must still be in place so an active claude session does
  # not lose access mid-init.
  [ -f "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/.credentials.json" ]
  [ -f "$CS_TEST_ROOT/home/$SOURCE_USER/.claude.json" ]
  [ -f "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/settings.json" ]
  [ -f "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/settings.local.json" ]
  # And the content must match
  grep -q '"accessToken":"xxx"' "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/.credentials.json"
  grep -q '"accessToken":"xxx"' "$SHARED_DIR/home/.claude/.credentials.json"
}

@test "link_user_to_shared leaves no gap (replaces file atomically)" {
  bootstrap_shared_dir
  seed_shared_from_source_user

  local user="bob"
  mkdir -p "$CS_TEST_ROOT/home/$user/.claude"
  echo "original bob content" > "$CS_TEST_ROOT/home/$user/.claude/.credentials.json"

  link_user_to_shared "$user"

  # After linking: path must exist (no gap), and must be a symlink to shared
  local p="$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  [ -e "$p" ]
  [ -L "$p" ]
  [ "$(readlink "$p")" = "$SHARED_DIR/home/.claude/.credentials.json" ]

  # The original content was backed up, not destroyed
  run find "$CS_TEST_ROOT/home/$user" -name "*.credentials.json" -not -type l
  echo "$output" | xargs -r grep -l "original bob content"
}

@test "seed_shared_from_source_user is idempotent" {
  bootstrap_shared_dir
  seed_shared_from_source_user
  seed_shared_from_source_user  # second run must not blow up or duplicate
  [ -f "$SHARED_DIR/home/.claude/.credentials.json" ]
}

@test "link_user_to_shared creates symlinks pointing at shared copies" {
  bootstrap_shared_dir
  seed_shared_from_source_user

  # Fake user directory
  local user="bob"
  mkdir -p "$CS_TEST_ROOT/home/$user/.claude"

  link_user_to_shared "$user"

  local link="$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$SHARED_DIR/home/.claude/.credentials.json" ]
}

@test "link_user_to_shared backs up pre-existing real files" {
  bootstrap_shared_dir
  seed_shared_from_source_user

  local user="bob"
  mkdir -p "$CS_TEST_ROOT/home/$user/.claude"
  echo "pre-existing" > "$CS_TEST_ROOT/home/$user/.claude/.credentials.json"

  link_user_to_shared "$user"

  local link="$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  [ -L "$link" ]
  # Backup exists somewhere under .claude-share.bak.*
  run find "$CS_TEST_ROOT/home/$user" -name ".claude-share.bak.*" -type d
  [ -n "$output" ]
}

@test "link_user_to_shared is idempotent" {
  bootstrap_shared_dir
  seed_shared_from_source_user
  local user="bob"
  mkdir -p "$CS_TEST_ROOT/home/$user/.claude"
  link_user_to_shared "$user"
  link_user_to_shared "$user"
  local link="$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  [ -L "$link" ]
  # And no backup dir created on second run
  run find "$CS_TEST_ROOT/home/$user" -name ".claude-share.bak.*" -type d
  [ -z "$output" ]
}

@test "unlink_user_from_shared replaces symlinks with real copies" {
  bootstrap_shared_dir
  seed_shared_from_source_user
  local user="bob"
  mkdir -p "$CS_TEST_ROOT/home/$user/.claude"
  link_user_to_shared "$user"

  unlink_user_from_shared "$user"

  local f="$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  [ -f "$f" ]
  [ ! -L "$f" ]
}
