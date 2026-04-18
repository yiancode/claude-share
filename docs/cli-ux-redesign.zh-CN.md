# claude-share 三步式命令体验重构方案（已落地同步版）

## 文档状态

这份文档最初是 CLI 重构设计稿；当前已经根据仓库里的真实实现同步更新。

阅读方式：

- **已落地**：仓库里已经实现并可用的命令与行为
- **当前边界**：仍保留为后续优化空间的部分

---

## 目标

把偏底层的 `bootstrap / serve / mount / status / umount` 使用方式，收敛成面向最终用户的三步式体验：

1. **服务器初始化一次**
2. **本地初始化一次**
3. **以后每次只在本地当前目录执行一条命令**

核心目标：

- 默认围绕“**当前目录**”工作
- 命令要**短、好记、统一**
- 默认流程尽量不暴露底层概念
- 额外挂载目录单独补充，不影响主流程

---

## 命令统一原则

不再使用多套短别名，例如：

- `csl`
- `csa`
- `css`

统一为**一个短入口**：

```bash
cs
```

所有常用操作都走：

```bash
cs <subcommand>
```

这样用户只需要记住一个词：`cs`

---

## 已落地命令模型

### 1) 服务器初始化

在 Linux 服务器上执行一次：

```bash
sudo claude-share server init
```

当前已落地为：

- `claude-share server init`
- `claude-share server add-user`
- `claude-share server remove-user`
- `claude-share server status`
- `claude-share server sync`
- `claude-share server uninstall`

说明：

- 这是对原来 `init / add-user / remove-user / status / sync / uninstall` 的表层重组
- 底层仍复用原有多用户共享认证实现

---

### 2) 本地初始化

在本地 Mac/Linux 上执行一次：

```bash
claude-share client init st@43.162.99.88
```

当前已落地为：

- `claude-share client init <user@host>`
- `claude-share client status`

说明：

- `client init` 内部复用 `tunnel bootstrap`
- 会保存本地 profile 到：

```bash
~/.claude-share/client/profile.env
```

profile 当前会记录：

- 默认服务器
- identity file
- local prefix
- remote prefix

---

### 3) 日常使用

进入本地项目目录后，只执行：

```bash
cs live
```

当前已落地为：

- `cs live`
- `cs add <dir>`
- `cs list`
- `cs remove <dir>`
- `cs where`
- `cs status`
- `cs status --json`
- `cs stop`

实际 `cs live` 现有行为：

1. 读取当前目录
2. 读取本地保存的 client profile
3. 自动选择远端空闲端口
4. 启动主工作区 live session
5. 自动在远端挂载主目录
6. 读取 `cs add` 注册的额外目录
7. 为每个额外目录自动建立独立 session 并挂载
8. 在本地先打印一段清晰的挂载摘要
9. ssh 进入远端并启动 `claude`

用户心智模型已经收敛到：

```bash
cd /my/project
cs live
```

而不是：

```bash
tunnel bootstrap
tunnel serve
ssh 到服务器
tunnel mount
source env
cd mountpoint
claude
```

---

## 额外挂载目录设计

当前已落地：

- `cs add <dir>`：注册额外挂载目录
- `cs list`：查看注册表
- `cs remove <dir>`：删除注册表项

实现方式：

- 本地注册表保存在：

```bash
~/.claude-share/client/extra-mounts.txt
```

- `cs live` 启动时会自动读取该文件
- 主目录仍然是当前目录
- 额外挂载目录会被挂到远端独立路径下，而不是混进主项目目录

当前远端路径规则：

- 主目录：

```bash
~/.claude-share/mounts/<session>
```

- 额外目录：

```bash
~/.claude-share/extras/<main-session>/<index>-<slug>
```

设计原则仍保持不变：

- `cs live` 永远以“当前目录”为主挂载目录
- `cs add` 只处理附加白名单目录
- 不允许默认把整个 `$HOME` 暴露给服务器

---

## 挂载路径可见性

当前已落地：

- `cs live` 在真正进入远端 `claude` 前，会先打印本次会话的挂载摘要
- `cs where` 可以单独查看当前会话的远端挂载路径
- `cs status` 会直接显示当前 active session 的挂载摘要
- `cs status --json` 输出机器可读 JSON

示例：

```bash
cs where
```

输出示意：

```text
[claude-share] Live mount paths
  session          myproj-20260419-001500
  main             /home/st/.claude-share/mounts/myproj-20260419-001500 <= /Users/me/work/myproj
  extra            /home/st/.claude-share/extras/myproj-20260419-001500/1-data <= /Users/me/data
```

---

## 停止与回收

当前已落地为：

```bash
cs stop
```

职责：

- 远端卸载当前 live session
- 停止本地反向隧道
- 清理当前 session 状态

配套命令：

- `cs where`
- `cs status`
- `cs status --json`

---

## 对外命令清单

### 推荐暴露给用户的命令

```bash
claude-share server init
claude-share server add-user
claude-share server status

claude-share client init
claude-share client status

cs live
cs add
cs list
cs remove
cs where
cs status
cs stop
```

### 不推荐直接暴露给普通用户的底层命令

这些命令继续保留，但应视为内部实现面：

```bash
claude-share tunnel bootstrap
claude-share tunnel connect
claude-share tunnel serve
claude-share tunnel mount
claude-share tunnel umount
claude-share tunnel status
```

当前策略已落地为：

- README 主文档优先写三步式命令
- `tunnel *` 作为高级/底层命令保留
- 统一以 `cs` 作为唯一短命令入口

---

## 交互流程示例

### 首次部署

#### 服务器

```bash
sudo claude-share server init
sudo claude-share server add-user alice
sudo claude-share server add-user bob
```

#### 本地

```bash
claude-share client init st@43.162.99.88
```

### 日常开发

```bash
cd ~/work/my-project
cs live
```

如需额外目录：

```bash
cs add ~/work/shared-dataset
```

查看当前会话挂载位置：

```bash
cs where
```

查看当前状态：

```bash
cs status
cs status --json
```

结束：

```bash
cs stop
```

---

## 已落地与未落地

### 已落地

- `server / client / cs` 三层命令面
- `bin/cs`
- `client profile`
- `cs add / list / remove`
- `cs where`
- `cs status --json`
- `cs live` 的挂载摘要输出
- README 主文档切换到新体验

### 当前边界 / 尚未继续优化的点

- `cs live` 仍然内部依赖现有 `tunnel` 实现，不是全新 runtime
- `tunnel *` 仍然对外可见，尚未完全收口到内部面
- 额外挂载目录当前挂在远端独立 `extras/` 路径下，不会自动映射进主项目目录
- 远端自动进入 `claude` 的体验已经有欢迎摘要，但仍可继续优化交互文案

---

## 明确结论

当前项目已经实际采用：

```bash
cs
```

作为默认短命令入口。

当前推荐体验已经压缩为：

### 服务器一次

```bash
sudo claude-share server init
```

### 本地一次

```bash
claude-share client init st@43.162.99.88
```

### 日常一条

```bash
cs live
```

并已支持：

```bash
cs add
cs where
cs status
cs status --json
cs stop
```
