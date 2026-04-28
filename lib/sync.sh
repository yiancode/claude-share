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

# Copy $SOURCE_USER's existing files into the shared dir. The source file is
# left in place so nothing running as $SOURCE_USER (including an active
# claude session) loses access mid-init. link_user_to_shared will later
# atomically replace the source file with a symlink.
#
# If the source file doesn't exist yet, we create a zero-byte placeholder so
# we always have something to link to.
# Idempotent: if the canonical copy already exists, it's left alone.
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
      # Shared copy exists. If the source user's file is a real file (severed
      # symlink after a Claude token refresh), it holds a fresher token —
      # overwrite the shared copy so managed users get the new credentials.
      if [[ -f "$abs_src" && ! -L "$abs_src" ]]; then
        cp -a "$abs_src" "$abs_shared"
      fi
    elif [[ -L "$abs_src" ]]; then
      # Source is already a symlink — most likely pointing here. Do nothing.
      :
    elif [[ -f "$abs_src" ]]; then
      cp -a "$abs_src" "$abs_shared"
    else
      # Claude Code parses these files as JSON on startup; a zero-byte file
      # makes it throw on first run. Seed with an empty JSON object so the
      # symlink chain is immediately usable, even before any user has run
      # `claude /login`. Only `.credentials.json` is exempt — Claude itself
      # treats a missing credentials file as "not logged in" and handles it,
      # while an empty-object credentials file would look like a corrupt
      # login.
      case "$rel" in
        *.credentials.json) : > "$abs_shared" ;;
        *)                  printf '{}\n' > "$abs_shared" ;;
      esac
    fi

    priv_chown "$SOURCE_USER:$SHARE_GROUP" "$abs_shared"
    chmod 660 "$abs_shared"
  done < <(shared_items)
}

# Atomically replace $path with a symlink to $target. "Atomically" means
# there is no instant where $path doesn't exist: we stage the symlink next
# to it and use rename(2) to swap. This matters when a running process
# (e.g. an active claude session) may read the file mid-operation.
_atomic_symlink() {
  local target="$1" path="$2"
  local stage="${path}.claude-share.stage.$$"
  ln -sfn "$target" "$stage"
  mv -f "$stage" "$path"
}

# For a given user, make sure every SHARED_ITEM under their $HOME is a
# symlink pointing at the shared copy. Backs up any pre-existing real files
# so nothing is silently destroyed.
link_user_to_shared() {
  local user="$1"
  local home rel abs_home abs_shared parent backup_dir ts
  home="$(user_home "$user")" || die "cannot find home for $user"
  [[ -d "$home" ]] || die "home directory missing for $user: $home"

  # Include nanoseconds + PID so rapid successive calls (tests, scripted
  # sync) can't collide on a single-second boundary.
  ts="$(date +%s%N).$$"
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
      # Wrong symlink target — replace atomically.
      _atomic_symlink "$abs_shared" "$abs_home"
      priv_chown_link "$user:$user" "$abs_home"
      continue
    fi

    if [[ -e "$abs_home" ]]; then
      # A real file exists. Back it up under a per-user backup dir so
      # nothing is silently destroyed, then atomically replace with symlink.
      priv_install_dir 700 "$user" "$user" "$backup_dir"
      local dest="$backup_dir/$rel"
      priv_install_dir 755 "$user" "$user" "$(dirname "$dest")"
      cp -a "$abs_home" "$dest"
      warn "Backed up $abs_home -> $dest"
    fi

    _atomic_symlink "$abs_shared" "$abs_home"
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
