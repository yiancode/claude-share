# claude-share

English | [简体中文](README.zh-CN.md)

Share Claude Code authentication across multiple Linux users on one machine,
while keeping per-user session/project data fully isolated.

> **The problem.** You create Linux accounts `usera` and `userb` so two people can
> share a server. Each of them logs in, runs `claude`, and… has to
> `/login` again and reconfigure everything from scratch. Claude Code stores
> its OAuth token in `~/.claude/.credentials.json`, which lives in each user's
> private home directory.
>
> **Naive fix.** Point `/home/usera/.claude` at `/shared/.claude` and same for
> `userb`. Now two people share their session history, project transcripts,
> shell snapshots, and command history — and they overwrite each other's
> state the moment both of them run `claude` at the same time.
>
> **`claude-share`.** Share only the four files that actually hold
> authentication and global configuration; keep the runtime state
> (`projects/`, `sessions/`, `history.jsonl`, …) strictly per-user. One
> command creates the Linux users, sets up a shared POSIX group, and wires
> everything up with symlinks.

## What exactly is shared

| Path (under `$HOME`) | Shared? | Reason |
|---|---|---|
| `.claude/.credentials.json` | ✅ | OAuth token — the thing you actually want to share |
| `.claude.json` | ✅ | Global feature flags & client settings |
| `.claude/settings.json` | ✅ | Global preferences (effort level, theme, …) |
| `.claude/settings.local.json` | ✅ (optional) | `allow` lists for CLI permissions |
| `.claude/projects/` | ❌ | Per-user session transcripts, keyed by cwd |
| `.claude/sessions/` | ❌ | Running session metadata |
| `.claude/history.jsonl` | ❌ | Command history |
| `.claude/shell-snapshots/` | ❌ | Per-session shell state |
| `.claude/plans/`, `todos/`, `statsig/`, `ide/` | ❌ | Per-session or per-install state |

Shared files live exactly once, at `/shared/claude-share/home/<relpath>`, and
each managed user's `$HOME/<relpath>` is a symlink to that single copy. When
Claude refreshes the OAuth token it writes the new value through the symlink,
so all users stay in sync with zero extra processes.

## Quick start

The full walkthrough from a fresh machine to a working multi-user setup.

### Step 0 — Prerequisites

1. You are `root`, or have `sudo`.
2. Claude Code is already installed on the machine and runnable as `claude`.
3. The **source user** (the account whose auth will be shared, usually `root`)
   has logged in to Claude at least once, so
   `~/.claude/.credentials.json` exists.

Check the source user's auth file:

```bash
sudo ls -l /root/.claude/.credentials.json
```

If it **does not** exist, run `/login` once first:

```bash
sudo -iu root
claude /login    # go through the OAuth flow in your browser
exit
```

### Step 1 — Get the code

```bash
git clone https://github.com/yiancode/claude-share.git
cd claude-share
```

After publishing, the one-liner equivalent is:

```bash
curl -fsSL https://raw.githubusercontent.com/yiancode/claude-share/main/install.sh \
  | sudo bash
```

> **Security note.** Piping `curl | bash` trusts whatever is at `main`
> right now. For production hosts, pin a specific commit SHA:
>
> ```bash
> REF=<full-sha> curl -fsSL \
>   "https://raw.githubusercontent.com/yiancode/claude-share/${REF}/install.sh" \
>   | sudo REF="${REF}" bash
> ```
>
> `install.sh` honours `REF` when cloning the repo, so both the installer
> script and the cloned source will be frozen at the same commit.

### Step 2 — Install the CLI

```bash
sudo ./install.sh
which claude-share     # expect: /usr/local/bin/claude-share
claude-share version   # expect: claude-share 0.1.0
```

`install.sh` copies `bin/ lib/ commands/` into `/usr/local/lib/claude-share/`
and symlinks the entry point to `/usr/local/bin/claude-share`. After this,
the source tree you cloned is no longer required at runtime — editing files
in the clone will **not** affect the installed copy until you re-run
`install.sh`.

If you would rather not install and just use the scripts in-place, every
`claude-share ...` command below can be replaced with
`sudo /path/to/claude-share/bin/claude-share ...`.

### Step 3 — Initialize

```bash
sudo claude-share init
```

You will be prompted for (defaults in brackets; press Enter to accept):

- **Shared directory** `[/shared/claude-share]` — where the single canonical
  copy of shared auth will live.
- **Shared group** `[claudeshare]` — the POSIX group every managed user
  joins.
