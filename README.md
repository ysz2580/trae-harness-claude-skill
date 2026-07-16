# trae-harness-claude

> TRAE Skill —— 语音远程控制电脑时，让 TRAE 当 Claude Code 的「传话筒」。

## 这是什么

当你用语音远程操控电脑时，说出 **「CC：xxx」** / **「用 Claude：xxx」** / **「cc，xxx」**，TRAE 不会自己处理任务，而是把 prompt 拼好、调用 Claude Code（CC）执行、再把 CC 的输出**原样**回传给你。

- **TRAE 的角色**：纯传话筒——拼接 prompt → 调用 CC → 原样返回输出。不加工、不验收、不给第二意见、不做越界检查。
- **不带触发词**的任务（如「帮我写个快排」）走 TRAE 正常流程，**不**调用 CC。

项目本身不含可执行代码，只是一个技能定义包，通过 `.trae/skills/claude-harness/` 目录向 TRAE 注入「如何做传话筒」的知识。

## 目录结构

```
.trae/skills/claude-harness/
├── SKILL.md                          # 技能主文件（角色定位、触发条件、执行流程）
├── config.json                       # ★ 配置文件：claude.exe 路径与调用参数
└── resources/
    └── claude-invocation.md          # 调用参考（命令模板、转义、文件验证，按需读取）
```

## 前置依赖

1. **Windows + PowerShell**（技能命令按 PowerShell 语法编写）。
2. **已安装 Claude Code CLI** 并完成登录认证（终端能跑 `claude` 并正常响应）。

## 安装

### 作为项目级技能（仅在本项目目录生效）

直接在本项目目录下用 TRAE IDE 打开，或 TRAE CLI `cd` 到本项目即可。执行 `/skills` 应能看到 `claude-harness`。

### 作为全局技能（所有项目都能用）

把 `.trae/skills/claude-harness/` **整个目录**复制到：

- **Windows**：`%userprofile%\.trae-cn\skills\`
- **macOS / Linux**：`~/.trae-cn/skills/`

## 配置（重要）

每个用户的 Claude Code 安装位置不同，路径**不写死在文档里**，统一放在 [config.json](.trae/skills/claude-harness/config.json)：

```json
{
  "claude_path": "C:/Users/你的用户名/.npm-global/node_modules/@anthropic-ai/claude-code/bin/claude.exe",
  "extra_args": "--dangerously-skip-permissions"
}
```

| 字段 | 含义 |
|---|---|
| `claude_path` | `claude.exe` 的绝对路径，改成你机器上的实际位置 |
| `extra_args` | 调用 CC 时固定追加的参数，默认 `--dangerously-skip-permissions` |

**路径写法**（JSON 注意点）：

- 推荐用**正斜杠 `/`**，省事且 PowerShell 也认：`C:/Users/xxx/.../claude.exe`
- 若用反斜杠 `\`，JSON 里必须写成双反斜杠 `\\`：`C:\\Users\\xxx\\...\\claude.exe`

不知道 `claude.exe` 在哪？在能跑 `claude` 的终端里执行：

```powershell
# 若是通过 npm 全局安装
npm root -g                          # 拿到全局 node_modules 路径
# 通常是 <上面那个路径>\@anthropic-ai\claude-code\bin\claude.exe
```

技能加载时会用 `Test-Path` 校验路径，无效会报错停止，不会跑到一半才失败。

## 使用方法

打开 TRAE，直接说话/输入即可：

| 输入 | 行为 |
|---|---|
| `CC：帮我写个快排` | 新话题，调用 CC，生成文件并附 `computer://` 链接 |
| `CC：改成降序` | 追问（`-c` 复用上一轮上下文） |
| `CC：分析 E:\data\main.py` | 新话题，`cwd` 设为 `E:\data` |
| `用 Claude：生成报告` | 新话题 |
| `cc，上面那个再加个图表` | 追问 |
| `帮我写个快排`（无触发词） | 走 TRAE 正常流程，不调用 CC |

触发词不区分大小写，冒号/逗号支持中英文（`:`/`：`、`,`/`，`）。

**新话题 vs 追问**：对上一次结果做修改/补充/追问 → 追问（`-c`）；新方向/新任务 → 新话题；拿不准 → 默认新话题。

## 安全提示（请务必阅读）

本技能针对**语音远程控制**场景，有意采用了与一般最佳实践不同的策略：

- **固定使用 `--dangerously-skip-permissions`**：语音场景下无法交互确认权限，跳过是必需的，不是疏漏。
- **TRAE 不做越界检查**：CC 改了哪些文件、执行了什么命令，由用户自己负责，TRAE 只传话。
- **不使用 `--allowedTools` 白名单**：避免阻碍远程操控。

**因此用户需自行承担的风险**：

- CC 可能修改或删除任意文件（因跳过权限确认）。
- CC 可能执行任意命令（包括破坏性命令）。
- **强烈建议**在工作目录用 Git 管理版本，便于出问题时回滚。

## 验证安装

1. 在 TRAE 中执行 `/skills`，确认 `claude-harness` 出现。
2. 输入 `CC：你好` —— 应触发技能，调用 CC 并原样返回。
3. 输入 `帮我写个快排`（不带触发词）—— 应走 TRAE 正常流程，**不**调用 CC。
4. 紧接上一步输入 `CC：改成降序` —— 应使用 `-c` 追问模式。

## 更多细节

- 技能完整定义：[SKILL.md](.trae/skills/claude-harness/SKILL.md)
- 命令模板、PowerShell 转义、文件验证、`computer://` 链接格式：[resources/claude-invocation.md](.trae/skills/claude-harness/resources/claude-invocation.md)
- 面向 agent 的项目说明：[AGENTS.md](AGENTS.md)
