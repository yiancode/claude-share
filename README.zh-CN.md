# claude-share

[English](README.md) | 简体中文

在同一台 Linux 机器上，多个系统用户共享 Claude Code 的鉴权信息，同时**严格隔离**
每个用户的会话和项目数据。

现在也包含一个 **SSH 反向隧道工作区模式**：把本地工作区通过 SSH 发布到
Linux 服务器，在服务器上用 `sshfs` 挂载，并把常见构建/测试命令代理回本地执行，
这样消耗的是本地 CPU / 内存。

## 推荐体验：三步完成

新版推荐把命令面分成三层：

- **服务器初始化**：`claude-share server ...`
- **本地初始化**：`claude-share client ...`
- **日常使用**：`cs ...`

### 第一步：服务器上初始化一次

```bash
sudo claude-share server init
```

后续加用户：

```bash
sudo claude-share server add-user alice
sudo claude-share server add-user bob
```

### 第二步：本地初始化一次

```bash
claude-share client init st@43.162.99.88
```

这一步会：

- 安装/更新本地 CLI
- 安装/更新远端 CLI
- 生成或复用 SSH key
- 下发公钥到远端
- 检查本地 sshd 与远端 `sshfs`
- 保存默认 client profile

### 第三步：以后每次只在当前目录执行一条命令

```bash
cd /your/project
cs live
```

默认行为：

1. 发布当前目录
2. 建立反向 SSH 隧道
3. 自动选择远端空闲端口
4. 自动在远端挂载当前目录
5. 自动进入远端挂载目录
6. 自动启动远端 `claude`

在真正进入远端 `claude` 前，`cs live` 会先打印一段欢迎摘要，告诉你：

- 当前 server
- 当前 session
- 主挂载目录
- 所有额外挂载目录
- 停止命令 `cs stop`

示例输出：

```text
[claude-share] Live mount paths
  session          myproj-20260419-001500
  main             /home/st/.claude-share/mounts/myproj-20260419-001500 <= /Users/me/work/myproj
  extra            /home/st/.claude-share/extras/myproj-20260419-001500/1-data <= /Users/me/data
```

如果还要附加别的目录：

```bash
cs add ~/Documents/data
cs list
cs remove ~/Documents/data
```

查看当前 live session 在远端的挂载路径：

```bash
cs where
```

查看当前状态的机器可读 JSON：

```bash
cs status --json
```

结束当前 live session：

```bash
cs stop
```

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

## 经典共享鉴权快速上手

从一台干净的机器开始，一步步走到多用户共享完成，不省略任何步骤。

### 第 0 步 —— 准备工作

1. 你是 `root`，或者有 `sudo` 权限。
2. Claude Code 已经装在这台机器上，能直接跑 `claude`。
3. **源用户**（用来提供共享鉴权的账号，通常是 `root`）**至少登录过一次 Claude**，
   所以 `~/.claude/.credentials.json` 已经存在。

检查源用户的鉴权文件是否就绪：

```bash
sudo ls -l /root/.claude/.credentials.json
```

如果**不存在**，先 `/login` 一次：

```bash
sudo -iu root
claude /login    # 在浏览器走一次 OAuth 流程
exit
```

### 第 1 步 —— 拉代码

```bash
git clone https://github.com/yiancode/claude-share.git
cd claude-share
```

发布后的一行等价写法：

```bash
curl -fsSL https://raw.githubusercontent.com/yiancode/claude-share/main/install.sh \
  | sudo bash
```

### 第 2 步 —— 安装 CLI

```bash
sudo ./install.sh
which claude-share     # 期望: /usr/local/bin/claude-share
claude-share version   # 期望: claude-share 0.1.0
```

`install.sh` 做的事：把 `bin/ lib/ commands/` 拷到 `/usr/local/lib/claude-share/`，
再把入口软链到 `/usr/local/bin/claude-share`。这步跑完之后，你 clone 的源码
目录跟运行时副本就**解绑**了 —— 改了源码想生效必须再跑一次 `install.sh`。

如果你不想做全局安装，下面所有 `claude-share ...` 命令都可以改成
`sudo /path/to/claude-share/bin/claude-share ...` 直接用源码树。

### 第 3 步 —— 初始化

```bash
sudo claude-share init
```

