# 百發超載版 Windows 封包

2026-10-04，來源檢查點 `e43d4cc2e4f2b909eaa975e786b90d7c47e11380`，建置時 `source_state=clean`。後續提交只補交付／驗證記錄；沒有重新改動 runtime。

- 直接遊玩：`build/arcade/ThunderVector3D.exe`
- 分享 ZIP：`build/arcade/ThunderVector3D-1.0.0-windows-x86_64.zip`
- ZIP **55,287,945 bytes**，SHA-256 `6014162ed67fca1945f384ac723b14f7289bf08479e62b18cb459258b01a3d98`
- EXE **125,254,824 bytes**，SHA-256 `5abd075b70689f1c30efd2041c07946f859e55ea8b44fdd71928d6352b82746f`

正式匯出指令 `scripts/build_windows.ps1 -OutputSubdirectory arcade` **exit 0**：完整來源回歸、Godot 4.7.2 Windows x86_64 PE 驗證、匯出 EXE headless 啟動、實際 Windows 視窗建立／存活／正常關閉，以及 ZIP 十二個檔案白名單與內含 EXE SHA-256 一致性均通過。`BUILD_INFO.txt` 記錄 `launch_validation=passed`，`built_utc=2026-10-04T01:46:57.3403201Z`。

ZIP 包含自帶資源 EXE、操作說明、BUILD_INFO、三份素材來源紀錄，以及遊戲／素材／Godot 與第三方授權。遊玩不需要 Godot、Python、AI 工具或網路。仍沿用專案封包版號 1.0.0，以 `arcade` 目錄與來源 SHA 區分本次更新。

開場按 **E** 即可六秒自動百發齊射；平時 Space／左鍵射擊、WASD／方向鍵移動。起始兩架僚機，武器階級三變四架，M 切換震動。完整機制與量測限制見 [ARCADE_OVERDRIVE.md](ARCADE_OVERDRIVE.md)。

原始、`optimized`、`content` 舊版 EXE／ZIP 未覆寫。此次僅本機分支 `codex/arcade-overdrive-20261004` 儲存 Git 檢查點，**未推送 GitHub、未建立 Release**。本機舊歷史含非公開參考資料；未來發佈應接續既有已清理的公開分支，不可直接推送本機主線祖先。

限制：另一台未安裝 Godot 的乾淨 Windows 尚未實測；EXE 未簽章，SmartScreen／Smart App Control 可能警告或阻擋。未關閉或修改任何安全防護。主觀平衡仍需玩家實玩，不以固定測試負載承諾所有硬體 FPS。

## 收尾檢查

唯讀去重稽核掃描 272 個專案檔、212 個使用者技能檔；沒有修改全域技能。兩組結果均保留：`detox-31f82697703d` 為 Godot 每資源的編輯器折疊狀態，`detox-dcd2cf707135` 為不同人物技能範圍內的重複指令區塊，沒有可自動刪除的證據。稽核沒有結構化命令紀錄，因此 `coverage_complete=false`，不能宣稱查無所有重複命令。

本次審查封包／原始模型回覆及非正式 QA 圖，在必要結論已整理入本文件與玩法記錄後，依任務 ledger 移往可還原隔離區；不永久刪除。原圖、正式截圖、測試、來源、授權、建置與啟動日誌均保留。本機隔離收據不包含在公開原始碼中。