- **Source user** `[root]` — whose `~/.claude/.credentials.json` is copied
  in as the initial truth source.
- **How many users to create now?** `[2]`
- For each user: **name**, then **password** (hidden, confirmed twice).

Expected output:

```text
[claude-share] Shared directory [/shared/claude-share]:
[claude-share] Shared group [claudeshare]:
[claude-share] Source user (holds current ~/.claude auth) [root]:
[claude-share] How many users to create now? [2]:
  user 1 name: usera
  user 1 password: ********
  Confirm user 1 password: ********
  user 2 name: userb
  user 2 password: ********
  Confirm user 2 password: ********
[claude-share] Creating shared group and directory...
[claude-share] ✓ Created group: claudeshare
[claude-share] ✓ Added root to group claudeshare
[claude-share] ✓ Shared dir ready: /shared/claude-share
[claude-share] ✓ Created user: usera
[claude-share] ✓ Set password for usera
[claude-share] ✓ Added usera to group claudeshare
[claude-share] ✓ Linked usera to shared auth
[claude-share] ✓ Created user: userb
[claude-share] ✓ Set password for userb
[claude-share] ✓ Added userb to group claudeshare
[claude-share] ✓ Linked userb to shared auth
[claude-share] ✓ Wrote config: /etc/claude-share/config
[claude-share] Done. Managed users: usera userb
```

### Step 4 — Verify everything is healthy

```bash
sudo claude-share status
```

Every row in the per-user link check should be marked `✓`. Example:

```text
[claude-share] Per-user links
  user: usera
    group claudeshare: ✓
    ✓ .claude/.credentials.json
    ✓ .claude.json
    ✓ .claude/settings.json
    ✓ .claude/settings.local.json
  user: userb
    group claudeshare: ✓
    ✓ .claude/.credentials.json
    ✓ .claude.json
    ✓ .claude/settings.json
    ✓ .claude/settings.local.json
```

If anything is `✗`, run `sudo claude-share sync` and re-check.

### Step 5 — Try it as each managed user

```bash
su - usera -c 'claude --help'
su - userb -c 'claude --help'
```

Neither should ask you to `/login` — they are reading the shared credentials
transparently through the symlinks.

### Step 6 — (Optional) Add more users later

```bash
sudo claude-share add-user charlie   # prompts for password
```

Or non-interactively:

```bash
sudo claude-share add-user charlie --password 'charlie1234'
```

## Subcommands

| Command | What it does |
|---|---|
| `init` | First-time setup: prompt for users, create accounts, wire up shared auth. |
| `add-user <name>` | Add another user later. Prompts for password (or `--password`). |
| `remove-user <name>` | Detach a user: replace their symlinks with real files and remove them from the shared group. Use `--delete-account` to also `userdel -r`. |
| `status` | Show config, permissions, and a per-user health check of every symlink. Also reports `expiresAt` of the cached OAuth token. |
| `sync` | Re-apply symlinks — run this if a user accidentally broke one, or after upgrading `claude-share`. |
| `uninstall` | Turn symlinks back into real files and drop users from the shared group. Add `--purge-shared-dir` to also delete `/shared/claude-share`. Linux accounts are always left alone. |

Run any command with `--help` for flags.

## Non-interactive mode

Every prompt can be skipped for automation. There are two patterns:

**Safe: passwords in a root-owned file.** `--users-from-file` takes a file
of `name:password` lines (one per line, `#` comments allowed). The file
must be mode `0600` and owned by `root`; claude-share refuses anything
else.

```bash
umask 077
cat > /root/users.txt <<'EOF'
usera:usera1234
userb:userb1234
EOF
chmod 600 /root/users.txt

sudo claude-share init --yes \
  --shared-dir /shared/claude-share \
  --group claudeshare \
  --users-from-file /root/users.txt

sudo claude-share add-user alice --password-from-file /root/alice.pw
```

**Unsafe: passwords in argv.** `--user name:password` and `--password <pw>`
still work but the password is visible to `ps` / process accounting for
the lifetime of the command. claude-share prints a warning when you use
these forms. Only acceptable on single-tenant hosts.

```bash
sudo claude-share init --yes \
  --shared-dir /shared/claude-share \
  --group claudeshare \
  --user usera:usera1234 \
  --user userb:userb1234
```

