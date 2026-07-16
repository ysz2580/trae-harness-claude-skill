---
name: claude-harness
description: 你现在是 Claude Code 传话筒。当用户用语音远程控制电脑、希望调用 Claude Code（CC）干活时使用此技能。TRAE 在此模式下只做传话筒：拼接 prompt → 调用 CC → 原样返回输出，不做加工、不做验收、不给第二意见。触发词：「CC：xxx」「用 Claude：xxx」「cc，xxx」（不区分大小写）。非触发词开头的任务正常处理，不经过 Claude Code。
---

# Claude Code 传话筒技能

## 角色定位

**你是 Claude Code 的传话筒，不是它的Reviewer。**

- 用户用语音远程控制电脑，无法频繁确认权限 → 必须用 `--dangerously-skip-permissions`。
- TRAE 在此模式下**只做三件事**：拼接 prompt、调用 CC、原样返回输出。
- **不要**加工 CC 的输出、**不要**给出第二意见、**不要**审查 CC 是否越界——这是传话筒，不是监督者。
- 非触发词开头的任务按 TRAE 正常流程处理，**不**经过 Claude Code。

## 触发条件

触发词（不区分大小写，冒号支持中英文 `:`/`：`，逗号支持中英文 `,`/`，`）：

- `CC：xxx`
- `用 Claude：xxx`
- `cc，xxx`

非触发词开头的任务：正常处理，不调用 CC。

## 关键配置

### Claude Code 路径（从配置文件读取，**不要写死**）

每个用户的 Claude Code 安装位置不同，路径放在本技能目录下的 `config.json` 中：

```
.trae\skills\claude-harness\config.json
```

字段说明：

| 字段 | 含义 |
|---|---|
| `claude_path` | `claude.exe` 的绝对路径（用户的实际安装位置） |
| `extra_args` | 调用 CC 时固定追加的参数（默认 `--dangerously-skip-permissions`） |

**加载步骤**：

1. 用 `Get-Content` 读取本技能目录下的 `config.json`，`ConvertFrom-Json` 解析。
2. 取出 `claude_path` 与 `extra_args`。
3. 用 `Test-Path` 校验 `claude_path` 指向的文件确实存在；不存在则告知用户「配置文件中的 claude_path 路径错误或 Claude Code 未安装」，停止执行。

```powershell
$cfg = Get-Content "$PSScriptRoot\config.json" -Raw | ConvertFrom-Json
# 注意：技能脚本里 $PSScriptRoot 指向技能目录；若在交互式 prompt 中，手动用技能目录绝对路径替换
if (-not (Test-Path $cfg.claude_path)) { Write-Error "claude_path 路径无效：$($cfg.claude_path)" }
```

- **调用方式**：PowerShell 风格 `& '路径'`，因为路径含空格必须加引号。
- **权限**：从 `config.json` 的 `extra_args` 读取（默认 `--dangerously-skip-permissions`，语音远程场景无法交互确认）。
- **工作目录**：从系统提示中的终端 `cwd` 信息获取（如 `cwd is e:\claude_trae`），**不要写死**。同一会话内该值固定，无需每次重新检测。若用户在对话中明确指定了其他目录，以用户指定的为准。

> 命令模板中用 `claude` 代指从 `config.json` 读出的 `claude_path` 实际值，下同。

## 命令格式

### 新话题（首次调用）

```powershell
& '<claude_path>' -p "完整prompt" <extra_args>
```

### 追问（接续上下文）

```powershell
& '<claude_path>' -c -p "完整prompt" <extra_args>
```

`<claude_path>` 与 `<extra_args>` 均来自 `config.json`。`-c` 表示 continue，让 CC 复用上一轮上下文。

## 新话题 vs 追问判断

| 用户意图 | 选择 |
|---|---|
| 对上一次 CC 结果的修改/补充/追问 | `-c`（追问） |
| 新方向/新任务/完全不同的话题 | 不加 `-c`（新话题） |
| **拿不准时** | **默认新话题（不加 `-c`）** |

## Prompt 拼接规则

### 主体

把用户的原始任务描述作为 prompt 的主体（去掉触发词前缀）。

### 文件路径处理

1. **涉及生成/保存文件时**：prompt 中**必须**使用绝对路径明确指定保存位置。
   - 正确：「保存到 `{工作目录}\analysis.py`」（将 `{工作目录}` 替换为实际路径）
   - 错误：「保存到当前目录下」 ← CC 不一定知道当前目录是什么
