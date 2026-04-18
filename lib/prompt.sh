#!/usr/bin/env bash
# prompt.sh — interactive prompts (hidden password input, defaults)

prompt_default() {
  local msg="$1" default="$2" var
  if [[ -n "$default" ]]; then
    read -r -p "$msg [$default]: " var
    printf '%s\n' "${var:-$default}"
  else
    read -r -p "$msg: " var
    printf '%s\n' "$var"
  fi
}

# Prompt for a password twice (confirmation). Retries on empty input or
# mismatch up to $CS_PW_MAX_ATTEMPTS times (default 5). Echoes the password
# to stdout on success, returns non-zero only if the attempt limit is hit
# or stdin hits EOF (so scripted callers can still fail fast).
# Caller should capture via $(prompt_password ...) and pipe straight into
# chpasswd so the value never lands in a file.
prompt_password() {
  local msg="$1"
  local max="${CS_PW_MAX_ATTEMPTS:-5}"
  local attempt=0 p1 p2
  while (( attempt < max )); do
    attempt=$((attempt + 1))
    if ! read -r -s -p "$msg: " p1; then
      printf '\n' >&2
      printf 'password entry aborted (EOF)\n' >&2
      return 1
    fi
    printf '\n' >&2
    if ! read -r -s -p "Confirm $msg: " p2; then
      printf '\n' >&2
      printf 'password entry aborted (EOF)\n' >&2
      return 1
    fi
    printf '\n' >&2
    if [[ -z "$p1" ]]; then
      printf 'password must not be empty, try again\n' >&2
      continue
    fi
    if [[ "$p1" != "$p2" ]]; then
      printf 'passwords do not match, try again\n' >&2
      continue
    fi
    printf '%s' "$p1"
    return 0
  done
  printf 'too many failed attempts (%d), giving up\n' "$max" >&2
  return 1
}

prompt_yes_no() {
  local msg="$1" default="${2:-n}" reply
  local suffix reply_lc
  if [[ "$default" == "y" ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
  printf '%s %s: ' "$msg" "$suffix" >&2
  if ! IFS= read -r reply; then
    reply="$default"
  fi
  reply="${reply:-$default}"
  reply_lc="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
  if [[ "$reply_lc" == "y" || "$reply_lc" == "yes" ]]; then
    return 0
  fi
  return 1
}
