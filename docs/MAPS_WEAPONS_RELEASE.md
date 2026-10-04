# 擴大地圖／導彈／閃電／雷射 Windows 交付

2026-10-04。來源 checkpoint `0fbf2a388949ac5f63c46301ac05d161f7bf7f5e`，`source_state=clean`；後續提交只補交付紀錄，沒有改動 runtime。

- 遊玩：`build/maps-weapons/ThunderVector3D.exe`
- 分享：`build/maps-weapons/ThunderVector3D-1.0.0-windows-x86_64.zip`
- EXE **126,391,424 bytes**，SHA-256 `9dfa4ea6f6ff1e2286389fbe977ec21087cd0e29429137dc0b0af6b29afcf2df`
- ZIP **56,424,664 bytes**，SHA-256 `52b6b7c0bc4e9fba9db27b8aec4e2f5729a4d9e6070728b735c8687f7e97c3bb`

`scripts/build_windows.ps1 -OutputSubdirectory maps-weapons` 真實執行 **exit 0**。完整來源回歸、Godot 4.7.2 x86_64 PE 匯出、匯出 EXE headless 啟動、Windows 視窗建立／存活／正常關閉、ZIP 十三個檔案白名單及內含 EXE 雜湊一致性均通過。`BUILD_INFO.txt` 的 `launch_validation=passed`、`built_utc=2026-10-04T02:22:01.9182608Z`；未使用跳過啟動驗證選項。

ZIP 包含自帶資源 EXE、操作說明、建置資訊、四份 ImageGen 素材來源，以及遊戲／素材／Godot 與第三方授權。遊玩無需 Godot、Python、AI 工具或網路。封包版號仍沿用 1.0.0，由 `maps-weapons` 目錄、來源 SHA 與雜湊區別新版。

按 `1/2/3/4` 切換機砲／導彈／閃電／雷射；Space／左鍵射擊、WASD／方向鍵移動，E 百發超載、B 炸彈。保留 2–4 僚機。移動面積增加約 89%，三戰區更換地形；新安裝預設 1600×900，已有設定者按 O 選擇新解析度或全螢幕。

完整機制、658 項武器測試、499 項邊界测试、600 模擬秒壓測、Windows GL 量測及兩輪 Qwen 審查決策，見 [MAPS_AND_WEAPONS.md](MAPS_AND_WEAPONS.md)。正式截圖位於 `docs/screenshots/map_sector_0..2.png` 與 `weapon_2..4.png`；它們是實際渲染的固定展示，不是人工通關宣稱。

## 保留與限制

原始 `build/` 與 `optimized`、`content`、`arcade` 舊版皆保留。只建立本機分支 `codex/sector-maps-20261004` 檢查點，沒有推送 GitHub 或新建 Release。本機祖先包含非公開早期參考，未來發佈須接續既有乾淨公開分支，不可直接把本機歷史推上去。

另一台未安裝 Godot 的乾淨 Windows 尚未實測。EXE 未簽章，SmartScreen／Smart App Control 仍可能警告或阻擋，沒有修改安全設定。人類手感與平衡需實玩；固定負載測量不保證各種硬體 FPS，極端高速雙方連續碰撞及所有傾斜姿態的遮擋也非已完成驗收。

## 收尾

使用專案技能要求的圖譜／測試檢查點，peer-audit 技能促成兩輪獨立挑戰，ImageGen 技能產生透明行星，detox 技能只處理本次可重現暫存。唯讀去重發現 `detox-31f82697703d`（Godot 各資源編輯器摺疊狀態）及 `detox-dcd2cf707135`（不同人物技能範圍的指令重述），皆保留、不修改全域技能。沒有結構化命令日誌，`coverage_complete=false`，不能聲稱查無所有重複命令。本機隔離收據不包含在公開原始碼中。
