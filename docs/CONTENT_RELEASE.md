# 內容擴充版 Windows 交付

2026-09-13，本機已完成，不代表 GitHub 已更新。

- 可直接執行：[ThunderVector3D.exe](../build/content/ThunderVector3D.exe)
- 可分享下載包：[Windows x86_64 ZIP](../build/content/ThunderVector3D-1.0.0-windows-x86_64.zip)
- [新增玩法、實機展示與測試證據](CONTENT_EXPANSION.md)
- Godot 4.7.2／GL Compatibility，離線執行，不需要另外安裝 Godot。
- 最終封包來源：`00ba240761b6dff33577e3ae212aa75ed6e82072`，`source_state=clean`。
- 打包時間：2026-09-13T09:08:35.0815439Z；本輪第一次封包已由補齊授權的最終封包取代，原版與 optimized 版完整保留。

| 檔案 | 大小（bytes） | SHA-256 |
|---|---:|---|
| EXE | 124638296 | `3142cad3ca95bedea03dc0fe056772396d1eaa27727f2f9f57066420a7951266` |
| ZIP | 54672559 | `1be055c37e5c6c49396f14d161227728f08b12ab8ac954490227d02c891e09f5` |

`scripts/build_windows.ps1 -OutputSubdirectory content` 實跑 exit 0：全套來源驗證、Windows x86_64 PE 檢查、匯出 EXE headless smoke、Windows 主視窗建立／存活／正常關閉、ZIP 11 個檔案白名單與內含 EXE 雜湊比對均通過。啟动 helper 使用 Hidden；另有實際 Windows 渲染截圖，不將視窗存在檢查冒稱人工玩測。完整自動回歸測試與 600 秒模擬壓測見內容紀錄。

ZIP 包含 EXE、README、BUILD_INFO、SHA256SUMS、兩份 ImageGen 來源紀錄、專案 MIT 授權、素材授權及 Godot／第三方授權。編譯產物保持在被 Git 忽略的 `build/content/`，不提交二進位檔。

## 收尾與仍待驗證

- 原創素材流程檢查真正 alpha，双模型流程保留測試反例與兩輪 Qwen 意見；沒有未解決的 critical／high 缺陷。GPU 幀時間與多人手感平衡仍待量測。
- 去重稽核發現 Godot editor 摺疊設定重複（`detox-31f82697703d`）及不同技能的重複指令段（`detox-dcd2cf707135`）；不同用途／作用域，全部保留，未刪全域技能或使用者資料。
- 稽核 coverage_complete=false：缺少結構化命令事件紀錄；二進位／部分格式不做語義去重，超大圖與 build／Git 目錄也有明示排除。不聲稱完整無重複。
- 本輪暫存審查資料採可恢復隔離；本機隔離收據不包含在公開原始碼中。素材來源原圖、正式截圖、測試及既有遊戲保留。
- 尚未在另一台乾淨 Windows 電腦驗收；EXE 未簽章，其他電腦的安全政策仍可能攔截。不修改使用者安全設定。
- 本次未 push GitHub；若後續要求發佈，沿用乾淨公開分支流程，不能推送含歷史參考圖的本機 main。
