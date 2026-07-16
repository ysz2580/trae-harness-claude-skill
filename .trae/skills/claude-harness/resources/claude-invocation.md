# Claude Code 传话筒调用参考

本文档是 `claude-harness` 技能的参考资料。**仅在需要确认具体命令语法、PowerShell 转义、文件验证或 `computer://` 链接格式时才读取**，不必在技能加载时全量读入上下文。

## 环境信息

- **目标系统**：Windows + PowerShell
- **Claude Code 路径**：从本技能目录下的 `config.json` 读取（字段 `claude_path`）。每个用户的安装位置不同，**不要写死**。加载时用 `Test-Path` 校验，不存在则报错并停止。
- **额外参数**：从 `config.json` 的 `extra_args` 字段读取（默认 `--dangerously-skip-permissions`）。
- **路径含空格**：必须用 `& '路径'` 形式调用（PowerShell 调用操作符）。
- **权限模式**：固定 `--dangerously-skip-permissions`（语音远程场景无法交互确认）。
- **工作目录来源**：系统提示中的终端 `cwd` 信息（如 `cwd is e:\claude_trae`）。同一会话内固定，不重复检测。

### 读取配置

```powershell
$cfg = Get-Content "<技能目录>\config.json" -Raw | ConvertFrom-Json
if (-not (Test-Path $cfg.claude_path)) {
  Write-Error "config.json 中 claude_path 无效：$($cfg.claude_path)"
}
# 之后用 & $cfg.claude_path ... $cfg.extra_args
```

下文命令模板中 `claude` 代指 `$cfg.claude_path`，`<extra_args>` 代指 `$cfg.extra_args`。

## 命令模板

### 新话题

```powershell
& $cfg.claude_path -p "完整prompt" $cfg.extra_args
```

### 追问（接续上下文）

```powershell
& $cfg.claude_path -c -p "完整prompt" $cfg.extra_args
```

`-c` / `--continue`：复用上一轮 CC 上下文。仅在用户对上一次结果做修改/补充/追问时使用；拿不准时默认不加 `-c`。

## RunCommand 调用参数

```
command:           见上方模板（追问时加 -c）
cwd:               {工作目录}（从终端 cwd 获取，或用户指定目录）
blocking:          true   （语音场景同步等待结果）
requires_approval: false  （触发词已表明用户授权）
```

`<extra_args>` 与 `claude` 均从 `config.json` 读取。

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

## PowerShell 引号与转义

prompt 中的双引号是 PowerShell 字符串边界。处理方式：

### 方式 1：prompt 中无双引号时

直接用双引号包裹：

```powershell
& $cfg.claude_path -p "写一个快速排序算法，保存到 E:\project\webapp\quicksort.py。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" $cfg.extra_args
```

### 方式 2：prompt 中含双引号时

改用 PowerShell Here-string `@" ... "@`，避免转义地狱：

```powershell
$prompt = @"
请按以下要求生成代码：
- 函数名 "sort_ascending"
- 输出到 "E:\project\webapp\sort.py"
工作目录为 E:\project\webapp，所有文件操作请在该目录下进行
"@
& $cfg.claude_path -p $prompt $cfg.extra_args
```

注意：Here-string 的结束 `"@` 必须在行首，不能有前置空格。

### 方式 3：prompt 中含反斜杠路径

PowerShell 双引号字符串中 `\` 不是转义符，路径可以原样写：`E:\project\webapp\file.py` 无需 `\\`。

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

### 示例 1：新话题，生成文件

工作目录 `E:\project\webapp`，用户输入 `CC：帮我写个快排`：

```powershell
& $cfg.claude_path -p "写一个快速排序算法，保存到 E:\project\webapp\quicksort.py。工作目录为 E:\project\webapp，所有文件操作请在该目录下进行" $cfg.extra_args
```

`cwd` = `E:\project\webapp`

调用结束后：
1. `Test-Path "E:\project\webapp\quicksort.py"`
2. 若 False，搜索并 `Move-Item` 到工作目录
3. 原样返回 CC 输出
4. 1-2 句概括
5. 附 `computer://E:\project\webapp\quicksort.py`

### 示例 2：追问

紧接上例，用户输入 `CC：改成降序`：

```powershell
& $cfg.claude_path -c -p "改成降序排列" $cfg.extra_args
```

不追加工作目录说明（CC 已有上下文）。无文件生成步骤。

### 示例 3：用户指定其他目录

用户输入 `CC：分析 E:\data\main.py`：

```powershell
& $cfg.claude_path -p "分析 E:\data\main.py 这个文件" $cfg.extra_args
```

`cwd` = `E:\data`（用户指定目录优先于会话默认工作目录）

## 异常处理

| 现象 | 处理 |
|---|---|
| `claude.exe` 不存在 / 命令未找到 | 告知用户 Claude Code 未安装或路径错误，原样返回 stderr |
| HTTP 401 / 未登录 | 告知用户 CC 认证失效，需在终端执行 `claude` 交互式登录 |
| CC 执行超时 | 语音场景下用户在等，超时后告知用户「CC 执行超时，请稍后重试或拆分任务」 |
| 文件未生成 | 告知用户 CC 未产出文件，原样返回 CC 输出供用户判断 |
| CC 返回错误信息 | 原样返回错误信息，并简要说明可能原因（不要替用户修复） |

**核心原则**：传话筒模式下，TRAE 不替用户决策、不自动重试、不静默修复——把信息原样传回，让用户自己判断下一步。
