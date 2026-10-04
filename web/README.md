# Thunder Vector 3D — Web / 跨裝置版本

這是 Godot 自訂 HTML 外殼，不是直接可玩的 `index.html`。請使用 Godot **4.7.2 stable** 的 `Web` 匯出預設產生遊戲，再以 HTTP/HTTPS 開啟；不要直接雙擊 HTML。

## 建置與本機試玩

```powershell
.\scripts\build_web.ps1 -BuildName local-test
python .\scripts\serve_web.py --directory .\build\web-crossdevice\local-test\site --port 8060
```

開啟 `http://127.0.0.1:8060/index.html`，按「開始遊戲」。從目錄網址開啟時，外殼會將目前網址正規化成 `index.html`，配合 Godot 內建 worker 的離線快取鍵。`-GodotCommand` 可指定 Godot 執行檔。每次建置必須使用新的 `-BuildName`；不指定時自動產生時間戳記。既有建置不會被刪除或覆蓋。

建置輸出位於已忽略的 `build/web-crossdevice/<BuildName>/`：

- `site/`：完整靜態網站與授權文件，可整個放到 HTTPS 靜態主機。
- `ThunderVector3D-web.zip`：網站檔案 ZIP，每個成員已比對 SHA-256。
- `build-manifest.json`：引擎、模板與輸出雜湊、Git checkpoint／dirty 狀態。匯出成功不等於瀏覽器或實機驗收通過；瀏覽器驗收另列。

手機在可信任的同一區網測試時，可明確加上 `--bind 0.0.0.0`，再用電腦的區網 IP 連線。這個開發伺服器預設只綁定本機，不應直接對公網開放。HTTP 區網網址可遊玩，但通常不能安裝離線 PWA；正式版本使用 HTTPS。

## 裝置與操作

畫布固定為 1280×720 邏輯尺寸，以 CSS 等比例縮放；直向與橫向都維持 16:9，不裁掉遊戲區域。手機畫布外提供至少 48 CSS 像素的操作按鈕、八方向搖桿與獨立文字狀態列。直向有橫向建議，但不強制鎖住旋轉。

桌機保留 WASD／方向鍵、空白鍵／滑鼠左鍵射擊、1–4 武器、B 炸彈、E 超載、P 暫停、R 重開、O 設定。觸控面板包含相同動作，以及設定選單方向／確認鍵。電腦可按「觸控面板」測試外部控制。

「開始遊戲」由真實點擊啟動引擎；音訊仍受瀏覽器政策影響，無聲音時再點一下遊戲畫面。全螢幕也必須由使用者按鈕觸發，個別 iPhone 瀏覽器可能不提供此功能。切換分頁、失去焦點及取消指標會釋放移動／射擊；回來後按「繼續」。

## 執行期橋接契約

外殼在引擎啟動前設置：

```javascript
window.thunderDeviceControls = true;  // Web 不重複顯示畫布內觸控操作
window.thunderDeviceTouch = matchMedia('(pointer: coarse)').matches || navigator.maxTouchPoints > 0;
```

Godot 的 JavaScriptBridge 必須持有 callback 參照並提供：

```javascript
window.thunderDeviceMove(x, y);                 // 正規化方向；y 正值向畫面下方
window.thunderDeviceAction(action, pressed);    // 按下／放開，射擊支援持續按住
window.thunderStateJson;                        // JSON 字串，每 0.25 秒更新
```

action：`fire`, `bomb`, `overdrive`, `weapon_cycle`, `pause`, `restart`, `settings`, `up`, `down`, `left`, `right`, `confirm`, `focus_lost`。最後一個動作只由失焦／隱藏／離頁事件觸發；重新獲得焦點不會自動繼續。狀態：`hp`, `score`, `weapon_mode`, `overdrive_charge`, `overdrive_seconds`, `paused`, `dead`, `settings`, `sector`。

