# claude-harness.ps1 —— 传话筒技能的调用器
#
# 作用：自动探测 claude 可执行文件、组装参数、调用 Claude Code。
#   把「找 claude 在哪」这件麻烦事集中在这里，SKILL.md 只需教 agent 调本脚本。
#
# 探测优先级（逐级回退，任一命中即可用）：
#   1) config.json 的 claude_path（用户手动覆盖，最高优先级）
#   2) PATH 上的 claude（Get-Command，最常见——npm 全局安装、原生安装器加 PATH 都走这条）
#   3) 常见安装位置的兜底清单
# → 因此 90% 的用户下载后零配置即可用；config.json 仅在 claude 不在 PATH 时才需要改。
#
# 用法：
#   & claude-harness.ps1 -Prompt "完整prompt" [-Continue] [-WorkingDirectory "E:\..."]
#       -Continue        追问模式（对应 claude -c，复用上一轮上下文）
#       -WorkingDirectory 工作目录（CC 在该目录下执行文件操作）

param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Prompt,
  [switch]$Continue,
  [string]$WorkingDirectory
)

$ErrorActionPreference = 'Stop'

# 在技能目录下定位文件：先从当前目录向上找 .trae（项目级技能），再找全局技能目录。
function Find-InSkill {
  param([string]$File)
  $rel = ".trae\skills\claude-harness\$File"
  $dir = $PWD.Path
  while ($dir) {
    $p = Join-Path $dir $rel
    if (Test-Path $p) { return $p }
    $parent = Split-Path $dir -Parent
    if (-not $parent -or $parent -eq $dir) { break }
    $dir = $parent
  }
  $g = Join-Path $env:USERPROFILE ".trae-cn\skills\claude-harness\$File"
  if (Test-Path $g) { return $g }
  return $null
}

# 1) 读取 config.json（可选，仅用于覆盖默认值）
$cfgPath = Find-InSkill 'config.json'
$cfg = $null
if ($cfgPath) {
  try { $cfg = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $cfg = $null }
}

# extra_args 默认 --dangerously-skip-permissions（语音远程场景无法交互确认权限）
$extraArgs = '--dangerously-skip-permissions'
if ($cfg -and $cfg.extra_args) { $extraArgs = $cfg.extra_args }

# 2) 探测 claude 路径
$claude = $null

# 优先级 1：config.json 显式覆盖
if ($cfg -and $cfg.claude_path -and (Test-Path $cfg.claude_path)) {
  $claude = $cfg.claude_path
}

# 优先级 2：PATH 上的 claude
if (-not $claude) {
  $c = Get-Command claude -ErrorAction SilentlyContinue
  if ($c) { $claude = $c.Source }
}

# 优先级 3：常见安装位置兜底
if (-not $claude) {
  $cands = @(
    (Join-Path $env:USERPROFILE '.claude\local\claude.exe'),
    (Join-Path $env:APPDATA 'npm\claude.cmd'),
    (Join-Path $env:USERPROFILE '.npm-global\claude.cmd')
  )
  $claude = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $claude -or -not (Test-Path $claude)) {
  $msg = "未找到 claude 可执行文件。请任选其一：`n  1) 把 claude 加入 PATH（推荐）；或`n  2) 在 config.json 的 claude_path 写入 claude.exe 的绝对路径。`nconfig.json 位置：$cfgPath"
  Write-Error $msg
  exit 1
}

# 3) 切换工作目录（若指定且存在）
if ($WorkingDirectory -and (Test-Path $WorkingDirectory -PathType Container)) {
  Set-Location $WorkingDirectory
}

# 4) 调用 Claude Code
$extraArgsArray = $extraArgs -split '\s+'
if ($Continue) {
  & $claude -c -p $Prompt @extraArgsArray
} else {
  & $claude -p $Prompt @extraArgsArray
}
