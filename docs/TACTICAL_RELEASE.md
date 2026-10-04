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

新版公開 source 已正常 push，Web-only [v1.2.0 Release](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d/releases/tag/v1.2.0) `402900832` 已發布（draft=false），tag 固定 `17ac56b5f3f937c591d442c184ff29d46cfe832e`。服務端唯一 Web ZIP 的 uploaded state、大小與 SHA-256 與本機相符；獨立 reviewer 不使用登入／Authorization，完整串流下載至 EOF（HTTP 200、36,685,712 bytes、441.74 秒），實際 SHA-256 與上表一致。不只是 HEAD 或服務端 digest。

初次 Actions [37186241892](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d/actions/runs/37186241892) 真實 failure／deploy skipped，因測試把活的隨機掉落物納入固定節點基準，不是遊戲物件池增長。測試專用修正正常 push 為 `bf2e256f667d0aca5e25bfe21349664a26eaa5fe`；本機獨立 10 次隨機單測和全套 verifier 通過，[37186539392](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d/actions/runs/37186539392) 真實 build／Pages deploy success。沒有修改 v1.2.0 tag、asset 或 runtime。

正式 [Pages 網頁](https://dumbmoneycryptobump-ai.github.io/thunder-vector-3d/index.html) 的 Chrome 舊快取實際顯示「更新並重載」，點擊後載入新版，開始遊戲成功：新戰術任務列實際顯示「掃蕩先鋒 0/12 · 40秒」、生命 5、充能 100%，離線快取完成。這項正式站新版啟動驗收與上表的本機完整四尺寸／操作／離線 QA 分開記錄。

ZIP 內 `README.md` 沿用來源 HTML 模板的說明，可能使讀者誤解；本 ZIP 已有完整匯出的 HTML／JS／WASM／PCK，解壓後用 HTTP/HTTPS serve 即可，不需重建。Release 說明已澄清；發行後不偷偷替換資產。

Windows 1.2.0 啟動驗收仍受上述政策阻擋，整體交接保持 partial。唯讀清理審查發現 9 組相同 cache／法律文字及 1 組跨技能的重複通用指令；不同作用域不等於可刪除，全部保留。命令去重缺少結構化日誌，coverage_complete=false。7 個本回合暫存檔與 ledger 保留於專案外，未執行自動隔離或刪除；正式素材、永久測試、套件、失敗證據與不相關工作均保留。
