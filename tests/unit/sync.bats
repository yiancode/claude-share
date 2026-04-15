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

@test "seed uses '{}' (not zero-byte) for missing source files" {
  # Remove source .claude.json entirely before seeding.
  rm -f "$CS_TEST_ROOT/home/$SOURCE_USER/.claude.json"
  bootstrap_shared_dir
  seed_shared_from_source_user

  local shared="$SHARED_DIR/home/.claude.json"
  [ -f "$shared" ]
  [ -s "$shared" ]                   # non-zero size — the failure mode
                                     # we're guarding against
  run cat "$shared"
  [ "$output" = "{}" ]
}

@test "seed still creates empty credentials placeholder (login flow)" {
  # credentials.json is the exception: an empty-object credentials file
  # would look like a corrupt login, so we keep the zero-byte placeholder
  # ONLY for that path.
  rm -f "$CS_TEST_ROOT/home/$SOURCE_USER/.claude/.credentials.json"
  bootstrap_shared_dir
  seed_shared_from_source_user

  local shared="$SHARED_DIR/home/.claude/.credentials.json"
  [ -f "$shared" ]
  [ ! -s "$shared" ]
}

@test "link_user_to_shared self-heals after a severed symlink (rename case)" {
  bootstrap_shared_dir
  seed_shared_from_source_user

  local user="bob"
  mkdir -p "$CS_TEST_ROOT/home/$user/.claude"
  link_user_to_shared "$user"

  # Simulate Claude Code (or any rename-based writer) replacing the
  # symlink with a fresh real file — this is the "rename severed the
  # link" failure mode our status check warns about.
  local abs="$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  rm "$abs"
  echo "rogue local content" > "$abs"
  [ ! -L "$abs" ]

  # sync == re-running link_user_to_shared. It must back up the rogue
  # content and restore the symlink to the shared target.
  link_user_to_shared "$user"

  [ -L "$abs" ]
  [ "$(readlink "$abs")" = "$SHARED_DIR/home/.claude/.credentials.json" ]

  # The rogue content must be under a backup dir, not silently destroyed.
  run find "$CS_TEST_ROOT/home/$user" -name ".claude-share.bak.*" -type d
  [ -n "$output" ]
  echo "$output" | xargs -I{} grep -rl "rogue local content" {}
}

@test "link_user_to_shared backup dirs don't collide on rapid successive calls" {
  bootstrap_shared_dir
  seed_shared_from_source_user

  local user="bob"
  mkdir -p "$CS_TEST_ROOT/home/$user/.claude"

  # Two back-to-back real files that each need to be backed up.
  echo "first"  > "$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  link_user_to_shared "$user"
  rm "$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  echo "second" > "$CS_TEST_ROOT/home/$user/.claude/.credentials.json"
  link_user_to_shared "$user"

  # Both backups must survive — the second call must not have
  # overwritten the first because of a shared-second timestamp.
  local count
  count=$(find "$CS_TEST_ROOT/home/$user" -name ".claude-share.bak.*" -type d | wc -l)
  [ "$count" -ge 2 ]
}
