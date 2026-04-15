#!/usr/bin/env bash
# commands/status.sh — show what's configured and whether it's healthy

cmd_status() {
  if ! load_config; then
    err "claude-share is NOT initialized (no $CS_CONFIG_FILE)"
    return 1
  fi

  printf '%s Configuration\n' "$CS_TAG"
  printf '  shared dir           : %s\n' "$SHARED_DIR"
  printf '  shared group         : %s\n' "$SHARE_GROUP"
  printf '  source user          : %s\n' "$SOURCE_USER"
  printf '  share settings.local : %s\n' "$SHARE_SETTINGS_LOCAL"
  printf '  managed users        : %s\n' "${MANAGED_USERS[*]:-<none>}"
  printf '\n'

  # Shared dir permissions
  printf '%s Shared dir\n' "$CS_TAG"
  if [[ -d "$SHARED_DIR" ]]; then
    local perms
    perms="$(stat -c '%A %U:%G' "$SHARED_DIR")"
    printf '  %s  %s\n' "$SHARED_DIR" "$perms"
  else
    printf '  %s  %sMISSING%s\n' "$SHARED_DIR" "$CS_C_RED" "$CS_C_RESET"
  fi
  printf '\n'

  # Credential freshness
  local cred="$SHARED_DIR/home/.claude/.credentials.json"
  printf '%s Credentials\n' "$CS_TAG"
  if [[ -f "$cred" ]]; then
    printf '  file : %s\n' "$cred"
    printf '  perms: %s\n' "$(stat -c '%A %U:%G' "$cred")"
    # Try to read expiresAt without printing secrets
    if command -v python3 >/dev/null; then
      python3 - "$cred" <<'PY' || true
import json, sys, time
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    exp = d.get("claudeAiOauth", {}).get("expiresAt")
    if not exp:
        print("  expiresAt: <unknown>")
    else:
        exp_s = int(exp) / 1000 if exp > 1e12 else int(exp)
        remaining = exp_s - time.time()
        state = "valid" if remaining > 0 else "EXPIRED"
        print(f"  expiresAt: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(exp_s))} ({state}, {int(remaining)}s)")
except Exception as e:
    print(f"  expiresAt: <parse error: {e}>")
PY
    fi
  else
    printf '  %sno credentials file in shared dir%s\n' "$CS_C_YELLOW" "$CS_C_RESET"
    printf '  run `claude /login` as %s to populate it\n' "$SOURCE_USER"
  fi
  printf '\n'

  # Per-user symlink health
  printf '%s Per-user links\n' "$CS_TAG"
  local u rel abs_home abs_shared status
  for u in "${MANAGED_USERS[@]}"; do
    printf '  user: %s\n' "$u"
    if ! user_exists "$u"; then
      printf '    %sno such Linux user%s\n' "$CS_C_RED" "$CS_C_RESET"
      continue
    fi
    if id -nG "$u" | tr ' ' '\n' | grep -qx "$SHARE_GROUP"; then
      printf '    group %s: ✓\n' "$SHARE_GROUP"
    else
      printf '    group %s: %s✗%s\n' "$SHARE_GROUP" "$CS_C_RED" "$CS_C_RESET"
    fi
    local home; home="$(user_home "$u")"
    while IFS= read -r rel; do
      abs_home="$home/$rel"
      abs_shared="$(shared_target_for "$rel")"
      if [[ -L "$abs_home" && "$(readlink "$abs_home")" == "$abs_shared" ]]; then
        status="${CS_C_GREEN}✓${CS_C_RESET}"
      else
        status="${CS_C_RED}✗${CS_C_RESET}"
      fi
      printf '    %s %s\n' "$status" "$rel"
    done < <(shared_items)
  done
}