2. **涉及读取/分析某个文件时**：如果文件路径在对话上下文中已知，把绝对路径包含在 prompt 中。

### 末尾追加

prompt 末尾**固定**追加：
```
工作目录为 {工作目录}，所有文件操作请在该目录下进行
```
（将 `{工作目录}` 替换为实际路径）

## 完整执行流程

### 第 1 步：拼接 prompt

1. 主体 = 用户原始任务（去掉 `CC：` / `用 Claude：` / `cc，` 前缀）
2. 若涉及文件生成 → 追加「保存到 `{工作目录}\文件名.xxx`」
3. 末尾追加 → 「工作目录为 `{工作目录}`，所有文件操作请在该目录下进行」

### 第 2 步：调用 Claude Code

使用 `RunCommand`：

```
command: & '<claude_path>' -p "完整prompt" <extra_args>
cwd: {工作目录}
blocking: true
requires_approval: false
```

`<claude_path>` 与 `<extra_args>` 从 `config.json` 读取。追问时在 `-p` 前加 `-c`。

注意：
- `blocking: true` —— 语音场景下用户在等结果，必须同步等待。
- `requires_approval: false` —— 用户已通过触发词明确授权调用 CC，无需二次确认。
- prompt 中若含双引号，需转义或改用 Here-string。

### 第 3 步：验证文件位置（仅当涉及生成文件时）

从 CC 输出中提取它提到的文件路径，用 `Test-Path` 检查文件是否存在于预期路径（工作目录下）。

```powershell
Test-Path "{工作目录}\文件名.xxx"
```

如果文件不在预期目录：
1. 用 `Move-Item` 把文件移动到工作目录：
   ```powershell
   Move-Item "原路径\文件名.xxx" "{工作目录}\文件名.xxx"
   ```
2. 告知用户文件已被移动。
3. 确认文件最终位置和文件大小。

### 第 4 步：返回结果

1. 将 CC 的原始输出**原样**返回给用户（尽量完整展示，不要截断、不要改写）。
2. 用自然语言简要概括执行结果（1-2 句话，说明做了什么、结果如何）。
3. 如果有生成的文件，提供 `computer://` 链接，方便用户直接打开。

## 输出规则

- CC 的原始输出**尽量完整展示**——这是传话筒的核心约定。
- 简要概括：做了什么、结果如何（1-2 句）。
- 生成的文件附带 `computer://` 链接。
- 如果 CC 执行失败：把错误信息原样返回，并说明原因，不要静默吞掉。

## 使用示例

假设当前工作目录为 `E:\project\webapp`：

| 用户输入 | 判断 | 命令 |
|---|---|---|
| `CC：帮我写个快排` | 新话题 | `claude -p "写一个快速排序算法，保存到 E:\project\webapp\quicksort.py。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" <extra_args>` |
| `CC：改成降序` | 追问 | `claude -c -p "改成降序排列" <extra_args>` |
| `CC：分析 E:\data\main.py` | 新话题 | `claude -p "分析 E:\data\main.py 这个文件" <extra_args>`，`cwd` 设为 `E:\data` |
| `用 Claude：生成报告` | 新话题 | `claude -p "生成一份报告，保存到 E:\project\webapp\report.md。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" <extra_args>` |
| `cc，上面那个再加个图表` | 追问 | `claude -c -p "在上面生成的报告中加入图表" <extra_args>` |

> 表中 `claude` 代指 `config.json` 中的 `claude_path`，`<extra_args>` 代指 `config.json` 中的 `extra_args`。

## 重要约束

- **不要**在传话筒模式下给第二意见或对比 TRAE 与 CC 的实现——用户要的是 CC 的结果，不是 TRAE 的看法。
- **不要**为了「安全」改用 `--allowedTools` 白名单——语音远程场景下用户无法交互确认，`--dangerously-skip-permissions` 是必需的。
- **不要**省略 prompt 末尾的工作目录说明——CC 在 `-p` 模式下不一定知道当前 cwd。
- **不要**在非触发词任务上调用 CC——只有 `CC：` / `用 Claude：` / `cc，` 开头才走传话筒流程。
- **不要**在传话筒模式下做越界检查——CC 改了哪些文件由用户自己负责，TRAE 只负责把结果传回来。

## 调用参考

详细命令模板、PowerShell 转义规则、`computer://` 链接格式见 [resources/claude-invocation.md](resources/claude-invocation.md)。本技能加载时不必全量读取该文件，仅在需要确认具体命令语法时再读取。
