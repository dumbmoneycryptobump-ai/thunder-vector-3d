# 版本與官方文件備註（建立日期：2026-08-29）

- Godot：本套件鎖定 4.7.2 stable。官方下載頁：`https://godotengine.org/download/archive/4.7.2-stable/`
- Godot 匯出：需安裝與引擎版本相符的 export templates。官方文件：`https://docs.godotengine.org/en/latest/tutorials/export/exporting_projects.html`
- Codex CLI：可在本機 repo 讀取、修改並執行工具；安裝套件為 `@openai/codex`。官方文件：`https://developers.openai.com/codex/cli`
- Codex MCP：專案可用 `.codex/config.toml` 設定 STDIO MCP server。官方文件：`https://developers.openai.com/codex/mcp`
- Codex 自動化：使用 `codex exec --sandbox workspace-write`。官方文件：`https://developers.openai.com/codex/non-interactive-mode`
- Ollama 本機 API：預設 `http://localhost:11434/api`，聊天端點 `/api/chat`。官方文件：`https://docs.ollama.com/api/introduction`
- MCP Python SDK：本專案採 v2 `MCPServer`，Python 3.10+。官方文件：`https://modelcontextprotocol.io/docs/2026-07-28/develop/build-server`

這些 URL 僅供開發時查閱；遊戲執行不會連線。
