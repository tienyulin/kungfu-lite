---
name: doc-author
description: 幫一個 repo 寫兩份文件：README.md 是給使用者的使用文件，單檔自足、可整份上傳文件平台；docs/ARCHITECTURE.md 是給維護者與 AI 的架構文件。HTTP API 專案另從 code 匯出 openapi.json。使用者要寫、補或更新 repo 文件、README、使用文件、架構文件，或 openapi.json 過期、與 code 不一致時使用，新舊專案都適用。
---

# doc-author

開工前把進度清單抄進回覆，完成一步勾一步；遇到本 skill 與 references 都沒定義的
情況，停下來問使用者。

```
進度：
- [ ] Step 1 判定 repo 種類，決定要產哪幾份
- [ ] Step 2 docs/ARCHITECTURE.md 寫完、地標檢查通過
- [ ] Step 3（僅 API）openapi 匯出、完整度檢查通過
- [ ] Step 4（僅對外元件）README.md 寫完、自足檢查通過
- [ ] Step 5 事實抽查與回報
```

兩條原則：

1. 文件是事實，寫錯比寫少嚴重。內容只能來自 repo 裡可觀察的事實（code、設定、註解）
   或使用者親口提供；查不到的細節在正文原地標「（待補：<要問什麼>）」。
   不要發明一個像樣的值再標待補（發明的名字看起來像真的，比空缺更難發現），
   也不要用「常見做法」補（來源寫重試 2 次就寫 2 次，不要自行升級成指數退避）。
2. 本 skill 只建立和修改文件（README、`docs/`、openapi.json），不動 repo 的
   程式碼與其他檔案；Step 3 的補標註是唯一例外，動手前先徵求同意。

名詞用法先讀 [references/glossary.md](references/glossary.md)（存在
`references/glossary/` 資料夾就整個讀）。文件裡用到表列名詞時照它的定義與寫法；
與 repo 慣用講法衝突時以 glossary 為準，並在文件裡註明 code 內的實際識別字。

## 兩個讀者、兩份文件

| 文件 | 讀者 | 目的 | 什麼時候要 |
|------|------|------|-----------|
| `docs/ARCHITECTURE.md` | 維護者與 AI | 讀完能建立系統的心智模型、直接動工，不用重掃 repo | 每個 repo 都要 |
| `README.md`（repo 根） | 對外使用者 | 單檔自足的使用文件，可整份上傳到文件平台 | 有對外介面時是主角；純內部 library 或知識庫，README 寫簡介並指向 ARCHITECTURE.md 即可 |
| `openapi.json` | 使用者與工具 | endpoint 的權威細節 | HTTP API 且框架能匯出時附上（Step 3） |

## Step 1 — 判定 repo 種類

讀 repo 找訊號：ASGI target（`app.main:app`）、`FastAPI(`、swagger 設定是 API；
crontab、k8s CronJob、Celery beat、CLI entrypoint 是會執行的非 API 元件；
被 import 的套件是 library；其餘是純知識庫。

| 種類 | 產出 |
|------|------|
| HTTP API | README（使用文件）＋ docs/ARCHITECTURE.md ＋ openapi.json（可匯出時） |
| cronjob / worker / CLI | ARCHITECTURE.md（觸發方式、輸入輸出、副作用寫進對應節）；CLI 有外部使用者就寫 README 使用文件，否則 README 簡介加指路 |
| library / 純內部 | ARCHITECTURE.md ＋ README 簡介加指路 |
| 純知識庫 | ARCHITECTURE.md（架構節換成內容地圖）＋ README 簡介加指路 |

monorepo（多服務同 repo）：各服務目錄各自一份 README 與 docs/ARCHITECTURE.md，
根目錄的 README 只做索引（服務、一句話說明、路徑）。

## Step 2 — docs/ARCHITECTURE.md

這是一份普通的工程架構文件：分層、目錄、一個 request 怎麼流過系統、為什麼這樣設計。
用工程師的日常用語寫節名（專案結構、設計說明），不自創術語。人類工程師掃著讀要能懂，
AI 讀完要能不重掃 repo 就動工。

寫作要求：

- 提到的路徑、符號、環境變數一律寫真實字面值，寫完照下面的地標檢查逐一驗證。
  不用行號（code 一改就錯）。
- 指令自己跑過才能寫，每塊附一行成功時的輸出長相；跑不了的（依賴壞、缺環境）
  在指令旁標「（待補：未驗證——<原因>）」。
- 領域名詞在敘述裡順帶對應到 code 識別字（例：「回收筒（Oracle `RECYCLEBIN`）」），
  不另開對照表。
- 設計說明寫為什麼，不只寫是什麼——錯誤格式、權限、重要預設值這類行為規則，
  以及「看起來奇怪但是故意的」的地方，防後人好心改壞。
