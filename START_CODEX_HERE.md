# 交給 Codex 的入口

這是一個 **Codex 工作包**，不是要求你手動開發。Codex 負責修改遊戲；Ollama 地端模型透過 `thunder_local` MCP 負責規劃與程式審查；`knowledge_graph/` 是智慧圖譜地圖與專案狀態來源。

## 第一次設定（Windows PowerShell）

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install_windows.ps1
```

安裝完成後重開 PowerShell，回到此資料夾：

```powershell
.\scripts\setup_ai.ps1 -OllamaModel "qwen3.5"
.\scripts\configure_codex_mcp.ps1 -OllamaModel "qwen3.5"
.\scripts\verify.ps1
```

硬體不適合下載大型模型時：

```powershell
.\scripts\setup_ai.ps1 -SkipModelPull
.\scripts\configure_codex_mcp.ps1 -OllamaModel "你已安裝的模型名稱"
```

## 直接讓 Codex 接手

互動模式：

```powershell
.\scripts\run_codex.ps1
```

進入 Codex 後貼上：

```text
$thunder-vector-godot
讀取 AGENTS.md、prompts/CODEX_MASTER_PROMPT.md 與 knowledge_graph/knowledge_graph.json。先呼叫 thunder_local.plan_game_feature 規劃最高優先的未完成節點，列出驗收條件、預計修改檔案、測試與回滾方式；接著在 workspace-write 沙盒內完成該節點。修改後執行所有可用驗證，把 git diff 交給 thunder_local.review_change，修正所有 BLOCKER，最後只用真實測試證據更新智慧圖譜。不要把遊戲改成需要雲端 API，也不要使用《雷電》原作素材。
```

非互動、自動執行主工作卡：

```powershell
.\START_CODEX_HANDOFF.ps1
```

## 要 Codex 先做到可玩 Windows 版本

```text
先完成環境與專案驗證，再把目前 Godot 專案匯出成 Windows x86_64 Release。若缺少與 Godot 4.7.2 相符的 Export Templates，停止並告訴我精確安裝位置，不得假裝 EXE 已建立。匯出成功後啟動 EXE，紀錄實際命令、輸出路徑、錯誤與手動測試清單；再更新智慧圖譜。
```

## 重要檔案
- `AGENTS.md`：Codex 永久規則。
- `.agents/skills/thunder-vector-godot/SKILL.md`：Codex 專用 Skill。
- `prompts/CODEX_MASTER_PROMPT.md`：主指令。
- `prompts/CODEX_COMMANDS.md`：逐項功能指令。
- `knowledge_graph/smart_graph.png`：智慧圖譜圖片。
- `knowledge_graph/knowledge_graph.json`：機器可讀智慧圖譜。
- `reference_images/`、`game/assets/`：視覺參考與原型素材。
