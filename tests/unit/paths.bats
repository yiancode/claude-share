#!/usr/bin/env bats

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "shared_items includes .credentials.json and .claude.json" {
  run shared_items
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx ".claude/.credentials.json"
  echo "$output" | grep -qx ".claude.json"
  echo "$output" | grep -qx ".claude/settings.json"
}

@test "shared_items includes settings.local.json when SHARE_SETTINGS_LOCAL=true" {
  SHARE_SETTINGS_LOCAL=true
  run shared_items
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx ".claude/settings.local.json"
}

@test "shared_items excludes settings.local.json when SHARE_SETTINGS_LOCAL=false" {
  SHARE_SETTINGS_LOCAL=false
  run shared_items
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx ".claude/settings.local.json"
}

@test "LOCAL_ITEMS documents projects and sessions" {
  [[ " ${LOCAL_ITEMS[*]} " == *" .claude/projects "* ]]
  [[ " ${LOCAL_ITEMS[*]} " == *" .claude/sessions "* ]]
  [[ " ${LOCAL_ITEMS[*]} " == *" .claude/history.jsonl "* ]]
}
