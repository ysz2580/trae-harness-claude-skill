@echo off
REM claude-harness.cmd —— claude-harness.ps1 的启动器
REM
REM 为什么需要这个 .cmd：
REM   PowerShell 执行策略（默认 Restricted）会拦截 .ps1，agent 用 `& $s` 直接调 .ps1 会失败。
REM   .cmd 走 cmd.exe，不受 PowerShell 执行策略约束；内部固定用 -NoProfile -ExecutionPolicy Bypass
REM   启动干净子进程跑 .ps1，绕过 Restricted 并跳过 TRAE 注入的 profile-snapshot（消除 CLIXML 噪声）。
REM   agent 只需 `& $s`（$s 指向本 .cmd）即可，无需记住加 -ExecutionPolicy Bypass。
REM
REM 参数：原样 %* 透传给 .ps1（-Prompt / -WorkingDirectory / -Continue 等）。
REM 注意：若 prompt 含 cmd 元字符（& | < > ^），改用显式
REM   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<本目录>\claude-harness.ps1" -Prompt ...
REM 形式（见 SKILL.md「命令格式」段的兜底写法）。

setlocal
set "PS1=%~dp0claude-harness.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
endlocal
