#!/usr/bin/env bash
# commands/tunnel_bootstrap.sh — bootstrap local/remote install + SSH key auth.

cmd_tunnel_default_identity_file() {
  local server="$1"
  printf '%s/.ssh/claude-share-%s' "$HOME" "$(tunnel_slugify "$server")"
}

cmd_tunnel_bootstrap_usage() {
  cat <<'EOF'
Usage: claude-share tunnel bootstrap --server <user@host> [options]

Options:
  --server <user@host>    Remote SSH destination.
  --password <password>   Optional bootstrap password for first-time install.
                          If omitted, uses existing SSH auth.
  --identity-file <path>  Local key file to seed on the remote host.
                          Default: ~/.ssh/claude-share-<server-slug>
  --local-prefix <path>   Local install prefix. Default: ~/.local
  --remote-prefix <path>  Remote install prefix. Default: ~/.local
  -h, --help              Show this help.
EOF
}

_cmd_tunnel_bootstrap_expect_copy() {
  local src="$1" dst="$2"
  SRC="$src" DST="$dst" SERVER="$CS_TUNNEL_BOOTSTRAP_SERVER" PASSWORD="$CS_TUNNEL_BOOTSTRAP_PASSWORD" expect <<'EOF'
set timeout 120
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -- $env(SRC) "$env(SERVER):$env(DST)"
expect {
  "*password:" { send "$env(PASSWORD)\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
EOF
}

_cmd_tunnel_bootstrap_expect_ssh() {
  local remote_cmd="$1"
  REMOTE_CMD="$remote_cmd" SERVER="$CS_TUNNEL_BOOTSTRAP_SERVER" PASSWORD="$CS_TUNNEL_BOOTSTRAP_PASSWORD" expect <<'EOF'
set timeout 120
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$env(SERVER)" "$env(REMOTE_CMD)"
expect {
  "*password:" { send "$env(PASSWORD)\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
EOF
}

_cmd_tunnel_bootstrap_copy_to_remote() {
  local src="$1" dst="$2"
  if [[ -n "${CS_TUNNEL_BOOTSTRAP_PASSWORD:-}" ]]; then
    _cmd_tunnel_bootstrap_expect_copy "$src" "$dst"
  else
    scp \
      -i "$CS_TUNNEL_BOOTSTRAP_IDENTITY_FILE" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -- "$src" "$CS_TUNNEL_BOOTSTRAP_SERVER:$dst"
  fi
}

_cmd_tunnel_bootstrap_run_remote() {
  local remote_cmd="$1"
  if [[ -n "${CS_TUNNEL_BOOTSTRAP_PASSWORD:-}" ]]; then
    _cmd_tunnel_bootstrap_expect_ssh "$remote_cmd"
  else
    ssh \
      -i "$CS_TUNNEL_BOOTSTRAP_IDENTITY_FILE" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$CS_TUNNEL_BOOTSTRAP_SERVER" "$remote_cmd"
  fi
}

_cmd_tunnel_bootstrap_install_local() {
  local prefix="$1"
  local install_dir="$prefix/lib/claude-share"
  local bin_link="$prefix/bin/claude-share"
  local cs_link="$prefix/bin/cs"
  local src_root="$ROOT_DIR"
  local tmp_stage=""

  if [[ "$src_root" == "$install_dir" ]]; then
    tmp_stage="$(mktemp -d)"
    cp -a "$src_root/bin" "$src_root/lib" "$src_root/commands" "$tmp_stage/"
    src_root="$tmp_stage"
  fi

  install -d -m 755 "$install_dir" "$prefix/bin"
  rm -rf "${install_dir:?}/bin" "${install_dir:?}/lib" "${install_dir:?}/commands"
  cp -a "$src_root/bin" "$src_root/lib" "$src_root/commands" "$install_dir/"
  chmod +x "$install_dir/bin/claude-share"
  chmod +x "$install_dir/bin/cs"
  ln -sfn "$install_dir/bin/claude-share" "$bin_link"
  ln -sfn "$install_dir/bin/cs" "$cs_link"

  if [[ -n "$tmp_stage" ]]; then
    rm -rf "$tmp_stage"
  fi
}

cmd_tunnel_bootstrap() {
  local server="" password="" identity_file="" local_prefix="$HOME/.local"
  local remote_prefix='$HOME/.local'
  local tmp_dir="" payload="" remote_tmp_dir="" remote_payload="" remote_pub="" remote_script=""
  local script_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --server)        server="$2"; shift 2 ;;
      --password)      password="$2"; shift 2 ;;
      --identity-file) identity_file="$2"; shift 2 ;;
      --local-prefix)  local_prefix="$2"; shift 2 ;;
      --remote-prefix) remote_prefix="$2"; shift 2 ;;
      -h|--help)       cmd_tunnel_bootstrap_usage; return 0 ;;
      *)               die "unknown flag: $1" ;;
    esac
  done

  [[ -n "$server" ]] || die "--server is required"
  [[ "$local_prefix" == /* ]] || die "--local-prefix must be absolute"
  [[ "$remote_prefix" == /* || "$remote_prefix" == '$HOME/'* || "$remote_prefix" == '$HOME' ]] \
    || die "--remote-prefix must be absolute or start with \$HOME"

  CS_TUNNEL_BOOTSTRAP_SERVER="$server"
  CS_TUNNEL_BOOTSTRAP_PASSWORD="$password"

  tunnel_require_cmd ssh scp ssh-keygen tar
  if [[ -n "$password" ]]; then
    tunnel_require_cmd expect
  fi
  tunnel_port_open_localhost 22 || die "local sshd is not reachable on 127.0.0.1:22"

  [[ -n "$identity_file" ]] || identity_file="$(cmd_tunnel_default_identity_file "$server")"
  [[ "$identity_file" == /* ]] || die "--identity-file must be absolute"
  CS_TUNNEL_BOOTSTRAP_IDENTITY_FILE="$identity_file"

  log "Installing claude-share locally into $local_prefix"
  _cmd_tunnel_bootstrap_install_local "$local_prefix"
  ok "Local CLI ready: $local_prefix/bin/claude-share"

  install -d -m 700 "$(dirname "$identity_file")"
  if [[ ! -f "$identity_file" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "claude-share:$server" -f "$identity_file" >/dev/null
    ok "Generated identity: $identity_file"
  fi
  chmod 600 "$identity_file"
  chmod 644 "$identity_file.pub"

  tmp_dir="$(mktemp -d)"
  payload="$tmp_dir/claude-share.tgz"
  script_file="$tmp_dir/bootstrap-remote.sh"
  remote_tmp_dir="/tmp/claude-share-bootstrap-${USER:-user}-$$"
  remote_payload="$remote_tmp_dir/payload.tgz"
  remote_pub="$remote_tmp_dir/key.pub"
  remote_script="$remote_tmp_dir/bootstrap.sh"

  tar -C "$ROOT_DIR" -czf "$payload" bin lib commands
  cat > "$script_file" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

remote_prefix=$remote_prefix
remote_install="\$remote_prefix/lib/claude-share"
remote_bin="\$remote_prefix/bin/claude-share"
remote_cs="\$remote_prefix/bin/cs"
remote_tmp_dir=$(printf '%q' "$remote_tmp_dir")
remote_payload=$(printf '%q' "$remote_payload")
remote_pub=$(printf '%q' "$remote_pub")

install -d -m 755 "\$remote_install" "\$remote_prefix/bin"
rm -rf "\$remote_install/bin" "\$remote_install/lib" "\$remote_install/commands"
tar -C "\$remote_install" -xzf "\$remote_payload"
chmod +x "\$remote_install/bin/claude-share"
chmod +x "\$remote_install/bin/cs"
ln -sfn "\$remote_install/bin/claude-share" "\$remote_bin"
ln -sfn "\$remote_install/bin/cs" "\$remote_cs"

install -d -m 700 "\$HOME/.ssh"
touch "\$HOME/.ssh/authorized_keys"
chmod 600 "\$HOME/.ssh/authorized_keys"
pubkey="\$(cat "\$remote_pub")"
grep -qxF "\$pubkey" "\$HOME/.ssh/authorized_keys" || printf '%s\n' "\$pubkey" >> "\$HOME/.ssh/authorized_keys"

rm -rf "\$remote_tmp_dir"

printf 'remote_cli=%s\n' "\$remote_bin"
command -v sshfs >/dev/null && printf 'sshfs=%s\n' "\$(command -v sshfs)" || printf 'sshfs=<missing>\n'
if command -v fusermount >/dev/null; then
  printf 'fusermount=%s\n' "\$(command -v fusermount)"
elif command -v fusermount3 >/dev/null; then
  printf 'fusermount=%s\n' "\$(command -v fusermount3)"
else
  printf 'fusermount=<missing>\n'
fi
EOF
  chmod 700 "$script_file"
  _cmd_tunnel_bootstrap_cleanup() {
    [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]] && rm -rf "$tmp_dir"
  }
  trap _cmd_tunnel_bootstrap_cleanup EXIT

  _cmd_tunnel_bootstrap_run_remote "install -d -m 700 $(printf '%q' "$remote_tmp_dir")"
  _cmd_tunnel_bootstrap_copy_to_remote "$payload" "$remote_payload"
  _cmd_tunnel_bootstrap_copy_to_remote "$identity_file.pub" "$remote_pub"
  _cmd_tunnel_bootstrap_copy_to_remote "$script_file" "$remote_script"

  log "Installing claude-share on $server"
  _cmd_tunnel_bootstrap_run_remote "bash $(printf '%q' "$remote_script")"

  log "Verifying key-based SSH login"
  ssh -i "$identity_file" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$server" 'printf "key-login-ok\n"' >/dev/null
  ok "Remote key login verified"

  printf '\n'
  log "Bootstrap complete. Reusable tunnel command:"
  printf '  %q tunnel serve --workspace %q --server %q --ssh-arg -i --ssh-arg %q --ssh-arg -o --ssh-arg StrictHostKeyChecking=no --ssh-arg -o --ssh-arg UserKnownHostsFile=/dev/null\n' \
    "$local_prefix/bin/claude-share" "$PWD" "$server" "$identity_file"
}
