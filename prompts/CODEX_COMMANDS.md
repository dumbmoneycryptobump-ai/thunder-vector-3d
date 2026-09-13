# 可直接貼給 Codex 的指令

## 1. 第一次接手
讀取 AGENTS.md 與 knowledge_graph/knowledge_graph.json，說明目前已完成、待完成、最高風險與下一個最小任務。不要修改檔案。

## 2. 驗證目前原型
執行 tools/verify_project.py；若 Godot 在 PATH，執行 headless parser 驗證。只修正實際出現的錯誤，不做無關重構。

## 3. 做物件池
針對 player_bullet、enemy_bullet 與一般 enemy 建立簡單物件池。保持所有操控與視覺行為不變，增加可觀測的活躍／閒置數量，並提供 10 分鐘壓力測試方法。

## 4. 抽出玩家模組
把玩家移動、射擊與受傷狀態從 main.gd 抽成一個 PlayerController 腳本。一次只抽玩家，不同時重寫敵人或 UI。完成後跑靜態與 headless 驗證。

## 5. 新增設定選單
新增可本機保存的主音量、音效音量、全螢幕與難度設定。使用 Godot ConfigFile，不得連網；保留 P/Esc 暫停行為。

## 6. 導入 GLB 模型
在不破壞碰撞半徑與遊戲比例的前提下，允許用 res://assets/models/*.glb 替換程序化飛機。模型缺失時必須自動退回目前的程序化佔位模型。

## 7. 加強 BOSS
為 BOSS 增加三階段彈幕，但每階段要有清楚可讀的安全空隙。不要單純提高子彈速度；加入血量門檻、視覺提示與測試方法。

## 8. 本機模型審查
使用 thunder_local.review_change 審查目前 git diff。先列出 BLOCKER，再修正；沒有實際測試日誌時不得標記 headless_verify 為 done。

## 9. Windows 打包
確認 export_presets.cfg、圖示與版本資訊；執行 Windows release export。若缺 export templates，停止並回報精確安裝步驟，不要偽造 EXE。
