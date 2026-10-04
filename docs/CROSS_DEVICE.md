# 跨裝置／開源版 1.1.0

這一版讓同一個 Godot 射擊遊戲提供 Windows 原生包與瀏覽器版。MIT 原始碼和原創 ImageGen 素材公開；Godot／第三方字型等各自授權另附。不把私人參考圖、AI 金鑰、開發快取或本機私人 Git 祖先發佈出去。

## 操作

| 裝置 | 移動 | 射擊 | 其他 |
| --- | --- | --- | --- |
| 電腦 | WASD／方向鍵 | Space／滑鼠左鍵 | 1–4 武器、B 炸彈、E 百發超載、P／Esc 暫停、O 設定、R／Enter 重開 |
| 手機／平板網頁 | 畫面外八方向搖桿 | 按住射擊鈕 | 獨立炸彈、超載、切武器、暫停、設定、重開鈕；設定方向／儲存鈕 |
| 手把 | 左搖桿／十字鍵 | A／右扳機 | B 炸彈、X 切武器、Y 超載、Start 暫停、Back 設定；死亡後 A 重開，設定用十字鍵／A |

所有射擊來源共用冷卻，不會因同時按兩個射擊方式額外多發。保留導彈、閃電、雷射、百發超載與 2–4 架僚機。手機直橫向等比顯示完整 16:9 戰場，操作鈕至少 48 CSS 像素。離開分頁／App 會釋放輸入並暫停，不會回來還卡住射擊。

## 支援範圍與限制

Windows 10／11 x86_64 原生包需 OpenGL 3.3；macOS、Linux、Android、iOS／iPadOS 透過現代瀏覽器遊玩，需 WebGL 2 和 WebAssembly。單執行緒 Web 模板不需要 SharedArrayBuffer 或 COOP／COEP；執行期沒有 AI 或外部 CDN。[Godot 官方 Web 限制與說明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

Web 的 3D render scale 0.75，關閉 Web／行動裝置陰影；不宣称所有硬體 FPS。手機系統全螢幕可能不提供，仍可在普通頁面遊玩。初次 HTTPS 完整下載、service worker 快取完成後可離線重開；隱私模式、清除資料、儲存空間不足與系統清除快取會影響離線功能。Windows EXE 未簽章，不修改安全防護設定。

## 開發與驗收

`scripts/verify.ps1` 執行靜態驗證、Godot parser 與所有既有 gameplay 回歸，新增 `device_controls_test.gd`（161 項指標所有權斷言）與 `device_integration_test.gd`（254 項主場景跨裝置狀態斷言）；兩者已本機實跑通過，settings 寫入 0。

`scripts/build_web.ps1` 產生固定尺寸自訂外殼、WASM／PCK、PWA worker、ZIP 與檔案雜湊；`scripts/serve_web.py` 預設只服務 localhost。瀏覽器驗收工具 `tools/test_web_browser.cjs` 需 Playwright 與 Chrome，測試實際 WebGL 啟動、四種武器、暫停／設定／失焦、多指操作與離線重載。手機尺寸模擬不是實體 iPhone／Android 驗收。

GitHub Actions `.github/workflows/web-pages.yml` 從乾淨公開來源建置，官方 Godot 4.7.2 engine／模板整包 SHA-256 驗證後，僅將匯出的 `site/` 部署至 Pages。`tools/github_release.py` 使用既有 Git Credential Manager 驗證，明確命令才寫入；先驗證草稿 ZIP size／SHA-256，再發佈，不替換既有公開版本。

2026-10-04 本機完整 `scripts/verify.ps1` 已 exit 0。實際 Chromium 桌面 1280×900、手機直向 390×844、手機橫向 844×390、平板 768×1024 合計 105 項瀏覽器斷言通過：實際 WebGL、四武器、超載、設定、失焦、多指搖桿／射擊獨立釋放與取消；桌面全新 profile 切斷網路後重載並啟動遊戲通過。這些是 Chrome 尺寸／觸控模擬，不是實機測試。

Windows 1.1.0 原生包已實際匯出，headless 與 Windows 主視窗建立／存活／正常關閉皆通過。正式 Pages 子路徑與匿名公開下載被 GitHub 帳戶限制阻擋，並未通過；物理手機／手把類比軸及另一台乾淨 Windows 尚未實測。

真實瀏覽器畫面：[桌面](screenshots/web-desktop.png)、[手機直向](screenshots/web-phone-portrait.png)、[手機橫向](screenshots/web-phone-landscape.png)、[平板](screenshots/web-tablet.png)。

## 獨立審查決策

兩輪 DashScope `qwen3.8-flash` 真實回覆完成，最終沒有新的 evidence-backed blocker。Codex 未把模型一致當成測試證據：`limit_length` 速度指控、設定失焦不釋放、單執行緒仍必須隔離標頭、EXIF 才能证明素材授權等假說，由程式／官方版本與真實驗收反證。有效回饋促成動作後即時 Web 遙測，以及首次完整離線快取的驗證。

API 修正後另取得 Qwen 精簡最終 verdict：PASS、finish_reason=stop；它明確只根據提供的描述與證據，不能認證未展示的原始碼。獨立代理和 Codex 已直接檢查實作與 31 項回歸，不把模型判詞当作 GitHub 部署或匿名下載成功。

發佈 helper 補上草稿最後 tag identity 及發佈後 metadata／全部 ZIP digest 再讀；不可聲稱阻止其他有管理權限的人並行改動 GitHub。服務端並發不是客戶端可保證的原子交易，若公開後發現不一致會報需要人工檢查、不自動刪版本。實際 API 的不存在 tag `/commits/` 回傳 422，已改先查 `/git/ref/tags/`，存在時仍解析 annotated tag 並拒絕競態錯誤。另補直接 `/releases/tags/` 檢查防止空列舉下重建公開版本；`--draft-id` 只續作確切且通過身分檢查的草稿，找不到不回退建立。獨立代理審查與永久 31 項離線發佈安全測試通過。iPhone 音訊與實體平台差異保留為驗收限制，不冒稱完成。

## GitHub 外部阻擋

public 來源 `9e805c07ee580f5093049359b180d3ac8012f601` 已正常 fast-forward 推送，240 個 Git blob／mode 與安全來源完全一致，歷史只有既有公開根與新快照兩個 commit。未推送私人祖先、參考圖、金鑰、build 或其他專案。

GitHub API 顯示 repo public、Actions enabled／allowed all、workflow active、Pages workflow 模式，但實際 dispatch 回傳 HTTP 422，訊息包含 user／Actions／disabled；沒有任何 workflow run／check。匿名 API、專案頁、raw README、Pages 全部 HTTP 404。可證實外部限制，不能由此推斷帳戶遭限制的原因，也未宣稱是免費額度耗盡。

[GitHub 官方說明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)：GitHub 控制的帳戶停用狀態不是調整 repo Actions 設定就能解除，需聯絡 Support。未付費、變更安全設定、替換帳戶或擅自部署其他服務。解除後需重新觸發此 workflow、確認 build／deploy 實際成功，再跑公開子路徑／離線瀏覽器及匿名下載測試；這些驗收目前未完成。
