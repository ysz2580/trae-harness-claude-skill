# Claude Code 传话筒调用参考

本文档是 `claude-harness` 技能的参考资料。**仅在需要确认具体命令语法、PowerShell 转义、文件验证或 `computer://` 链接格式时才读取**，不必在技能加载时全量读入上下文。

## 环境信息

- **目标系统**：Windows + PowerShell
- **Claude Code 路径**：由 `resources\claude-harness.ps1` 自动探测，**不写死**。探测优先级：`config.json` 的 `claude_path` → PATH 上的 `claude`（`Get-Command`）→ 常见安装位置兜底。任一命中即可用。
- **额外参数**：`config.json` 的 `extra_args`（默认 `--dangerously-skip-permissions`）。
- **权限模式**：默认 `--dangerously-skip-permissions`（语音远程场景无法交互确认）。
- **工作目录来源**：系统提示中的终端 `cwd` 信息（如 `cwd is e:\claude_trae`）。同一会话内固定，不重复检测。
- **执行策略约束（重要）**：TRAE 的 RunCommand 每次都开新 PowerShell 进程，系统执行策略通常为 `Restricted`（禁止运行 `.ps1`）。因此**不能用 `& $s` 直接点源调用**，必须用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s …` 启动干净子进程跑脚本——`-NoProfile` 跳过 TRAE 注入的 profile-snapshot 消除 CLIXML 噪声，`-ExecutionPolicy Bypass` 仅对子进程生效、不改系统策略。

### 调用入口（经由脚本）

所有调用走 `claude-harness.ps1`，它负责探测路径、读 config、组装参数。agent 只需定位并用 `powershell.exe -File` 调用它。**定位 `$s` 与调用必须在同一条 RunCommand 里**（`$s` 是当前 shell 变量，跨进程丢失）：

```powershell
# 定位 claude-harness.ps1
$s = $null; $d = $PWD.Path
while ($d -and -not $s) {
  $p = Join-Path $d '.trae\skills\claude-harness\resources\claude-harness.ps1'
  if (Test-Path $p) { $s = $p }
  $n = Split-Path $d -Parent
  if (-not $n -or $n -eq $d) { break }; $d = $n
}
if (-not $s) {
  $g = Join-Path $env:USERPROFILE '.trae-cn\skills\claude-harness\resources\claude-harness.ps1'
  if (Test-Path $g) { $s = $g }
}
if (-not $s) { Write-Error '未找到 claude-harness.ps1'; exit 1 }
```

下文命令模板中 `$s` 即定位到的脚本，调用行统一为 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s …`。

## 命令模板

### 新话题

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt "完整prompt" -WorkingDirectory "{工作目录}"
```

### 追问（接续上下文）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt "完整prompt" -WorkingDirectory "{工作目录}" -Continue
```

`-Continue` 对应 `claude -c`，复用上一轮 CC 上下文。仅在用户对上一次结果做修改/补充/追问时使用；拿不准时默认不加。

> 必须用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s` 而非 `& $s`：TRAE RunCommand 每次新进程 + 系统策略 `Restricted`，`& $s` 会被拦截并触发 CLIXML 噪声。`-File` 后的参数原样传给脚本。

## RunCommand 调用参数

```
command:           $s = $null; $d = $PWD.Path; while ($d -and -not $s) { $p = Join-Path $d '.trae\skills\claude-harness\resources\claude-harness.ps1'; if (Test-Path $p) { $s = $p }; $n = Split-Path $d -Parent; if (-not $n -or $n -eq $d) { break }; $d = $n }; if (-not $s) { $g = Join-Path $env:USERPROFILE '.trae-cn\skills\claude-harness\resources\claude-harness.ps1'; if (Test-Path $g) { $s = $g } }; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt "完整prompt" -WorkingDirectory "{工作目录}"
cwd:               {工作目录}（从终端 cwd 获取，或用户指定目录）
blocking:          true   （语音场景同步等待结果）
requires_approval: false  （触发词已表明用户授权）
```

追问时把末尾调用行换成带 `-Continue` 的版本。`$s` 由上方定位代码取得，**定位与调用必须在同一 RunCommand**。

## Prompt 拼接规则

### 主体

用户原始任务，去掉触发词前缀（`CC：` / `用 Claude：` / `cc，` 及其英文变体）。

### 涉及文件生成时

prompt 中**必须**用绝对路径指定保存位置：

```
{用户任务}。保存到 {工作目录}\文件名.xxx
```

错误示例：「保存到当前目录下」—— CC 在 `-p` 模式下不一定知道当前 cwd。

### 涉及文件读取/分析时

若文件路径在对话上下文中已知，把绝对路径直接写入 prompt：

```
分析 {绝对路径}\xxx.py 这个文件
```

若用户在输入中明确指定了其他目录（如 `E:\data\main.py`），以用户指定为准，并把 `cwd` 也设为该目录。

### 末尾固定追加

```
工作目录为 {工作目录}，所有文件操作请在该目录下进行
```

## Prompt 传入与转义

prompt 经 `claude-harness.ps1` 的 `-Prompt` 参数传入，**作为变量传递**，因此天然避开 PowerShell 字符串边界的转义问题——含双引号、反斜杠路径的 prompt 直接写进字符串字面量即可。

### 普通 prompt

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt "写一个快速排序算法，保存到 E:\project\webapp\quicksort.py。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" -WorkingDirectory "E:\project\webapp"
```

