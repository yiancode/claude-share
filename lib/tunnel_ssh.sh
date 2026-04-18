#!/usr/bin/env bash
# tunnel_ssh.sh — reverse tunnel setup and ephemeral SSH key helpers.
# shellcheck disable=SC2034
CS_TUNNEL_LAST_SSH_PID=""

tunnel_prepare_keypair() {
  local session_dir="$1" session="$2"
  local key_file="$session_dir/id_ed25519"
  if [[ ! -f "$key_file" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "claude-share:$session" -f "$key_file" >/dev/null
  fi
  chmod 600 "$key_file"
  chmod 644 "$key_file.pub"
  printf '%s\n' "$key_file"
}

tunnel_authorized_keys_file() {
  printf '%s/.ssh/authorized_keys' "$HOME"
}

tunnel_remove_authorized_key() {
  local session="$1" auth_file tmp
  auth_file="$(tunnel_authorized_keys_file)"
  [[ -f "$auth_file" ]] || return 0
  tmp="${auth_file}.claude-share.$$"
  awk -v marker="# claude-share:${session}" '
    skip == 1 { skip = 0; next }
    $0 == marker { skip = 1; next }
    { print }
  ' "$auth_file" > "$tmp"
  mv "$tmp" "$auth_file"
  chmod 600 "$auth_file"
}

tunnel_install_authorized_key() {
  local session="$1" pubkey_file="$2"
  local ssh_dir="$HOME/.ssh" auth_file marker
  marker="# claude-share:${session}"
  auth_file="$(tunnel_authorized_keys_file)"

  install -d -m 700 "$ssh_dir"
  [[ -f "$auth_file" ]] || : > "$auth_file"
  chmod 600 "$auth_file"
  tunnel_remove_authorized_key "$session"
  {
    printf '%s\n' "$marker"
    cat "$pubkey_file"
    printf '\n'
  } >> "$auth_file"
}

tunnel_fetch_remote_home() {
  local server="$1"
  shift
  ssh "$@" "$server" 'printf %s "$HOME"'
}

tunnel_remote_install_dir() {
  local server="$1" dir="$2"
  shift 2
  ssh "$@" "$server" "install -d -m 700 $(printf '%q' "$dir")"
}

tunnel_remote_remove_dir() {
  local server="$1" dir="$2"
  shift 2
  ssh "$@" "$server" "rm -rf $(printf '%q' "$dir")" >/dev/null 2>&1
}

tunnel_copy_file_to_remote() {
  local server="$1" src="$2" dest="$3"
  shift 3
  ssh "$@" "$server" "umask 077 && cat > $(printf '%q' "$dest")" < "$src"
}

tunnel_wait_for_remote_port() {
  local server="$1" remote_port="$2"
  shift 2
  ssh "$@" "$server" "bash -lc 'for i in {1..20}; do if : < /dev/tcp/127.0.0.1/$remote_port; then exit 0; fi; sleep 1; done; exit 1'" >/dev/null 2>&1
}

tunnel_start_reverse_ssh() {
  local server="$1" remote_port="$2" local_port="$3" logfile="$4"
  shift 4

  ssh \
    -NT \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -R "127.0.0.1:${remote_port}:127.0.0.1:${local_port}" \
    "$@" "$server" >> "$logfile" 2>&1 &
  CS_TUNNEL_LAST_SSH_PID="$!"
}