- 長度不設限，以講清楚為準；砍的是行銷語和空話，不是事實。

範本（節名與層級照抄；不適用的節省略並在 Step 5 回報說明）：

```markdown
# <repo 名> — 架構

<開頭一段：這是什麼、解決什麼問題、給誰用、目前狀態。>

## 專案結構

<帶註解的目錄樹，每個目錄一句「放什麼」。產生的、棄用的、vendored 目錄要標明。>

## 架構

<分層表，依呼叫方向由上往下；位置寫到目錄層級即可，每層職責一句講清楚：>

| 層 | 位置 | 職責 |
|----|------|------|
| API 層 | `api/` | HTTP 路由、request 驗證、認證 |
| Service 層 | `service/` | 業務規則、前置檢查 |
| Repository 層 | `repository/` | 外部系統存取（真實與 mock 實作） |

<接著走一條最有代表性的 request 生命週期：進來、經過哪些檔案與函式、出去，
用真實符號名。流程相近的 endpoint 不逐一重走；真的不同的（例如兩段式操作）
在設計說明用一兩句講差異。endpoint 清單歸 README 與 openapi，不放這裡。
外部系統（資料庫、佇列、第三方）：用來做什麼、mock 實作在哪。>

## 內建工具

本 repo 提供下列可重用工具：

| 工具 | 位置 | 做什麼 | 什麼時候用 |
|------|------|--------|-----------|

<填表指引（不寫進文件）：目的是讓後人知道有現成工具、不會重寫一個。掃三個地方：
共用 helper 與基底類（error 類、response 包裝、身分提取）、scripts/ 下的獨立工具、
測試基建（fixture、mock、假資料）。只列會被重複用到的。位置寫檔名加符號名
（例：`main.py` 的 `flashback_error_handler`），不寫行號。語氣用正向陳述
（「提供」「可用於」），不對讀者下指令。>

## 開發

<跑起來、測試、lint 各一個 bash 區塊，可直接貼上執行，每塊附一行成功時的輸出。>

### 環境變數

| 名稱 | 預設 | 作用 |
|------|------|------|

## 設計說明

<行為規則與理由，逐條：錯誤回傳格式、認證與權限怎麼運作、重要預設值。
「看起來奇怪但是故意的」的地方：現象加原因，防後人改壞。>

<!-- 更新規則：動到目錄結構、資料流、行為規則的 PR 必須同步改本檔 -->
```

寫完做地標檢查，逐一驗證、不抽查（過期的地圖比沒有地圖更誤導）：

1. 文件裡每個 backtick 的路徑用 `ls` 確認存在。
2. 每個 backtick 的符號名、環境變數、錯誤碼用 `grep -rn` 確認 repo 裡找得到。
3. 行號引用一律不用，兩種寫法都算：「行 149」「line 42」與 `main.py:44`。機器掃：

```bash
grep -nE ':[0-9]+`|行 ?[0-9]+|line [0-9]+' docs/ARCHITECTURE.md
```

命中就改用符號名，零命中才算通過。

改寫既有文件時，原有內容裡正確的部分重組進範本各節（架構內容歸 ARCHITECTURE.md，
使用說明留給 Step 4 的 README）；與 code 對不上的內容當過期處理，改正或刪除。

## Step 3 —（僅 HTTP API）openapi.json

框架能離線匯出的（判準與各框架指令見
[references/frameworks.md](references/frameworks.md)）就匯出 `openapi.json`，
然後逐 operation 檢查完整度：

- 每個 operation 有 summary 或 description
- 每個參數有說明
- 錯誤狀態碼（4xx/5xx）有宣告與 schema
- response 有範例（`example` 或 `examples`）

缺的照 frameworks.md 的對照表回 code 補標註再重新匯出；不手改 openapi.json
（會被下次匯出蓋掉）。匯不出來的（框架不支援、要加依賴）先問使用者；
不匯就在 README 手寫 endpoint 表（Step 4），並在 ARCHITECTURE.md 設計說明註明。

## Step 4 —（僅對外元件）README.md

這份會整份上傳到文件平台，使用者只看得到這一份，所以單檔自足：不出現
「見 repo 某檔」式的引用，需要的內容直接寫進來。用字白話、用使用者會搜尋的詞。

風格是規格表，不是教學文：不寫 curl 指令、不寫 base URL（部署位置是環境的事），
每個功能寫清楚 `METHOD /path`、輸入、輸出、錯誤即可。JSON body 範例照給，
那是介面的一部分，只是不包在 curl 裡。

三個容易漏的地方：

- 每種輸入形式都要有範例：參數支援兩種指定方式（例如時間戳或 SCN）就給兩個
  request body 範例。
- 時間類參數寫明格式與時區（例如 ISO 8601、UTC），這是使用者第一個會問的。
- 專有狀態與術語第一次出現時用半句白話解釋（例：「FLASHBACKED（回溯完成、
  唯讀待驗證）」）。使用者看不到 code，文件裡每個名詞都要能在文件內讀懂。

範本：

```markdown
# <服務名>