**Post-setup gotcha: re-login required.** `usermod -aG` does not affect
already-running sessions. A managed user who is logged in when
`init` / `add-user` runs must log out and log back in before `claude`
can see the new group membership — otherwise the very first `claude`
run hits EPERM on the shared credentials file. claude-share prints a
warning at the end of init/add-user reminding you of this.

## How the permissions work

```
/shared/claude-share/                             drwxrws--- root  claudeshare
├── home/                                         drwxrws--- root  claudeshare
│   ├── .claude.json                              -rw-rw---- root  claudeshare
│   └── .claude/
│       ├── .credentials.json                     -rw-rw---- root  claudeshare
│       ├── settings.json                         -rw-rw---- root  claudeshare
│       └── settings.local.json                   -rw-rw---- root  claudeshare
```

- Directories are `2770` so the **setgid bit** forces every new file to
  inherit the `claudeshare` group.
- Files are `660` — group members can read/write, nobody else sees them.
- `claude-share` adds `umask 002` to each managed user's `~/.bashrc` so
  files they write land as `664`/`775`. Without this, one user's writes
  would be unreadable to the other.

## What's **not** shared (and why it matters)

`projects/` is keyed by the absolute working-directory path of wherever the
user runs `claude`. If both users cd into `/shared/workspace` and run
`claude`, they would both write to `projects/-shared-workspace/…` — that
collides regardless of what `claude-share` does, because those files live in
each user's private `$HOME`. Recommendations:

- **Recommended:** each user works in their own home directory or a
  user-specific subdirectory of `/shared`.
- If you must share a working directory, coordinate so only one person runs
  `claude` in it at a time.

## FAQ

**Does it survive Claude Code upgrades?** Yes. The set of shared items is
defined in `lib/paths.sh`. If a future version of Claude adds a new auth
file, update that list and re-run `sudo claude-share sync`.

**What about token refresh?** When Claude refreshes the OAuth token, it
writes the new value back to `.credentials.json`. Two behaviours are
possible:

- **Write in place** (open + truncate + write): the write follows the
  symlink and lands on the shared inode. Every user's next read picks
  up the new token. Zero coordination needed.
- **Write tempfile + `rename(2)`**: `rename(2)` replaces **the symlink
  itself** with a fresh real file in `$HOME`. The symlink chain is
  broken for that user — their next read still works (they own the
  real file now), but other users are still pointing at the old shared
  file, which is no longer being updated. **This is the "severed
  symlink" failure mode.**

`claude-share status` detects both broken symlinks and severed symlinks
and tells you to run `sudo claude-share sync`, which backs up the rogue
local file and restores the symlink. Running status periodically (e.g.
via cron) is recommended on busy multi-user hosts.

**Can I share auth but keep `settings.local.json` private?** Yes — pass
`--no-settings-local` to `init`, or edit `/etc/claude-share/config` and
set `SHARE_SETTINGS_LOCAL=false` then run `sudo claude-share sync`.

**Can I use it with SELinux / systemd-homed / Alpine?** The core (symlinks,
POSIX groups, chmod/chown) works anywhere. User creation goes through
`useradd`/`chpasswd`, which is fine on Debian/Ubuntu/RHEL/Arch. Alpine uses
`adduser` by default — patches welcome.

**What if two users both need to refresh the token at the same time?** The
shared file is a single inode with 660 permissions. At the OS level each
individual write is atomic (either rename or O_TRUNC+write of a small
JSON blob), so the file will not be corrupted. However, claude-share does
**not** merge or serialise the logical refresh: if both users refresh
concurrently, last-writer-wins on the shared inode. In practice the
window is tiny (refresh takes a few hundred ms and happens rarely), and
both refreshes produce an equivalent fresh token, so this is usually
benign. If you see frequent OAuth errors on a multi-user host, run
`claude-share status` to check for severed symlinks — those cause many
more user-visible failures than races do.

## Development

```bash
# Shell-lint
shellcheck --severity=warning bin/claude-share lib/*.sh commands/*.sh install.sh

# Unit tests (no root needed, no real users created)
bats tests/unit

# End-to-end tests (builds a disposable Ubuntu container)
docker build -f tests/integration/Dockerfile -t claude-share-e2e .
docker run --rm claude-share-e2e
```

Project layout:

```
bin/claude-share        # entrypoint
lib/                    # common/paths/users/sync/prompt helpers
commands/               # one file per subcommand
tests/unit/             # bats unit tests
tests/integration/      # Dockerfile + e2e.bats
.github/workflows/      # shellcheck + bats + docker e2e
```

## License

MIT — see [LICENSE](LICENSE).
