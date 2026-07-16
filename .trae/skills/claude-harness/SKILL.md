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

### 通过调用器脚本调用 CC（**不要手写 claude 路径**）

所有调用 CC 的命令都经由本技能目录下的 `resources\claude-harness.ps1` 完成。该脚本自动探测 claude 可执行文件，agent 只需调用它——**不要在 SKILL.md 或 prompt 里写死 claude 路径**。

> 为什么走脚本：agent 在交互式命令里执行，`$PSScriptRoot` 等脚本变量为空，无法定位技能目录；把探测逻辑集中到一个 .ps1 里，既解决路径定位，又让陌生用户下载后零配置可用。

**探测优先级**（脚本内部逐级回退，任一命中即可用）：

1. `config.json` 的 `claude_path`（用户手动覆盖，最高优先级）
2. PATH 上的 `claude`（`Get-Command`，最常见——npm 全局安装 / 原生安装器加 PATH 都走这条）
3. 常见安装位置兜底清单

→ **90% 用户下载后无需改任何配置即可用**；`config.json` 仅在 claude 不在 PATH 时才需要改。

### config.json（可选覆盖）

位于 `.trae\skills\claude-harness\config.json`，**全部字段可选**：

| 字段 | 含义 | 默认 |
|---|---|---|
| `claude_path` | `claude.exe` 绝对路径，仅当 claude 不在 PATH 时需要填 | 留空则走探测 |
| `extra_args` | 调用 CC 追加的参数 | `--dangerously-skip-permissions` |

### 工作目录

从系统提示中的终端 `cwd` 信息获取（如 `cwd is e:\claude_trae`），**不要写死**。同一会话内固定，无需重新检测。若用户在对话中指定了其他目录，以用户指定为准。

## 命令格式

### 定位 + 调用（必须在同一条命令里）

调用入口是 `resources\claude-harness.cmd`（**不是 `.ps1`**）。`.cmd` 走 cmd.exe，**不受 PowerShell 执行策略限制**——这是关键：系统默认 `Restricted` 会拦截 `.ps1`，agent 若直接 `&` 一个 `.ps1` 会失败（实测第一次调用必踩）。`.cmd` 内部固定用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File …` 调 `.ps1`，绕过策略、跳过 TRAE profile-snapshot、消除 CLIXML 噪声。agent 只需自然的 `& $s`，**无需记住加 `-ExecutionPolicy Bypass`**。

完整模板（定位 `.cmd` + 调用合一，**同一 RunCommand**）：

```powershell
$s = $null; $d = $PWD.Path
while ($d -and -not $s) {
  $p = Join-Path $d '.trae\skills\claude-harness\resources\claude-harness.cmd'
  if (Test-Path $p) { $s = $p }
  $n = Split-Path $d -Parent
  if (-not $n -or $n -eq $d) { break }; $d = $n
}
if (-not $s) {
  $g = Join-Path $env:USERPROFILE '.trae-cn\skills\claude-harness\resources\claude-harness.cmd'
  if (Test-Path $g) { $s = $g }
}
if (-not $s) { Write-Error '未找到 claude-harness.cmd'; exit 1 }