<白話兩三句：這能幫你做什麼、什麼情況用得到。>

## 認證
<憑證放哪個 header（字面名）、怎麼取得、沒帶或帶錯會怎樣。>

## 功能一覽
| 動作 | Method | 路徑 | 說明 |
|------|--------|------|------|
| 查詢回收筒 | GET | `/query-recycle-bin` | 列出還救得回來的表 |

## <動作名>

<一個功能一個 H2 節，節名用功能一覽的「動作」欄、照表的順序，不把多個功能
合併成「某某管理」的大節——每節結構固定，讀者才能跳著讀。>

`METHOD /path` — <一句話：做什麼、什麼時候用>

**輸入**（無輸入寫「無」）：

| 參數 | 型態 | 必填 | 預設 | 說明 |
|------|------|------|------|------|

<支援多種輸入形式時，每種各給一個 request body JSON 範例。>

**輸出**：<response body JSON 範例，需要解釋的欄位逐條一句。>

**錯誤**：<此功能特有的錯誤（狀態碼、條件、怎麼辦）；只有共通錯誤就寫
「見錯誤與重試」。>

## 錯誤與重試（共通）
| HTTP | error_code | 意思 | 該怎麼辦 |
|------|-----------|------|---------|

## 限制與注意
<rate limit、已知限制、不支援的情況；沒有就寫「無」。>

---
架構與開發文件（repo 內）：`docs/ARCHITECTURE.md`
```

（末尾指路是給 repo 訪客的，上傳平台後多一行無害。照這個格式寫，
不用「見」「參考」等字眼，下面的自足檢查會擋。）

寫完跑三個檢查：

自足與風格檢查：

```bash
grep -nE '(\.\./|見 |參考 |see |curl |https?://)' README.md
```

命中內部引用就把內容直接寫進來；命中 curl 或 URL 就改成 `METHOD /path` 加
body 範例。命中數必須改到零，沒有例外——啟動指令、Swagger 位址這類內容屬於
ARCHITECTURE.md 的開發節，不屬於 README。末尾指路行不含這些 pattern，不會誤中。
grep 抓不到所有寫法，掃完再通讀一次，確認沒有任何地方要讀者去看 repo 內的檔案。

盤點完整性檢查（有 openapi.json 才適用）：README 的功能節數要等於 openapi 的
operation 總數。

```bash
grep -oE '"(get|post|put|delete|patch)":' openapi.json | wc -l
grep -cE '^\`(GET|POST|PUT|DELETE|PATCH) ' README.md
```

數字不相等表示漏寫或多寫了 endpoint（維運類端點是常見的漏網之魚）。刻意略去
某個 endpoint 時，在 Step 5 的「略去的節」點名它並說明原因。

錯誤碼覆蓋檢查（雙向）：code 裡回傳或 raise 的錯誤碼，README 要逐一寫到；
README 寫的錯誤碼也要在 code 裡 grep 得到，多出來的就是編造。pattern 與掃描目錄
都換成該 repo 的實際情況（pattern 如 `ORA-[0-9]+` 或 SCREAMING_SNAKE 常數）：

```bash
grep -rhoE 'ORA-[0-9]+' services/ repository/ models/ | sort -u   # code 有的
grep -oE 'ORA-[0-9]+' README.md | sort -u                          # 文件寫的
```

兩份清單要相等。文件裡的錯誤碼一律放 backtick，地標檢查會再驗一次。

## Step 5 — 事實抽查與回報

收尾前每項實際重跑、看到通過的輸出才算數：

- 各步檢查全部通過：地標檢查（含行號 grep）、README 自足與風格、盤點完整性、
  錯誤碼雙向、openapi 完整度（適用時）。
- glossary 禁用寫法掃描：glossary「文件裡怎麼寫」欄標明不用的變體逐一 grep
  兩份文件（例 `grep -nE '模擬模式|假資料模式|端點介面' README.md docs/ARCHITECTURE.md`，
  pattern 照 glossary 現況組），命中就改成 glossary 的寫法。
- 行為描述抽三條對回 code，優先抽容易寫反的：預設值、身分與權限、HTTP 動詞。
  逐字對回出處，對不上的就是想當然，回去修。

回報內容：產出檔案清單、待補清單（要問使用者的問題，沒有寫「無」）、
略去的節（哪些節不適用與原因，沒有寫「無」）。不產生額外的報告或摘要檔案。
