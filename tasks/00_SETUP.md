# 00 — 環境安裝

完成條件：Godot、Git、Python、Node、Codex CLI 可從 PowerShell 執行；Ollama 可選擇性執行；`python tools/verify_project.py` 通過。

建議命令：
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install_windows.ps1
# 重開 PowerShell
.\scripts\setup_ai.ps1 -OllamaModel "qwen3.5"
.\scripts\configure_codex_mcp.ps1 -OllamaModel "qwen3.5"
.\scripts\verify.ps1
```
