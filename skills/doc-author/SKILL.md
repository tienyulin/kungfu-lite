---
name: doc-author
description: 幫一個 repo 寫出「人與 AI 都讀得懂」的兩份文件 —— README.md（門面：API/工具怎麼用，單檔自足、可上傳文件平台）＋ docs/ARCHITECTURE.md（架構文件：AI 讀完不用重掃 repo 就能動工的系統地圖）。API repo 另附 openapi.json（從 code 匯出，不手抄）。新舊專案通用。Triggers - "寫 repo 文件"、"補 README"、"寫使用文件"、"寫 architecture 文件"、"author docs"、"fix my openapi"、"/doc-author"。
---

# doc-author

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 與 references 都沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] Step 1 認種類（偵察 repo，判定要產哪幾份）
- [ ] Step 2 docs/ARCHITECTURE.md 寫完＋地標檢查過
- [ ] Step 3（僅 API）openapi 匯出＋完整度檢查過
- [ ] Step 4（僅對外元件）README.md（使用文件）寫完＋自足檢查
- [ ] Step 5 事實溯源自查＋回報（含待補清單）
```

**內容原則：文件是事實，寫錯比寫少嚴重。** 內容只能來自 repo 可觀察事實（code、設定、
註解）或使用者親口提供；查無的細節在**正文原地**寫「（待補：<要問什麼>）」佔位，
**禁止發明一個像樣的值再標待補**（發明的 env 名看起來像真的，比空缺更毒），更**禁止用
「常見做法/合理假設」補**（例：來源寫「重試 2 次」就寫 2 次，不要腦補成指數退避）。

**範圍：本 skill 只建/改文件**（README、`docs/`、openapi.json）。
**絕不刪除、移動或修改 repo 的程式碼與其他檔案**（Step 3 的補標註是唯一例外，且要先徵求同意）。

**名詞一致性**：動筆前先讀
[references/glossary.md](references/glossary.md)（存在 `references/glossary/` 資料夾
就整個資料夾都讀）——文件裡用到表列名詞照它的定義與寫法；跟 repo 慣用講法衝突時
glossary 優先，並在文件裡註明 code 內的實際識別字。glossary 沒有的名詞才照
「領域詞在敘述裡順帶對應 code 識別字」規則自己處理。

## 心智模型：兩個讀者、兩份文件

| 文件 | 讀者 | 目的 | 什麼時候要 |
|------|------|------|-----------|
| `docs/ARCHITECTURE.md` | 維護者＋**AI agent** | 讀完建立心智模型直接動工，**不用重掃 repo** | 每個 repo 都要 |
| `README.md`（repo 根，門面） | 對外使用者（call API / 用工具的人） | 單檔自足的「怎麼用」，可整份上傳文件平台 | 有對外介面就是主角；純內部 library／純知識 repo → README 寫簡介＋指向 ARCHITECTURE.md 即可 |
| `openapi.json` | 使用者＋工具 | endpoint 權威細節 | 是 HTTP API 且框架能匯出才附（Step 3） |

## Step 1 — 認種類（先偵察，再決定產哪幾份）

讀 repo 找訊號：ASGI target（`app.main:app`）、`FastAPI(`、swagger 設定 → **API**；
crontab / k8s CronJob / Celery beat / CLI entrypoint → **會跑的非 API 元件**；
被 import 用的套件 → **library**；其餘散文 → **純知識**。

| 種類 | 產出 |
|------|------|
| HTTP API | README（使用文件）＋ docs/ARCHITECTURE.md ＋ openapi.json（可匯出時） |
| cronjob / worker / CLI | ARCHITECTURE.md（觸發、輸入輸出、副作用寫進對應節）；CLI 有外部使用者 → README 寫使用文件，否則 README 簡介＋指路 |
| library / 純內部 | ARCHITECTURE.md ＋ README 簡介＋指路 |
| 純知識 repo | ARCHITECTURE.md（架構節換成內容地圖）＋ README 簡介＋指路 |

monorepo（多服務同 repo）→ 各服務目錄各自一份 README＋docs/ARCHITECTURE.md，root README 只做
索引（一表：服務 → 一句話 → 路徑）。

## Step 2 — docs/ARCHITECTURE.md（架構文件：人與 AI 共讀）

**這是一份正常的工程架構文件**：核心是**這份 code 的架構**——分層、目錄、一個請求怎麼流過
系統、為什麼這樣設計。用工程師的日常用語寫（「專案結構」「設計說明」），不發明新框架、
不用自創術語當節名。人類工程師掃著讀要能懂；AI 讀完要能不重掃 repo 就動工。

寫作規則：
- **地標可驗證**：提到的路徑/符號/env 名一律寫真實字面值（**禁行號**——會爛），
  寫完照下方「地標檢查」逐一驗。
- **指令自己跑過才能寫**，每塊附一行「成功長怎樣」；跑不了（依賴壞、缺環境）就在
  該指令旁標「（待補：未驗證——<原因>）」——只在回報講、文件不標＝讀者不知道。
- **領域詞在架構敘述裡順帶對應到 code 識別字**（例：「回收筒（Oracle `RECYCLEBIN`）」），
  不另開對照表；讀者讀到哪、詞就解釋到哪。
- 設計說明寫「為什麼」不只寫「是什麼」——error 格式、權限、audit 這些行為規則，
  和「看起來奇怪但是故意的」的地方（防後人好心改壞）。
- 長度不設限，以「架構講清楚」為準；砍的是行銷語和廢話，不是事實。

範本（**節名與層級照抄**——含「環境變數」是「開發」底下的 `###`；不增節、不改層級，
不適用的節略去並在 Step 5 回報說明）：

```markdown
# <repo 名> — 架構

<開頭一段：這是什麼、解決什麼問題、給誰用、目前狀態。>

## 專案結構

<帶註解的目錄樹：每個目錄一句「放什麼」。產生的/棄用的/vendored 目錄要標明。>

## 架構

分層（表格照填，依呼叫方向由上往下；每層職責一句講清楚，不准只畫箭頭不解釋；
位置寫到**目錄層級**就好——重點是架構，不用點名個別 py 檔）：

| 層 | 位置 | 職責 |
|----|------|------|
| API 層 | `api/` | HTTP 路由、請求驗證、認證 |
| Service 層 | `service/` | 業務規則、前置檢查、審計 |
| Repository 層 | `repository/` | 外部系統存取（真實與 mock 實作） |

<接著：一個典型請求的生命週期：進來 → 經過哪些檔案/函式 → 出去（用真實符號名）——
**只挑一條最有代表性的走，不要每個 endpoint 各走一遍**（流程 pattern 都一樣，
一條就夠；endpoint 清單歸 README／openapi，不歸這裡）。某 endpoint 流程
真的不同（例：兩段式操作）→ 在設計說明用一兩句講差異，不另走全程。
外部系統（資料庫/佇列/第三方）：用來做什麼、mock 實作在哪。>

## 內建工具

本 repo 提供下列可重用工具：

| 工具 | 位置 | 做什麼 | 什麼時候用 |
|------|------|--------|-----------|

<給作者的填表指引（不要寫進文件）：這節的目的是讓後人（尤其 AI）知道有現成工具、
不會重寫一個。掃三個地方：共用 helper/基底類（error 類、response 包裝、身分提取…）、
`scripts/` 下的獨立工具、測試基建（fixture、mock、假資料）。只列會被重複用到的，
一次性內部函式不算。文件語氣用正向陳述（「提供」「可用於」），不要寫「別自己再寫」
這種對讀者下指令的句子。位置寫檔名＋符號名（例：`main.py` 的 `flashback_error_handler`），
不寫行號。>

## 開發

（跑起來 / 測試 / lint 各一個 bash 區塊，可直接貼上執行，每塊附一行「成功長怎樣」。）

### 環境變數

| 名稱 | 預設 | 作用 |
|------|------|------|

## 設計說明

<行為規則與其理由，逐條白話：錯誤回傳格式長怎樣、認證與權限怎麼運作、
操作紀錄（audit）記什麼、重要的預設值。
「看起來奇怪但是故意的」的地方：現象＋為什麼，防後人改壞。>

<!-- 更新規則：動到目錄結構、資料流、行為規則的 PR 必須同步改本檔 -->
```

**地標檢查（寫完必做，逐一驗證不准抽查）**——stale 地圖比沒地圖毒：

1. 文件裡每個 backtick 的**路徑** → `ls` 確認存在於 repo。
2. 每個 backtick 的**符號名／env 名／錯誤碼** → `grep -rn` 確認 repo 裡找得到（大小寫一致）。
3. **行號引用零容忍**——兩種寫法都禁：「行 149」「line 42」與 `main.py:44`。機器掃：

```bash
grep -nE ':[0-9]+`|行 ?[0-9]+|line [0-9]+' docs/ARCHITECTURE.md
```

命中＝有行號引用（會隨 code 改動爛掉），改用符號名；零命中才算過。

**Retrofit**：既有 README/架構文件裡正確的內容重組進範本節（架構內容歸 ARCHITECTURE.md、使用內容留給 Step 4 的 README）；
與 code 對不上的內容當 stale 處理（改正或刪）。

## Step 3 —（僅 HTTP API）openapi.json

框架能離線匯出（判準與各框架指令見
[references/frameworks.md](references/frameworks.md)）→ 匯出 `openapi.json`，
接著逐 operation 檢查完整度：

- 每個 operation 有 summary 或 description
- 每個參數有說明
- 錯誤狀態碼（4xx/5xx）有宣告＋schema
- response 有範例（`example`/`examples`）

缺的照 frameworks.md 的「缺漏 → 回 code 修哪」表**回 code 補標註再重匯**——
**絕不手改 openapi.json**（會被下次重匯蓋掉）。匯不出來（框架不支援、要加依賴）→
先問使用者；不匯就在 README 手寫 endpoints 表（Step 4），ARCHITECTURE.md 設計說明註明無 openapi。

## Step 4 —（僅對外元件）README.md（使用文件＝repo 門面）

**單檔自足**：這份會整份上傳文件平台，使用者只看得到這一份——禁止「見 repo 某檔」
式引用；需要的內容直接寫進來。用字白話、用使用者會搜尋的詞、不用內部代號。

**風格：規格表，不是 cookbook。** 不寫 curl 指令、不寫 base URL（部署在哪是環境的事，
使用者用什麼 client 是他的事）——每個功能寫清楚 `METHOD /path`、輸入、輸出、錯誤即可。
JSON body 範例照給（那是介面的一部分），只是不包在 curl 裡。

三條容易漏的（實測 user 卡住的點）：
- **每種輸入形式都要有範例**：參數支援兩種指定方式（例：時間戳或 SCN）就給兩個
  request body 範例，不要只示範其中一種。
- **時間類參數寫明格式與時區**（例：ISO 8601、UTC）——user 第一個會問的就是這個。
- **專有狀態/術語首次出現用半句白話解釋**（例：「FLASHBACKED（回溯完成、唯讀待驗證）」）
  ——user 看不到 code，文件裡的每個名詞都要能在文件內自己讀懂。

範本：

```markdown
# <服務名>

<白話 2–3 句：這能幫你做什麼、什麼情況用得到。>

## 認證
<憑證放哪個 header（字面名）、怎麼拿到、沒帶或帶錯會怎樣。>

## 功能一覽
| 動作 | Method | 路徑 | 說明 |
|------|--------|------|------|
| 查詢回收筒 | GET | `/query-recycle-bin` | 列出還救得回來的表 |

## <動作名>（**一個功能一個 H2 節**，節名＝功能一覽的「動作」欄、照表的順序；
不要把多個功能合併成「XX管理」類的大節——每節結構固定，讀者才能跳讀）

`METHOD /path` — <一句話做什麼、什麼時候用>

**輸入**（無輸入寫「無」）：

| 參數 | 型態 | 必填 | 預設 | 說明 |
|------|------|------|------|------|

<支援多種輸入形式時，每種給一個 request body JSON 範例。>

**輸出**：<response body JSON 範例＋需要解釋的欄位逐條一句。>

**錯誤**：<此功能特有的錯誤（狀態碼＋條件＋怎麼辦）；只有共通錯誤就寫「見錯誤與重試」。>

## 錯誤與重試（共通）
| HTTP | error_code | 意思 | 該怎麼辦 |
|------|-----------|------|---------|

## 限制與注意
<rate limit、已知怪現象、不支援的情況；沒有就「無」。>

---
架構與開發文件（repo 內）：`docs/ARCHITECTURE.md`
```

（末尾這行指路是給 repo 訪客的，上傳平台後多一行無害；格式照抄，不要用「見/參考」字眼——
自足檢查會擋。）

自足＋風格檢查（機器）：
`grep -nE '(\.\./|見 |參考 |see |curl |https?://)' README.md` ——
命中內部引用就把內容直接寫進來；命中 curl 或 URL＝違反規格表規則（不寫 curl、
不寫 base URL），改成 `METHOD /path`＋body 範例。**命中數必須改到 0——沒有任何
豁免條款，不准自行認定「這條可以留」**（啟動指令、Swagger 位址這類屬 ARCHITECTURE.md
開發節，不屬 README）。末尾指路行 `docs/ARCHITECTURE.md` 不含上述 pattern，
本來就不會命中。

**盤點完整性檢查（機器，有 openapi.json 才適用）**：README 的功能節數必須等於
openapi 的 operation 總數——

```bash
grep -oE '"(get|post|put|delete|patch)":' openapi.json | wc -l
grep -cE '^\`(GET|POST|PUT|DELETE|PATCH) ' README.md
```

兩個數字不相等＝漏寫或多寫了 endpoint（實測有 agent 漏掉 `GET /health` 還回報
「略去的節：無」）。真要略去某個 endpoint（例：純維運端點）→ 數字對不上時必須在
Step 5「略去的節」點名它＋原因。

**錯誤碼覆蓋檢查（機器，雙向）**：code 裡回傳/raise 的錯誤碼字面值，README 必須
逐一寫到；README 寫的錯誤碼也必須在 code 裡 grep 得到（編造即違反內容原則，退回修正）。例
（pattern 換成該 repo 的錯誤碼形式，如 `ORA-[0-9]+` 或 SCREAMING_SNAKE 常數）：

```bash
grep -rhoE 'ORA-[0-9]+' services/ repository/ models/ | sort -u   # code 有的
grep -oE 'ORA-[0-9]+' README.md | sort -u                          # 文件寫的
```

兩份清單必須相等——code 有文件沒有＝漏列（實測三個 agent 全漏，最慘 0/7）；
文件有 code 沒有＝編造（實測有 agent 發明了 5 個不存在的錯誤碼）。

## Step 5 — 事實溯源自查＋回報

收尾自查（**每項實際重跑，看到綠的輸出才算過**——聲稱過但工具紅著＝假勾）：

- 各步的檢查全綠：地標檢查（含行號 grep）、README 自足＋風格 grep、盤點完整性、
  錯誤碼雙向、openapi 完整度（適用時）。
- **glossary 禁用寫法掃描**：glossary「文件裡怎麼寫」欄標「不寫 X」的變體逐一 grep
  兩份文件（例 `grep -nE '預演|乾跑|乾執行|模擬模式|端點介面' README.md docs/ARCHITECTURE.md`），
  命中就改成 glossary 的寫法。
- **行為描述抽 3 條回對 code**（優先抽：預設值、身分/權限、HTTP 動詞這類容易寫反的），
  逐字對回出處——對不上的就是腦補，回去修（實測最常見：把 code 的 `'dev'` 寫成
  「空值」、把 GET 寫成 POST）。

回報：產出檔案清單＋「待補清單」（要問使用者的問題，逐條；沒有寫「無」）＋
「略去的節」（哪些節不適用＋一句原因；沒有寫「無」）。
