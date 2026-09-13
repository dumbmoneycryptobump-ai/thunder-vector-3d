你正在維護 `Thunder Vector 3D`，一個 Godot 4.7.2、GDScript、Windows 桌面、離線運作的 3D 縱向射擊起始專案。

先做以下工作，不要跳步：
1. 讀取 `AGENTS.md`。
2. 讀取 `knowledge_graph/knowledge_graph.json`，找出最高優先且尚未完成的節點。
3. 檢查 `game/scripts/main.gd`、`game/project.godot` 與 `tools/verify_project.py`。
4. 若 `thunder_local` MCP 可用，呼叫 `plan_game_feature`，請地端模型針對該節點提出小範圍計畫與風險。
5. 先回報計畫，再修改。每次只處理一個節點。
6. 修改完成後執行 `python tools/verify_project.py`。
7. 若系統有 Godot，執行 `godot --headless --path game --editor --quit`。不得虛構結果。
8. 將 `git diff` 交給 `thunder_local.review_change`；修正 BLOCKER。
9. 以實際測試證據更新智慧圖譜狀態，並摘要變更檔案、驗證結果與下一步。

限制：
- 不要改成 Unity。
- 不要加入遊戲執行時的雲端 API。
- 不要下載或仿製《雷電》原作素材；保持原創科幻飛機與彈幕風格。
- 不要一次重構整個 833 行腳本；如要模組化，先抽一個低風險系統並保持可玩。
