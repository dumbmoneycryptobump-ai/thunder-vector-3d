# v1.2.0 發行與限制

2026-10-04。新內容：[九項戰術任務、脈衝航道、救援信標與通知動畫](TACTICAL_MISSIONS.md)。保留原有百發超載、僚機、四武器、三戰區、操作與离線玩法。

## 實際封包

來源是僅含公開遊戲歷史的 clean checkpoint `7c09be58bac181f9b720d7fdd722d62685b81793`，不是根工作區的私人祖先或 Tokyo 專案。兩個 build 都保留先前版本，不覆蓋 v1.1.0。

| 項目 | 實際結果 |
|---|---|
| `scripts/build_web.ps1 -BuildName tactical-20261004` | exit 0，單執行緒 Godot 4.7.2 Web；27 檔逐 ZIP 成員雜湊通過、manifest dirty=false |
| Web ZIP | `build/web-crossdevice/tactical-20261004/ThunderVector3D-web.zip`，36,685,712 bytes，SHA-256 `058f2eeb00c03076d50d7265a80485ad9382c174360e639a155879a6d718c6db` |
| 新版 Chrome | WebGL 真啟動，四尺寸 28 布局條件、可信雙指射擊產生分數／任務進度、超載完成任務、pause 與斷網重載／重置均通過 |
| `scripts/build_windows.ps1 -OutputSubdirectory tactical-20261004` | exit 1；完整 source verifier／regressions／parser／smoke 通過，匯出 EXE 成功，第一次 exported-headless 啟動被應用程式控制政策封鎖 |
| Windows EXE | 135,317,912 bytes，SHA-256 `a6fe533cebff4052964996b0ad9e13e81277ab09f1a1717625af96a49ffc3d5e`；無 Windows ZIP，無 launch PASS |

Windows CodeIntegrity 3033／3077 事件在台北時間 2026-10-04 15:26:37–38 指向這份 fresh EXE 的 Enterprise 簽章／政策限制。沒有關閉安全防護、改名移動重試、購買簽章或使用 SkipLaunchValidation 冒充驗收。這是匯出 EXE 的限制；正式 Godot 執行原始碼的 parser／GL 畫面已實測，不代表匯出檔通過。

Windows 玩家可保留已公開 [v1.1.0 的舊套件](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d/releases/tag/v1.1.0)，或使用新版網頁／以官方 Godot 開啟新版原始碼。對另一台乾淨 Windows 或實體 iOS／Android 仍未測試。

## GitHub 授權診斷

本回合沒有再次啟動登入／OAuth。唯讀、非互動的既有 GCM 授權仍識別 `dumbmoneycryptobump-ai`，這個公開 repository 的 push 權限有效；有效 credential helper 只有一個 manager，兩次程序快照未見重複的認證程序。其他未指定帳戶的 Git 操作「可能」再次要求選帳號，但沒有視窗標題／URL／截圖，不能把假設寫成已確診。

本工作後續 Git/API 操作指定既有帳戶，禁止互動提示；若授權不可用會直接停止，不重啟登入、不輸出 token、不改全域設定、不修改舊 Avery-TSE 儲存庫或署名。仍有視窗時需提供已遮蔽敏感資料的截圖，以確認是哪個程式觸發。

## 公開發行

新版公開 push、Actions／Pages 和 Release 匿名下載仍待實際執行驗證；未宣稱新的 1.2.0 已上線。Windows 1.2.0 啟動驗收仍受上述政策阻擋。最新實際狀態以智慧圖譜及本文件後续更新為準。
