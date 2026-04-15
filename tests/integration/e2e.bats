#!/usr/bin/env bats
#
# End-to-end test. Must run as root inside a disposable container.
# Expects claude-share installed at /usr/local/bin/claude-share.

setup() {
  export HOME=/root
  mkdir -p /root/.claude
  echo '{"claudeAiOauth":{"accessToken":"fake","refreshToken":"fake","expiresAt":9999999999000,"scopes":["user:inference"],"subscriptionType":"pro"}}' \
    > /root/.claude/.credentials.json
  echo '{"numStartups":1}'    > /root/.claude.json
  echo '{"effortLevel":"med"}' > /root/.claude/settings.json
  echo '{"permissions":{"allow":[]}}' > /root/.claude/settings.local.json
}

teardown() {
  claude-share uninstall --yes --purge-shared-dir || true
  userdel -r usera 2>/dev/null || true
  userdel -r userb 2>/dev/null || true
  userdel -r alice 2>/dev/null || true
  groupdel claudeshare 2>/dev/null || true
}

@test "init creates users, group, and symlinks" {
  run claude-share init --yes --user usera:usera1234 --user userb:userb1234
  [ "$status" -eq 0 ]

  # Users and group
  getent passwd usera >/dev/null
  getent passwd userb >/dev/null
  getent group claudeshare | grep -q 'usera'
  getent group claudeshare | grep -q 'userb'

  # Symlinks
  [ -L /home/usera/.claude/.credentials.json ]
  [ -L /home/userb/.claude/.credentials.json ]
  [ "$(readlink /home/usera/.claude/.credentials.json)" = "/shared/claude-share/home/.claude/.credentials.json" ]
  [ "$(readlink /home/userb/.claude/.credentials.json)" = "/shared/claude-share/home/.claude/.credentials.json" ]

  # Shared file exists and carries original content
  [ -f /shared/claude-share/home/.claude/.credentials.json ]
  grep -q '"accessToken":"fake"' /shared/claude-share/home/.claude/.credentials.json

  # Both users can read it
  su - usera -c 'cat ~/.claude/.credentials.json' >/dev/null
  su - userb -c 'cat ~/.claude/.credentials.json' >/dev/null
}

@test "status reports healthy" {
  claude-share init --yes --user usera:usera1234 --user userb:userb1234
  run claude-share status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "managed users.*usera.*userb"
  echo "$output" | grep -q "\.credentials\.json"
}

@test "add-user and remove-user round trip" {
  claude-share init --yes --user usera:usera1234

  run claude-share add-user alice --password alice1234
  [ "$status" -eq 0 ]
  getent passwd alice
  getent group claudeshare | grep -q alice
  [ -L /home/alice/.claude/.credentials.json ]

  run claude-share remove-user alice
  [ "$status" -eq 0 ]
  ! getent group claudeshare | tr ',' '\n' | grep -qx alice
  [ -f /home/alice/.claude/.credentials.json ]
  [ ! -L /home/alice/.claude/.credentials.json ]
}

@test "projects dir remains per-user (not shared)" {
  claude-share init --yes --user usera:usera1234 --user userb:userb1234
  su - usera -c 'mkdir -p ~/.claude/projects/-home-usera && echo A > ~/.claude/projects/-home-usera/file'
  su - userb -c 'mkdir -p ~/.claude/projects/-home-userb && echo B > ~/.claude/projects/-home-userb/file'
  [ "$(cat /home/usera/.claude/projects/-home-usera/file)" = "A" ]
  [ "$(cat /home/userb/.claude/projects/-home-userb/file)" = "B" ]
  [ ! -e /home/usera/.claude/projects/-home-userb ]
  [ ! -e /home/userb/.claude/projects/-home-usera ]
}

@test "uninstall restores real files" {
  claude-share init --yes --user usera:usera1234

  run claude-share uninstall --yes
  [ "$status" -eq 0 ]
  [ -f /home/usera/.claude/.credentials.json ]
  [ ! -L /home/usera/.claude/.credentials.json ]
  [ ! -f /etc/claude-share/config ]
}
