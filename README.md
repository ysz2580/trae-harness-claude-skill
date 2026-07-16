# trae-harness-claude

> TRAE Skill —— 语音远程控制电脑时，让 TRAE 当 Claude Code 的「传话筒」。
>
> ⚠️ **仅支持 Windows + PowerShell**。macOS / Linux 暂不支持（命令为 PowerShell 语法）。

## 这是什么

当你用语音远程操控电脑时，说出 **「CC：xxx」** / **「用 Claude：xxx」** / **「cc，xxx」**，TRAE 不会自己处理任务，而是把 prompt 拼好、调用 Claude Code（CC）执行、再把 CC 的输出**原样**回传给你。

- **TRAE 的角色**：纯传话筒——拼接 prompt → 调用 CC → 原样返回输出。不加工、不验收、不给第二意见、不做越界检查。
- **不带触发词**的任务（如「帮我写个快排」）走 TRAE 正常流程，**不**调用 CC。

项目本身不含业务逻辑代码，只是一个技能定义包 + 一个调用器脚本，通过 `.trae/skills/claude-harness/` 目录向 TRAE 注入「如何做传话筒」的知识。

## 目录结构

```
.trae/skills/claude-harness/
├── SKILL.md                          # 技能主文件（角色定位、触发条件、执行流程）
├── config.json                       # 配置文件（可选：仅在 claude 不在 PATH 时需要改）
└── resources/
    ├── claude-harness.cmd            # ★ 调用入口：.cmd 不受 PowerShell 执行策略限制，内部绕过策略调 .ps1
    ├── claude-harness.ps1            # 调用器实现：自动探测 claude 路径、组装参数、调用 CC
    └── claude-invocation.md          # 调用参考（命令模板、转义、文件验证，按需读取）
```

## 前置依赖

1. **Windows + PowerShell**（技能命令按 PowerShell 语法编写）。
2. **TRAE**：已安装 TRAE IDE 或 TRAE CLI（本技能运行在 TRAE 里）。
3. **Claude Code CLI 已安装并登录**：在终端执行 `claude` 能正常进入对话即算就绪。未安装见官方文档 https://docs.claude.com/en/docs/claude-code 。安装方式不限——只要 `claude` 在 PATH 上，技能会自动识别；不在 PATH 也行，见下方「配置（可选）」。

## 安装

### 1. 获取技能

```powershell
git clone https://github.com/ysz2580/trae-harness-claude-skill.git
```

或在本仓库页面点 **Code → Download ZIP**，解压即可。

### 2. 装到 TRAE（两种方式任选其一）

**方式 A：项目级技能**（仅在该项目目录下生效）

用 TRAE IDE 打开 clone 下来的仓库根目录（`trae-harness-claude-skill`，内含 `.trae/`），或 TRAE CLI `cd` 到该目录。执行 `/skills` 应能看到 `claude-harness`。

**方式 B：全局技能**（所有项目都能用）

把仓库里的 `.trae/skills/claude-harness/` **整个目录**复制到 `%userprofile%\.trae-cn\skills\` 下。最终结构应为：

```
%userprofile%\.trae-cn\skills\claude-harness\SKILL.md
%userprofile%\.trae-cn\skills\claude-harness\config.json
%userprofile%\.trae-cn\skills\claude-harness\resources\...
```

## 配置（通常无需配置）

**大多数用户下载后零配置即可使用**——技能内置的 `resources/claude-harness.ps1` 会按以下顺序自动探测 `claude`：

1. `config.json` 的 `claude_path`（手动覆盖，可选）
2. PATH 上的 `claude`（`Get-Command`，**最常见**——npm 全局安装或原生安装器加 PATH 的都走这条）
3. 常见安装位置兜底（`~/.claude/local/claude.exe`、`%APPDATA%/npm/claude.cmd` 等）

→ 只要你的终端能直接敲 `claude` 跑起来，就不用改任何东西。

### 仅当 claude 不在 PATH 时才需改 config.json

打开 [.trae/skills/claude-harness/config.json](.trae/skills/claude-harness/config.json)，把 `claude_path` 填上：

```json
{
  "_comment": "所有字段可选。claude 不在 PATH 时才需填 claude_path。",
  "claude_path": "",
  "extra_args": "--dangerously-skip-permissions"
}
```

| 字段 | 含义 | 默认 |
|---|---|---|
| `claude_path` | `claude.exe` 绝对路径，仅当 claude 不在 PATH 时才填 | 留空走探测 |
| `extra_args` | 调用 CC 追加的参数 | `--dangerously-skip-permissions` |

**路径写法**（JSON 注意点）：

- 推荐用**正斜杠 `/`**，省事且 PowerShell 也认：`C:/Users/xxx/.../claude.exe`
- 若用反斜杠 `\`，JSON 里必须写成双反斜杠 `\\`：`C:\\Users\\xxx\\...\\claude.exe`

不知道 `claude.exe` 在哪？在能跑 `claude` 的终端里执行 `Get-Command claude`，返回的 `Source` 就是完整路径；若通过 npm 全局安装，`npm root -g` 给出 node_modules 路径，`claude.exe` 通常在其下的 `@anthropic-ai\claude-code\bin\` 里。

找不到时技能会输出明确指引，不会跑到一半才失败。

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

## 验证安装

1. 在 TRAE 中执行 `/skills`，确认 `claude-harness` 出现。
2. 输入 `CC：你好` —— 应触发技能，调用 CC 并原样返回（这一步建立了 CC 上下文）。
3. 输入 `帮我写个快排`（不带触发词）—— 应走 TRAE 正常流程，**不**调用 CC。
4. 紧接**第 2 步**输入 `CC：再介绍一下你自己` —— 应使用 `-c` 追问模式（复用第 2 步的 CC 上下文）。

若第 2 步报「未找到 claude 可执行文件」，说明 claude 不在 PATH——按上方「配置」填 `claude_path`，或先把 `claude` 加入 PATH。

## 安全提示（请务必阅读）

本技能针对**语音远程控制**场景，有意采用了与一般最佳实践不同的策略：

- **固定使用 `--dangerously-skip-permissions`**：语音场景下无法交互确认权限，跳过是必需的，不是疏漏。
- **TRAE 不做越界检查**：CC 改了哪些文件、执行了什么命令，由用户自己负责，TRAE 只传话。
- **不使用 `--allowedTools` 白名单**：避免阻碍远程操控。

**因此用户需自行承担的风险**：

- CC 可能修改或删除任意文件（因跳过权限确认）。
- CC 可能执行任意命令（包括破坏性命令）。
- **强烈建议**在工作目录用 Git 管理版本，便于出问题时回滚。

## 更多细节

- 技能完整定义：[SKILL.md](.trae/skills/claude-harness/SKILL.md)
- 命令模板、PowerShell 转义、文件验证、`computer://` 链接格式：[resources/claude-invocation.md](.trae/skills/claude-harness/resources/claude-invocation.md)
- 面向 agent 的项目说明：[AGENTS.md](AGENTS.md)
