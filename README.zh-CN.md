# claude-share

[English](README.md) | 简体中文

在同一台 Linux 机器上，多个系统用户共享 Claude Code 的鉴权信息，同时**严格隔离**
每个用户的会话和项目数据。

> **问题。** 你在服务器上给同事建了 `usera` 和 `userb` 两个账号。他们各自登录、跑
> `claude`，然后……都得重新 `/login`、重新配一遍。Claude Code 把 OAuth token 存在
> `~/.claude/.credentials.json` —— 这是每个用户私有的家目录文件。
>
> **笨方法。** 把 `/home/usera/.claude` 和 `/home/userb/.claude` 都指向 `/shared/.claude`。
> 结果两个人共享了会话历史、项目记录、shell 快照、命令历史 —— 并且只要两个人
> 同时跑 `claude`，就会互相覆盖彼此的状态。
>
> **`claude-share`。** 只共享真正承载鉴权和全局配置的那 4 个文件；运行时状态
> （`projects/`、`sessions/`、`history.jsonl` 等）严格保持每用户独立。一条命令
> 完成：创建 Linux 用户、建共享 POSIX 组、用软链把所有东西串起来。

## 到底共享了什么

| 路径（相对 `$HOME`） | 共享？ | 原因 |
|---|---|---|
| `.claude/.credentials.json` | ✅ | OAuth token —— 真正要共享的东西 |
| `.claude.json` | ✅ | 全局功能开关和客户端设置 |
| `.claude/settings.json` | ✅ | 全局偏好（effort level、theme 等） |
| `.claude/settings.local.json` | ✅（可关） | CLI 权限的 `allow` 列表 |
| `.claude/projects/` | ❌ | 按 cwd 哈希的会话记录，每用户独立 |
| `.claude/sessions/` | ❌ | 运行时 session 元数据 |
| `.claude/history.jsonl` | ❌ | 命令历史 |
| `.claude/shell-snapshots/` | ❌ | 每会话的 shell 状态 |
| `.claude/plans/`、`todos/`、`statsig/`、`ide/` | ❌ | 每会话或每安装的状态 |

共享文件只存一份，放在 `/shared/claude-share/home/<相对路径>`，每个受管用户的
`$HOME/<相对路径>` 都是指向这份实文件的软链。Claude 刷新 OAuth token 时，写入
会透过软链落到共享文件上，其他用户下次读文件就自然拿到新 token —— 不需要任何
后台进程。

## 安装

```bash
git clone https://github.com/<owner>/claude-share.git
cd claude-share
sudo ./install.sh
```

发布后也可以用：

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/claude-share/main/install.sh \
  | sudo bash
```

## 快速上手

```bash
# 1. 作为源用户先 /login 一次（如果之前没做过）
sudo -iu root
claude /login    # 走一遍 OAuth 流程
exit

# 2. 初始化：创建用户并接入共享鉴权
sudo claude-share init
# [claude-share] Shared directory [/shared/claude-share]:
# [claude-share] Shared group [claudeshare]:
# [claude-share] How many users to create now? [2]:
#   user 1 name: usera
#   user 1 password: ********
#   Confirm user 1 password: ********
#   user 2 name: userb
#   user 2 password: ********
#   Confirm user 2 password: ********
# [claude-share] ✓ Created group: claudeshare
# [claude-share] ✓ Created user: usera
# [claude-share] ✓ Created user: userb
# [claude-share] ✓ Linked usera to shared auth
# [claude-share] ✓ Linked userb to shared auth
# [claude-share] Done. Managed users: usera userb

# 3. 查看状态
sudo claude-share status

# 4. 两个用户都可以直接跑 claude，不用再 /login
su - usera -c 'claude --help'
su - userb -c 'claude --help'
```

## 子命令一览

| 命令 | 作用 |
|---|---|
| `init` | 首次初始化：交互式创建用户、建组、接入共享鉴权 |
| `add-user <name>` | 后续继续加人。默认交互式输入密码，也可以用 `--password` |
| `remove-user <name>` | 把某个用户从共享体系中摘出来：软链替换回实文件，移出共享组。加 `--delete-account` 连同 `userdel -r` |
| `status` | 打印配置、权限，以及每个受管用户每条软链的健康检查 ✓/✗，并解析 `.credentials.json` 的 `expiresAt` |
| `sync` | 重新套用所有软链 —— 用户误删软链、或升级 `claude-share` 后用 |
| `uninstall` | 把软链全部替换回实文件、把用户从共享组剔出。加 `--purge-shared-dir` 同时删掉 `/shared/claude-share`。**永远不会**删除 Linux 账号 |

每个命令加 `--help` 可以看所有选项。

## 非交互模式

所有提示都可以跳过，方便自动化部署：

```bash
sudo claude-share init --yes \
  --shared-dir /shared/claude-share \
  --group claudeshare \
  --user usera:usera1234 \
  --user userb:userb1234