每個指標各自擁有按鈕／搖桿；另一手指放開不會解除仍按住的射擊。`pointercancel`、失焦與分頁隱藏會清空輸入。`window.thunderWebReady` 表示引擎啟動 Promise 已完成；`window.thunderWebError` 保存啟動錯誤供測試查驗，並非完整遊戲正確性證明。

## 相容性、離線與部署

預設使用 GL Compatibility／WebGL 2、單執行緒、關閉 GDExtension，包含桌機與行動裝置紋理格式；不需要 COOP／COEP 或 SharedArrayBuffer。沒有 CDN、外部字型或遊戲內 AI 服務。必須保留 Godot 產生的所有同名檔案，不能單獨重新命名 `index.html`、JS、WASM 或 PCK。[Godot Web 匯出說明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

PWA 使用 Godot 匯出產生的 manifest 與 service worker；`Engine.startGame()` 的啟動流程會註冊相對路徑 worker，因此可放在 GitHub Pages 的專案子路徑。外殼使用該 worker 的 `claim` 訊息取得控制，首次啟動後至多再取得同源 WASM／PCK 兩個檔案，讓內建版本化快取完整；不改寫產生的 worker，也不操作無關網站快取。每個下載上限 128 MiB／60 秒，失敗時不影響線上遊戲，可按「重試離線快取」。

只有檢查同一份快取中全部九個核心檔案存在且回應成功後，才顯示「離線快取已完成」並設置 `window.thunderOfflineReady=true`。HTTPS／localhost 應等待這個狀態後，再用不帶查詢參數的明確 `index.html` 網址離線重新開啟。偵測到等待啟用的新 worker 時會提供「更新並重載」按鈕，明確點擊才送出官方 `update` 訊息、結束本局並載入新版；不會遊玩途中自動重載。儲存空間不足、隱私模式、清除網站資料或瀏覽器淘汰快取仍可能讓離線失效。請不要將「匯出已啟用 PWA」誤認為每種手機都已實測離線成功。

本機伺服器提供 `application/wasm`、JS／manifest MIME，停用目錄列表，禁止符號連結越界，並要求重新驗證可變檔名的 HTTP 快取；離線資料由 Godot 版本化 worker 管理。正式主機請保留正確 WASM MIME 與更新策略。不要快取新舊版本混合的一半檔案。

## 官方模板與來源

官方 [4.7.2 版本頁](https://godotengine.org/download/archive/4.7.2-stable/) 的標準模板包為 `Godot_v4.7.2-stable_export_templates.tpz`，1,281,349,702 bytes，官方 release metadata 發布整包 SHA-256：

```text
f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011
```

本機此次只經 HTTPS 從官方 GitHub release 以精確 HTTP 206 範圍取得 Web 所需成員，共傳輸 20,436,276 bytes，確認 `version.txt=4.7.2.stable`、外層 ZIP 成員 CRC32 與內層 ZIP 全成員 CRC32。**沒有下載整包，因此未驗證整包 SHA-256。** 以下僅是已安裝 Web 模板位元組的本機 SHA-256 指紋：

| 模板 | Bytes | SHA-256 |
| --- | ---: | --- |
| `web_nothreads_release.zip` | 10245903 | `d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0` |
| `web_nothreads_debug.zip` | 10232720 | `08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a` |

其他開發者可從官方完整模板包安裝；CI 建議下載完整包並驗證其發布雜湊。Windows 位置為 `%APPDATA%/Godot/export_templates/4.7.2.stable/`，Linux 通常為 `~/.local/share/godot/export_templates/4.7.2.stable/`。

自訂外殼使用官方 `$GODOT_URL`／`$GODOT_CONFIG`／`$GODOT_HEAD_INCLUDE` 替換與 `Engine.startGame`、`canvasResizePolicy:0`；API 已對照 [官方自訂外殼文件](https://docs.godotengine.org/en/stable/tutorials/platform/web/customizing_html5_shell.html) 及 [4.7.2 標記啟動程式](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/js/engine/engine.js)。