会依次提示（中括号是默认值，直接回车接受）：

- **Shared directory** `[/shared/claude-share]` —— 共享鉴权的真身存放目录。
- **Shared group** `[claudeshare]` —— 所有受管用户加入的 POSIX 组名。
- **Source user** `[root]` —— 谁的 `~/.claude/.credentials.json` 作为初始真相源。
- **How many users to create now?** `[2]` —— 要建几个用户。
- 然后对每个用户依次问：**用户名**、**密码**（隐藏输入，确认两次）。

期望的输出：

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

### 第 4 步 —— 核对健康状态

```bash
sudo claude-share status
```

"Per-user links" 下每一行都应该是 `✓`：

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

有 `✗` 的话，跑一次 `sudo claude-share sync` 再核一遍。

### 第 5 步 —— 以两个用户的身份跑 claude

```bash
su - usera -c 'claude --help'
su - userb -c 'claude --help'
```

两个都不应该再要求 `/login` —— 他们通过软链透明读到了共享凭证。

### 第 6 步 —— （可选）后续加人

```bash
sudo claude-share add-user charlie   # 交互式输密码
```

或者非交互：

```bash
sudo claude-share add-user charlie --password 'charlie1234'
```

## 子命令一览

| 命令 | 作用 |
|---|---|
| `server init` | 服务器端初始化共享 Claude 认证与多用户环境 |
| `server add-user` | 服务器后续继续加用户 |
| `server status` | 查看服务器共享认证健康状态 |
| `client init <user@host>` | 本地初始化并引导远端就绪 |
| `client status` | 查看本地保存的默认服务器配置 |
| `cs live` | 从当前目录一键建立 live 会话并启动远端 Claude |
| `cs add <dir>` | 注册额外挂载目录，后续 `cs live` 自动附加 |
| `cs list` | 查看已注册的额外挂载目录 |
| `cs remove <dir>` | 删除已注册的额外挂载目录 |
| `cs where` | 显示当前 live session 在远端的主挂载目录与额外挂载目录 |
| `cs status` | 查看当前 client profile 与本地 live session |
| `cs status --json` | 以 JSON 输出当前 client profile、active session 与挂载路径 |
| `cs stop` | 停止当前 live session，并尝试远端卸载 |
| `tunnel ...` | 底层高级命令面，主要用于调试和开发，不推荐普通用户直接使用 |

每个命令加 `--help` 可以看所有选项。

## 高级与调试：底层 tunnel 命令

这组命令仍然保留，但现在更推荐直接用：

```bash
claude-share client init <user@host>
cs live
```

下面的 `tunnel ...` 更适合：

- 调试
- 排障
- 开发 claude-share 本身
- 验证底层 SSH / 挂载行为

如果你只是日常使用，请优先记住这三条：

```bash
sudo claude-share server init
claude-share client init <user@host>
cs live
```

### 前提条件

- **本地机器**：需要 OpenSSH client + server，并且 SSH 登录后能找到 Bash 兼容 shell。
  macOS/Linux 最直接；Windows 需要 OpenSSH Server，并建议配 Git Bash 或 MSYS2。
- **服务器**：Linux，且可用 `sshfs` + FUSE。
- 两端都应安装 `claude-share`。

### 最小示例

本地：

```bash
claude-share tunnel serve \
  --workspace /绝对路径/你的项目 \
  --server user@example.com
```

远端：

```bash
claude-share tunnel mount --session project-20260418-120000
source ~/.claude-share/remote/project-20260418-120000/env.sh
cd ~/.claude-share/mounts/project-20260418-120000
claude
```

辅助命令：

```bash
claude-share tunnel status --session project-20260418-120000
claude-share tunnel umount --session project-20260418-120000
```

这就是底层命令面的完整最小流程。如果你不是在调试传输层、挂载层或开发
claude-share 本身，优先使用：

```bash
claude-share client init <user@host>
cs live
```

### 当前限制

- 服务器侧目前只支持 Linux。
- 每个会话只发布**一个工作区目录树**。
- 命令代理覆盖常见开发命令，不是任意二进制都自动代理。
- `tunnel serve` 退出后，反向隧道会关闭，同时本地 `authorized_keys` 里的临时 key 会被移除。

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
