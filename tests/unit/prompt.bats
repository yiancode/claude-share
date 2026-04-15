#!/usr/bin/env bats

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "prompt_default returns default when input empty" {
  run prompt_default "msg" "dflt" < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "dflt" ]
}

@test "prompt_default echoes typed value" {
  run prompt_default "msg" "dflt" <<< "custom"
  [ "$status" -eq 0 ]
  [ "$output" = "custom" ]
}

@test "prompt_yes_no returns 0 for y" {
  run prompt_yes_no "ok?" n <<< "y"
  [ "$status" -eq 0 ]
}

@test "prompt_yes_no returns nonzero for n" {
  run prompt_yes_no "ok?" y <<< "n"
  [ "$status" -ne 0 ]
}

@test "ensure_line_in_file is idempotent" {
  local f="$CS_TEST_ROOT/rc"
  ensure_line_in_file "$f" "umask 002" "test-marker"
  ensure_line_in_file "$f" "umask 002" "test-marker"
  run grep -c "umask 002" "$f"
  [ "$output" = "1" ]
}