# ↓ 新话题（首次调用）
& $s -Prompt "完整prompt" -WorkingDirectory "{工作目录}"
# ↓ 追问（接续上下文）：把上一行换成
# & $s -Prompt "完整prompt" -WorkingDirectory "{工作目录}" -Continue
```

`-Continue` 对应 `claude -c`，复用上一轮上下文。`-WorkingDirectory` 可省略（省略则用当前目录）。

> prompt 作为参数传给 `.cmd` 再透传给 `.ps1`，**避开 PowerShell 引号转义地狱**——含双引号、反斜杠路径的 prompt 直接写字面量即可。
>
> **兜底**：若 prompt 含 cmd 元字符（`&` `|` `<` `>` `^`）导致 `.cmd` 的 `%*` 透传出错，改用显式形式直接调 `.ps1`：
> ```powershell
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PWD '.trae\skills\claude-harness\resources\claude-harness.ps1') -Prompt "完整prompt" -WorkingDirectory "{工作目录}"
> ```
> （全局装则路径取 `$env:USERPROFILE\.trae-cn\skills\claude-harness\resources\claude-harness.ps1`）

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

先定位调用器脚本（见「命令格式」段的定位代码，得到 `$s`），再调用：

使用 `RunCommand`（定位 `$s` 与调用必须在同一条命令里，`$s` 指向 `claude-harness.cmd`）：

```
command: $s = $null; $d = $PWD.Path; while ($d -and -not $s) { $p = Join-Path $d '.trae\skills\claude-harness\resources\claude-harness.cmd'; if (Test-Path $p) { $s = $p }; $n = Split-Path $d -Parent; if (-not $n -or $n -eq $d) { break }; $d = $n }; if (-not $s) { $g = Join-Path $env:USERPROFILE '.trae-cn\skills\claude-harness\resources\claude-harness.cmd'; if (Test-Path $g) { $s = $g } }; & $s -Prompt "完整prompt" -WorkingDirectory "{工作目录}"
cwd:      {工作目录}
blocking: true
requires_approval: false
```

追问时把末尾 `& $s -Prompt "…" -WorkingDirectory "…"` 换成带 `-Continue` 的版本。路径探测、`config.json` 读取、参数组装都在 `claude-harness.ps1` 内完成，`.cmd` 只负责以绕过执行策略的方式启动它。

注意：
- `blocking: true` —— 语音场景下用户在等结果，必须同步等待。
- `requires_approval: false` —— 用户已通过触发词明确授权调用 CC，无需二次确认。
- 调 `claude-harness.cmd`（`& $s`），**不要**直接调 `.ps1`——`.ps1` 会被系统 `Restricted` 执行策略拦截（实测第一次必失败）；`.cmd` 走 cmd.exe 不受此限制，且内部已带 `-NoProfile -ExecutionPolicy Bypass`。
- prompt 经 `-Prompt` 参数传入，含双引号/反斜杠路径也无需转义。

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

假设当前工作目录为 `E:\project\webapp`，`$s` 已定位到 `claude-harness.cmd`（实际命令中定位与调用合并在一条 RunCommand 里，见「命令格式」段）：

| 用户输入 | 判断 | 命令（省略定位代码，仅展示调用行） |
|---|---|---|
| `CC：帮我写个快排` | 新话题 | `& $s -Prompt "写一个快速排序算法，保存到 E:\project\webapp\quicksort.py。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" -WorkingDirectory "E:\project\webapp"` |
| `CC：改成降序` | 追问 | `& $s -Prompt "改成降序排列" -WorkingDirectory "E:\project\webapp" -Continue` |
| `CC：分析 E:\data\main.py` | 新话题 | `& $s -Prompt "分析 E:\data\main.py 这个文件" -WorkingDirectory "E:\data"` |
| `用 Claude：生成报告` | 新话题 | `& $s -Prompt "生成一份报告，保存到 E:\project\webapp\report.md。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" -WorkingDirectory "E:\project\webapp"` |
| `cc，上面那个再加个图表` | 追问 | `& $s -Prompt "在上面生成的报告中加入图表" -WorkingDirectory "E:\project\webapp" -Continue` |

> 每条命令前都需先跑「命令格式」段里的定位代码得到 `$s`（指向 `.cmd`），**且定位与调用在同一 RunCommand**。`$s` 未就绪时兜底会输出 `未找到 claude-harness.cmd`。prompt 含 cmd 元字符时见「命令格式」段兜底写法（显式调 `.ps1`）。

## 重要约束

- **不要**在传话筒模式下给第二意见或对比 TRAE 与 CC 的实现——用户要的是 CC 的结果，不是 TRAE 的看法。
- **不要**手写 claude 路径或 `<claude_path>`——一律经由 `claude-harness.ps1` 调用，路径由脚本自动探测。
- **不要**用 `& $s` 直接点源调用 **`.ps1`**——会被系统 `Restricted` 执行策略拦截（实测第一次必失败）。调用入口是 `claude-harness.cmd`（`& $s` 指向 `.cmd`），`.cmd` 走 cmd.exe 不受策略限制，内部已带 `-NoProfile -ExecutionPolicy Bypass`。定位器找的是 `.cmd`，不是 `.ps1`。
- **不要**为了「安全」擅自改用 `--allowedTools` 白名单——默认 `--dangerously-skip-permissions` 是语音远程场景的必需项；如确需限制，由用户在 `config.json` 的 `extra_args` 覆盖，agent 不应自作主张。
- **不要**省略 prompt 末尾的工作目录说明——CC 在 `-p` 模式下不一定知道当前 cwd。
- **不要**在非触发词任务上调用 CC——只有 `CC：` / `用 Claude：` / `cc，` 开头才走传话筒流程。
- **不要**在传话筒模式下做越界检查——CC 改了哪些文件由用户自己负责，TRAE 只负责把结果传回来。

## 调用参考

详细命令模板、PowerShell 转义规则、`computer://` 链接格式见 [resources/claude-invocation.md](resources/claude-invocation.md)。本技能加载时不必全量读取该文件，仅在需要确认具体命令语法时再读取。