sudo claude-share add-user alice --password 'alice-pw-with $peci@l chars'
```

⚠️ 注意：在命令行上直接传密码会泄露到 `ps` 和进程审计里。多用户机器上建议用
交互模式。

## 权限布局

```
/shared/claude-share/                             drwxrws--- root  claudeshare
├── home/                                         drwxrws--- root  claudeshare
│   ├── .claude.json                              -rw-rw---- root  claudeshare
│   └── .claude/
│       ├── .credentials.json                     -rw-rw---- root  claudeshare
│       ├── settings.json                         -rw-rw---- root  claudeshare
│       └── settings.local.json                   -rw-rw---- root  claudeshare
```

- 目录 `2770`：**setgid 位**让新文件自动继承 `claudeshare` 组。
- 文件 `660`：组内成员可读写，其他用户完全看不到。
- 每个受管用户的 `~/.bashrc` 会被幂等追加一行 `umask 002`，保证他们新建的文件
  是 `664`/`775`。不这么做的话，一个用户写的文件会让另一个用户没法修改。

## **不共享**的东西（以及为什么要注意）

`projects/` 是按照 **绝对工作目录路径** 做 key 的。如果两个用户都 `cd` 到
`/shared/workspace` 去跑 `claude`，他们会同时写 `projects/-shared-workspace/…`
—— 而这些文件又分别在两人各自的 `$HOME` 下，`claude-share` 管不到。建议：

- **推荐做法**：每个用户在自己家目录，或者在 `/shared` 下各自独立的子目录里跑。
- **必须共享工作目录**：协调好同一时间只有一个人在里面跑 `claude`。

## FAQ

**Claude Code 升级后会坏吗？** 不会。共享条目的清单定义在 `lib/paths.sh` 里。
如果未来 Claude 加了新的鉴权文件，把它加到那个列表，再跑 `sudo claude-share sync`
就行。

**Token 刷新安全吗？** Claude 刷新 OAuth token 时用的是 "写临时文件 + `rename(2)`"
的方式。因为我们用的是软链，`rename(2)` 落到的是共享 inode，其他用户下次读到的
就是新 token。无需守护进程。

**能共享鉴权但私有化 `settings.local.json` 吗？** 可以。`init` 时加
`--no-settings-local`，或者编辑 `/etc/claude-share/config` 把 `SHARE_SETTINGS_LOCAL`
改成 `false`，再跑 `sudo claude-share sync`。

**SELinux / systemd-homed / Alpine 支持吗？** 核心部分（软链、POSIX 组、chmod/chown）
在哪都能跑。用户创建走的是 `useradd`/`chpasswd`，在 Debian/Ubuntu/RHEL/Arch 上
都没问题。Alpine 默认用 `adduser`，欢迎 PR。

**两个用户同时刷新 token 会冲突吗？** 共享文件是单个 inode，660 权限。并发刷新在
操作系统层面是安全的（原子 rename）；唯一的风险是 Claude 自己的刷新逻辑使用
就地写入（in-place write）—— 但它没这么干。

## 开发

```bash
# Shell 静态检查
shellcheck --severity=warning bin/claude-share lib/*.sh commands/*.sh install.sh

# 单元测试（无需 root，不会创建真实用户）
bats tests/unit

# 端到端测试（构建一次性的 Ubuntu 容器）
docker build -f tests/integration/Dockerfile -t claude-share-e2e .
docker run --rm claude-share-e2e
```

项目结构：

```
bin/claude-share        # 入口脚本
lib/                    # common/paths/users/sync/prompt 各个辅助模块
commands/               # 每个子命令一个文件
tests/unit/             # bats 单元测试
tests/integration/      # Dockerfile + e2e.bats
.github/workflows/      # shellcheck + bats + docker e2e
```

## 许可证

MIT —— 详见 [LICENSE](LICENSE)。
