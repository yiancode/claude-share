#!/usr/bin/env bash
# sync.sh — shared dir bootstrap + per-user symlink creation/repair
#
# The "single copy" of each shared item lives at:
#   $SHARED_DIR/home/<relpath>
# and every managed user's $HOME/<relpath> is a symlink to that single copy.

SHARED_HOME_SUBDIR="home"

# Path inside $SHARED_DIR where the canonical copy of $relpath lives.
shared_target_for() {
  local rel="$1"
  printf '%s/%s/%s' "$SHARED_DIR" "$SHARED_HOME_SUBDIR" "$rel"
}

# Create (or fix) the shared directory tree. Files and dirs are owned by
# $SOURCE_USER:$SHARE_GROUP, directories are 2770 (setgid so new files
# inherit the group), files are 660.
bootstrap_shared_dir() {
  priv_install_dir 2770 "$SOURCE_USER" "$SHARE_GROUP" "$SHARED_DIR"
  priv_install_dir 2770 "$SOURCE_USER" "$SHARE_GROUP" "$SHARED_DIR/$SHARED_HOME_SUBDIR"
}

# Move $SOURCE_USER's existing files into the shared dir. If a file does not
# exist yet, create a zero-byte placeholder so we have something to link to.
# Idempotent: if the canonical copy already exists, leave it alone.
seed_shared_from_source_user() {
  local src_home rel abs_src abs_shared parent
  src_home="$(user_home "$SOURCE_USER")" || die "cannot find home for $SOURCE_USER"

  while IFS= read -r rel; do
    abs_src="$src_home/$rel"
    abs_shared="$(shared_target_for "$rel")"
    parent="$(dirname "$abs_shared")"
    priv_install_dir 2770 "$SOURCE_USER" "$SHARE_GROUP" "$parent"

    if [[ -L "$abs_shared" ]]; then
      # Should not be a symlink — something's weird; replace.
      rm -f "$abs_shared"
    fi

    if [[ -e "$abs_shared" ]]; then
      # Already seeded; leave alone.
      :
    elif [[ -L "$abs_src" ]]; then
      # Source is already a symlink — most likely pointing here. Do nothing.
      :
    elif [[ -f "$abs_src" ]]; then
      mv "$abs_src" "$abs_shared"
    else
      : > "$abs_shared"
    fi

    priv_chown "$SOURCE_USER:$SHARE_GROUP" "$abs_shared"
    chmod 660 "$abs_shared"
  done < <(shared_items)
}

# For a given user, make sure every SHARED_ITEM under their $HOME is a
# symlink pointing at the shared copy. Backs up any pre-existing real files
# so nothing is silently destroyed.
link_user_to_shared() {
  local user="$1"
  local home rel abs_home abs_shared parent backup_dir ts
  home="$(user_home "$user")" || die "cannot find home for $user"
  [[ -d "$home" ]] || die "home directory missing for $user: $home"

  ts="$(date +%s)"
  backup_dir="$home/.claude-share.bak.$ts"

  while IFS= read -r rel; do
    abs_home="$home/$rel"
    abs_shared="$(shared_target_for "$rel")"
    parent="$(dirname "$abs_home")"

    # Ensure parent directory exists and is user-owned (not shared).
    if [[ ! -d "$parent" ]]; then
      priv_install_dir 755 "$user" "$user" "$parent"
    fi

    if [[ -L "$abs_home" ]]; then
      local cur
      cur="$(readlink "$abs_home")"
      if [[ "$cur" == "$abs_shared" ]]; then
        continue
      fi
      rm -f "$abs_home"
    elif [[ -e "$abs_home" ]]; then
      priv_install_dir 700 "$user" "$user" "$backup_dir"
      local dest="$backup_dir/$rel"
      priv_install_dir 755 "$user" "$user" "$(dirname "$dest")"
      mv "$abs_home" "$dest"
      warn "Backed up $abs_home -> $dest"
    fi

    ln -sfn "$abs_shared" "$abs_home"
    priv_chown_link "$user:$user" "$abs_home"
  done < <(shared_items)
}

# Replace every SHARED_ITEM symlink in a user's home with a real copy of the
# current shared content. Used by uninstall and remove-user.
unlink_user_from_shared() {
  local user="$1"
  local home rel abs_home abs_shared
  home="$(user_home "$user")" || return 0
  [[ -d "$home" ]] || return 0

  while IFS= read -r rel; do
    abs_home="$home/$rel"
    abs_shared="$(shared_target_for "$rel")"
    if [[ -L "$abs_home" ]]; then
      rm -f "$abs_home"
      if [[ -f "$abs_shared" ]]; then
        cp -a "$abs_shared" "$abs_home"
        priv_chown "$user:$user" "$abs_home"
        chmod 600 "$abs_home"
      fi
    fi
  done < <(shared_items)
}
