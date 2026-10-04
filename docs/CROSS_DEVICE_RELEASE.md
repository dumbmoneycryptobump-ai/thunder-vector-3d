# Thunder Vector 3D 1.1.0 — 開源跨裝置版

- [免安裝網頁](https://dumbmoneycryptobump-ai.github.io/thunder-vector-3d/index.html)：實際 Actions 建置／部署成功；正式網址遊戲啟動、四武器、觸控與離線重載通過。
- [MIT 原始碼](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d)：匿名 repo API／raw README HTTP 200。
- [版本下載](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d/releases/tag/v1.1.0)：新帳戶的發佈與匿名 ZIP 下載驗證尚未完成。

Windows ZIP 解壓後執行 `ThunderVector3D.exe`，不需要安裝 Godot。Web ZIP 是可自行部署的網頁封包，需 HTTPS 或 localhost HTTP 服務；不是直接雙擊 HTML。首次完整快取後支援離線。目前以使用者確認的 `dumbmoneycryptobump-ai` 公開發佈；原 `Avery-TSE` 的限制僅留作下方歷史紀錄。新帳戶的 Release 發佈與匿名下載尚待驗收，不提前宣稱封包對外下載已通過。

同一遊戲支援鍵盤／滑鼠、獨立多指搖桿與射擊、手把按鍵；保留導彈、連鎖閃電、貫穿雷射、百發超載與僚機。手機／平板保留完整戰場和 48px+ 畫面外操作鈕，失焦自動釋放並暫停。首次完整下載且頁面顯示「離線資料已快取」後可以斷網重載。

## 真實驗收與界線

本機 Godot 4.7.2 靜態／parser／全套回歸 exit 0，包括 161 項觸控所有權與 254 項主場景跨裝置整合斷言。獨立公開目錄完整驗證亦 exit 0。Windows 匯出檔 headless 與實際 Windows 主視窗建立、存活、正常關閉通過。

Chromium 真實 WebGL 在桌面 1280×900、手機直向 390×844、手機橫向 844×390、平板 768×1024 共 105 項瀏覽器斷言通過，包括四武器、多指獨立釋放、取消、暫停、設定、失焦與桌面斷網後重新啟動。手機尺寸是模擬；實體 Android／iPhone、macOS／Linux、實體手把類比軸與另一台乾淨 Windows 尚未驗收。不保證舊機或所有硬體 FPS。

瀏覽器需要 WebGL 2／WebAssembly；單執行緒不要求 SharedArrayBuffer／COOP／COEP。首次下載、隱私模式、儲存被清除會影響離線遊玩。Windows EXE 未簽章，未修改系統安全設定。[跨裝置說明與測試範圍](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d/blob/main/docs/CROSS_DEVICE.md)

## 下載完整性

| 封包 | 大小（bytes） | SHA-256 |
| --- | ---: | --- |
| ThunderVector3D-1.1.0-windows-x86_64.zip | 65330640 | `0f0ea2c347cdd897f4855309e5332919bb73aa49e177ad243e0a305800aded29` |
| ThunderVector3D-web.zip | 36666705 | `8a41e9eb87d4d41107f097aca26bb11dfe5d471fb2fc87fda631f479576aa20a` |

Windows EXE 135299192 bytes，SHA-256 `61a971c45fe03970acea90a63129793c802666809fe7b717da534d50a49166b7`。Windows ZIP 15 檔、Web ZIP 27 檔；皆含遊戲／素材／引擎／字型授權與來源紀錄。原始碼採 MIT，原創 ImageGen 素材依素材授權；Noto Sans TC 另依 OFL 1.1。

本機兩包來自乾淨 runtime checkpoint `7bea41fcdc8d2f7ed68f7ee87f4973bbde60af39`；後續只有瀏覽器測試、文件、截圖和 Git 換行屬性變更。公開來源使用獨立安全快照，不推送本機私人祖先；公開版本與上述匯出使用相同 `game/` 與 Web 外殼內容。發佈工具會核對 GitHub 草稿與公開後的 ZIP size／SHA-256，不覆蓋既有公開版本。

## 目前公開發佈進度

2026-10-04 依使用者明確確認的 `dumbmoneycryptobump-ai` 帳戶及官方 Git Credential Manager 授權，建立 public 儲存庫並正常推送安全公開歷史；沒有推送本機私人祖先、參考圖、憑證、編譯檔或其他專案。匿名 repo API／raw README HTTP 200。

GitHub Actions [run `37182321498`](https://github.com/dumbmoneycryptobump-ai/thunder-vector-3d/actions/runs/37182321498) 在公開來源 `297ce8c20d4abfa1d1f575386d91ae72e7546ddd` 實際 build／deploy 成功，正式 Pages 子路徑 HTTP 200。後續公開 checkpoint `875beba516eb6e2f31cd50c311384c32673cfa4c` 僅新增發佈工具的指定帳戶與 API 身分護欄，不改遊戲 runtime。此帳戶的 Release ZIP 發佈與匿名下載仍在驗收。

正式 Pages 已在實際 Chrome 通過引擎啟動、四武器／6 秒超載、暫停／設定確認、可信任雙指移動加射擊與單指釋放／取消檢查。四尺寸 390×844、844×390、768×1024、1280×900 保持完整 16:9 戰場，八個操作鈕均至少 48px 且位於 viewport 內。瀏覽器網路切為 offline 後重載，按開始可重新啟動引擎；HTML／JS／WASM／PCK 200 回覆確認由 service worker 提供。測後恢復網路並關閉觸控模擬。這項正式子路徑驗收與上方本機 105 項斷言分別記錄，不增加實體手機／手把／其他作業系統的驗收聲稱。

原 `Avery-TSE` 儲存庫、tag、發行與草稿均保留不動；沒有提交申訴、購買額度或更改系統安全設定。下節描述的是原帳戶當時的限制，不代表新帳戶部署失敗。

## 歷史：Avery-TSE 尚未通過的外部驗收

public 快照 `9e805c07ee580f5093049359b180d3ac8012f601` 已正常推送，與過濾後來源 `62818d243dd91bcb5b12b807bad29c8d92e0166c` 的 240 個 Git blob／mode 完全一致，只有公開根 `76752fedf09e10143574b9d88b10b4cc9444af44` 為祖先。獨立安全審查 PASS；不包含私人歷史／參考圖／憑證。

GitHub 已建立 draft=false 的發行 metadata id `402816748`，兩個 ZIP 的服務端 size、state=uploaded 與 SHA-256 均與上表一致；發佈後直接按 id／tag 再讀與 tag commit 解析皆通過，tag 指向上面的公開來源。匿名存取仍 404，故不能宣稱對外可下載。

此帳戶下 `/releases` 列舉在登入後也回傳空陣列，直接按 id／tag 讀取卻成功，導致草稿 id `402815823` 沒被列舉並保留下來；沒有擅刪草稿或資產。後續工具必須先直接查已發佈 tag、或用已知 draft id 明確續作，不能把空列表當成沒有版本。這些 API 可見性異常保留為外部待辦，不重複嘗試發佈。

實際 workflow dispatch HTTP 422 回覆此使用者 Actions 停用；repo 設定卻 enabled、workflow active，無 workflow run。匿名 API、專案頁、raw README 與 Pages 均 HTTP 404。這是外部帳戶可見性／執行限制，原因未確認；不是遊戲測試失敗或已知付費額度問題。需由使用者聯絡 GitHub Support 處理，或明確指定其他主機。[官方帳戶停用說明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)

若將來重新啟用原 `Avery-TSE` 發佈，仍須另行驗收真正 Actions build／deploy、正式 Pages 遊戲與離線重載、匿名 Release ZIP 下載。原帳戶當時只有本機 Web 與原生包通過；不能用新帳戶成功替原帳戶補記驗收，也沒有虛報實體手機結果。原有所有 Windows 版本保留。
