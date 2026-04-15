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

# Prompts for a password twice (for confirmation). Echoes the password to
# stdout on success, exits non-zero on mismatch. Note: caller should capture
# via $(prompt_password ...) and then pipe into chpasswd immediately.
prompt_password() {
  local msg="$1"
  local p1 p2
  read -r -s -p "$msg: " p1; printf '\n' >&2
  read -r -s -p "Confirm $msg: " p2; printf '\n' >&2
  if [[ "$p1" != "$p2" ]]; then
    printf 'passwords do not match\n' >&2
    return 1
  fi
  if [[ -z "$p1" ]]; then
    printf 'password must not be empty\n' >&2
    return 1
  fi
  printf '%s' "$p1"
}

prompt_yes_no() {
  local msg="$1" default="${2:-n}" reply
  local suffix
  if [[ "$default" == "y" ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
  read -r -p "$msg $suffix: " reply
  reply="${reply:-$default}"
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}
