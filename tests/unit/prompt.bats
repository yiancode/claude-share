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

@test "prompt_password retries on mismatch then succeeds" {
  # First attempt: mismatch (abc / xyz). Second attempt: matches (ok123 / ok123).
  # Real callers use $(prompt_password ...) which captures stdout only; here
  # we validate via the stdout-captured-in-subshell idiom since bats's `run`
  # merges stderr into $output.
  local out
  out=$(prompt_password "pw" 2>/dev/null <<'EOF'
abc
xyz
ok123
ok123
EOF
)
  [ "$?" -eq 0 ]
  [ "$out" = "ok123" ]
}

@test "prompt_password retries on empty then succeeds" {
  local out
  out=$(prompt_password "pw" 2>/dev/null <<'EOF'


ok123
ok123
EOF
)
  [ "$?" -eq 0 ]
  [ "$out" = "ok123" ]
}

@test "prompt_password gives up after CS_PW_MAX_ATTEMPTS" {
  CS_PW_MAX_ATTEMPTS=2 run prompt_password "pw" <<'EOF'
a
b
c
d
EOF
  [ "$status" -ne 0 ]
}

@test "ensure_line_in_file is idempotent" {
  local f="$CS_TEST_ROOT/rc"
  ensure_line_in_file "$f" "umask 002" "test-marker"
  ensure_line_in_file "$f" "umask 002" "test-marker"
  run grep -c "umask 002" "$f"
  [ "$output" = "1" ]
}