### 含双引号/多行的 prompt

用双引号字符串里嵌双引号需 ```"``` 转义，或改用 Here-string 赋给变量再传：

```powershell
$prompt = @"
请按以下要求生成代码：
- 函数名 "sort_ascending"
- 输出到 "E:\project\webapp\sort.py"
工作目录为 E:\project\webapp，所有文件操作请在该目录下进行
"@
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt $prompt -WorkingDirectory "E:\project\webapp"
```

注意：Here-string 的结束 `"@` 必须在行首，不能有前置空格。`-Prompt $prompt` 同样以变量传递，避开转义。

### 反斜杠路径

PowerShell 双引号字符串中 `\` 不是转义符，路径原样写：`E:\project\webapp\file.py` 无需 `\\`。

## 文件位置验证（仅当涉及生成文件时）

### 检查文件是否在预期路径

```powershell
Test-Path "{工作目录}\文件名.xxx"
```

返回 `True` / `False`。

### 查找 CC 实际把文件写到了哪里

从 CC 输出中提取它提到的路径。若 CC 未明说，可用 `Get-ChildItem` 在工作目录及其上层目录搜索最近创建的文件：

```powershell
Get-ChildItem -Path {工作目录} -Filter "文件名.xxx" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime
```

### 文件不在预期目录时移动

```powershell
Move-Item "原路径\文件名.xxx" "{工作目录}\文件名.xxx" -Force
```

移动后告知用户：
- 原位置
- 新位置
- 文件大小（`(Get-Item "{工作目录}\文件名.xxx").Length`）

## computer:// 链接格式

生成文件后，向用户提供 `computer://` 链接方便直接打开。格式：

```
computer://文件绝对路径
```

示例：

```
computer://E:\project\webapp\quicksort.py
```

注意：
- 路径中的反斜杠保留原样，不需要 URL 编码。
- 链接指向**最终**位置（若发生过 Move-Item，用移动后的路径）。

## 完整调用示例

> 以下示例假设已跑过「调用入口」段的定位代码，`$s` 已就绪。

### 示例 1：新话题，生成文件

工作目录 `E:\project\webapp`，用户输入 `CC：帮我写个快排`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt "写一个快速排序算法，保存到 E:\project\webapp\quicksort.py。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" -WorkingDirectory "E:\project\webapp"
```

调用结束后：
1. `Test-Path "E:\project\webapp\quicksort.py"`
2. 若 False，搜索并 `Move-Item` 到工作目录
3. 原样返回 CC 输出
4. 1-2 句概括
5. 附 `computer://E:\project\webapp\quicksort.py`

### 示例 2：追问

紧接上例，用户输入 `CC：改成降序`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt "改成降序排列" -WorkingDirectory "E:\project\webapp" -Continue
```

不追加工作目录说明（CC 已有上下文）。无文件生成步骤。

### 示例 3：用户指定其他目录

用户输入 `CC：分析 E:\data\main.py`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s -Prompt "分析 E:\data\main.py 这个文件" -WorkingDirectory "E:\data"
```

工作目录 = `E:\data`（用户指定目录优先于会话默认工作目录）

## 异常处理

| 现象 | 处理 |
|---|---|
| `无法加载文件 …powershell-profile-snapshot.ps1，因为在此系统上禁止运行脚本` + `& 后面表达式生成无效的对象` | 执行策略 `Restricted` 拦截了 `.ps1`。确认调用方式是 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s …` 而非 `& $s`；若仍报错，让用户在终端执行一次 `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`（一次性、不需管理员）。 |
| `claude.exe` 不存在 / 命令未找到 | 脚本已自动探测 PATH、常见位置、config.json；三者都没找到时输出指引，告知用户「把 claude 加入 PATH，或在 config.json 的 claude_path 填入绝对路径」 |
| HTTP 401 / 未登录 | 告知用户 CC 认证失效，需在终端执行 `claude` 交互式登录 |
| CC 执行超时 | 语音场景下用户在等，超时后告知用户「CC 执行超时，请稍后重试或拆分任务」 |
| 文件未生成 | 告知用户 CC 未产出文件，原样返回 CC 输出供用户判断 |
| CC 返回错误信息 | 原样返回错误信息，并简要说明可能原因（不要替用户修复） |

**核心原则**：传话筒模式下，TRAE 不替用户决策、不自动重试、不静默修复——把信息原样传回，让用户自己判断下一步。
