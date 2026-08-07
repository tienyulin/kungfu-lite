# Spec 模板

產出檔：見 SKILL.md「輸入 / 輸出 / 語言」（`docs/specs/<組名>/<sop-slug>-api.spec.md`，
非新佈局退回 `specs/`），結構 = 概要（六節）＋ 規格（§0–§10）。
**先寫概要** —— 寫不出概要代表你還沒讀懂 SOP。

**怎麼用這份模板**：標了「照抄」的區塊逐字複製進 spec；其餘各節照結構與要求填入
該 SOP 的內容。SOP 有未決事項時，spec 開頭加「未決事項」節（見 SKILL.md）。

**文件語氣**：spec 是一份正式文件——**文件裡不寫「給誰看」**（不出現「給審批者」
「給實作 agent」「Part A/B」這類讀者標籤或後設說明）。讀者分工只存在於本模板的
寫作指引：概要六節用日常語言（不用 EARS/JSON/狀態機術語），規格各節精確到零猜測——
成品讀起來就是一份文件。行文自然專業，像資深工程師寫的規格：技術名詞
（endpoint、request、response、header、mock、dry_run、audit、schema…）直接用英文，
敘述用該 SOP 的語言，不自創術語。

## 風險分級（Step 2 判定規則）

**照 SOP 原文判定，不做推理**：讀 SOP「做了之後能復原嗎」節——寫「能」→ `reversible`；
寫「不能／回不去」→ `irreversible`。**照抄該節結論，禁止以「從嚴」為由升級**
（升級會生出 SOP 沒要求的 confirm/審批流程，實作與審批兩頭皆錯；從嚴原則只適用於
SOP 未定義之處）。SOP 沒有這節才用下表判定；判定依據列入未決事項。

| 等級 | 判斷標準 | API 防護 |
|------|---------|---------|
| `read` 🟢 | 純查詢 | 無 |
| `reversible` 🟡 | 可被另一操作撤銷（SOP 有回退步驟） | `dry_run` 預設 `true`；執行 response 必含回退所需資訊（回退方法＋操作前狀態） |
| `irreversible` 🔴 | SOP 標示不可逆/需審批/警告 | `dry_run` 預設 `true` ＋ 必填 `confirm` 固定 token ＋ 必填 `approval_id`；缺一回 428 |

SOP 操作耗時數分鐘以上（停機、重啟、大量資料）→ 明定 sync 或 202+job 模式，寫出選擇理由。

---

## 概要（spec 前六節）

寫作要求（不寫進文件）：
- 全用日常語言，不用 EARS/JSON/狀態機術語。不懂技術的人讀完概要要能說出
  「這個 API 做什麼、最危險的操作是什麼、什麼情況會被擋」。
- 「典型情境」至少三個，必含風險最高操作的完整流程＋一個被擋下的失敗情境；
  SOP 全是 reversible 就用 reversible 示範，不要硬升級成不可逆。
- 「安全防護」最後一條列出本 API **不防護**的事（殘餘風險）——防護的邊界要明講。

骨架（照結構填，`<>` 換成內容）：

```markdown
# <名稱> API Spec

> 來源 SOP：<路徑>（<編號>）

## 概述

<三句話以內：這個 API 把哪份 SOP 的人工操作包成 API、可以用它做哪些事、給誰用。>

## Endpoint 一覽

| Endpoint | 說明 | 風險 |
|----------|------|------|
| GET /...  | 查詢 ○○ | 🟢 查詢 |
| POST /... | 執行 ○○，執行前先檢查 ○○ | 🟡 可逆 |
| POST /... | ○○，**執行後無法復原**，需要審批單號 | 🔴 不可逆 |

## 典型情境

情境一「<名稱>」：
- Given <現況>
- When 呼叫 <endpoint>（先以 dry_run 檢查，確認無誤後實際執行）
- Then <結果>，audit 留下紀錄

## 安全防護

- 會變更狀態的操作預設僅試算不執行（dry_run）
- 不可逆操作須同時提供固定確認字串與變更審批單號，缺一不執行
- 認證與授權由 OAuth 統一控管；<SOP 有角色限制時：僅 ○○ 角色可使用>
- 每個操作（含試算與被拒絕的 request）都留 audit 紀錄：操作者、時間、對象、結果
- 本 API 不防護的事項：<殘餘風險逐條>

## 人工保留項

| SOP 步驟 | 不自動化的原因 | API 提供的替代支援 |
|----------|---------------|-------------------|

## 簽核

簽核本文件即同意「Endpoint 一覽」的範圍、「安全防護」的防護等級、
「人工保留項」的保留項目。
```

## 規格（§0–§10）

概要之後接 `## 規格` 一節，底下 §0–§10 依序（`### §0 全域規則`…）。內容零猜測。

### §0 全域規則

#### 認證與授權（照抄進 spec，內容依 SOP 調整）

- 認證（401）與角色授權（403）由部署環境的 OAuth 機制統一處理，
  **不在本 spec 與實作範圍**——不自建 API key、不自行驗證角色。
- SOP 有「誰可以用」的限制 → 在本節照 SOP 原文列出允許角色，作為部署時的
  OAuth 授權設定需求。
- 操作者身分（audit 的 actor）取自 OAuth 認證結果（部署環境注入的身分資訊）；
  mock 模式與本機測試以 header `X-Operator` 模擬，缺席或 `str.strip()` 後為空
  → 記字面值 `"unknown"`。

#### 閘門順序（照抄進 spec，勿改寫）

```
（認證與授權在進入服務前由 OAuth 處理，見上節）
1. schema 驗證 → 422（pydantic：必填、型別、互斥輸入）
2. 資源解析    → 404（request 指到的資源不存在；dry_run 也 404）
3. 風險閘門    → 428（irreversible 且 dry_run=false：confirm/審批缺漏）
4. 前置條件    → 409（領域狀態不允許）
5. 執行
```

dry_run 的走法（照抄進 spec）：
- `dry_run=true`：跑 1–2（404 照常擲出）→ 閘門 4 的檢查**依序評估**，第一個沒過的 →
  對應 HTTP 碼＋error 物件（`error.status` = 該檢查的碼）；全過 → 2xx 回應含
  `"dry_run": true`。不進閘門 3、不執行。
- `dry_run=false`：reversible 過 1–2、4 後直接執行（閘門 3 只管 irreversible）；
  irreversible 過 1–2 後先過閘門 3 再 4、5。

#### 統一 response 形狀

**先選版**（寫 spec 前判定一次）：
- **既有專案**（目標 repo 已有 API 回傳慣例——看現有 endpoints、openapi、README）→
  **照舊格式**，把該格式完整定義進本節取代預設（例：既有慣例是
  `{"success": bool, "detail": <內容>}` 就照它寫死）。跟著舊格式是為了同一專案
  內一致；spec 仍要把形狀逐欄位寫死，維持零猜測。
- **全新專案／repo 無既有慣例** → 用下面的預設（照抄進 spec）。

預設——HTTP 2xx（成功，含 dry_run 通過）：**沒有信封**，直接回資源內容。
- 單一資源／操作結果 → 平鋪該 endpoint 的業務欄位（欄位由 §1/§3 定義）。
- 清單 → 複數名詞當 key 裝陣列，需要分頁時搭 `nextPageToken`：
  `{"<複數名詞>": [ {...}, ... ], "nextPageToken"?: str}`。
- 試算回應含 `"dry_run": true` 欄位；實際執行的回應**不帶**這個欄位。

HTTP 4xx/5xx（被擋、驗證失敗、錯誤——統一 exception handler 產出）：
根目錄**只有一個 `error` 鍵**，內部固定四欄位：

```json
{
  "error": {
    "code": <HTTP 狀態碼數字，例 409>,
    "message": "<簡述>",
    "status": "<大寫錯誤狀態字，例 NAME_CONFLICT / INVALID_ARGUMENT>",
    "details": [ <更具體的細節物件，可為空陣列> ]
  }
}
```

- `error.code` 一律等於 HTTP 狀態碼；`error.status` 值域＝§6 錯誤表的 error_code 欄
  （SOP 沒給碼的自訂 SCREAMING_SNAKE 並在 §6 宣告，spec 內一致）。
- `details` 兩種標準形，**同一個 error.status 永遠用同一形**：
  schema 驗證失敗（422）→
  `[{"fieldViolations": [{"field": "<欄位>", "description": "<原因>"}]}]`；
  其他 → `[{"reason": "<機器可讀原因>", "metadata": {<補充鍵值，無則空物件>}}]`。
- 前置條件編號 `PC-<n>`：**先列 PC 權威表**（本節或 §3 開頭：編號 → 條件 → HTTP →
  error.status → 評估順序），AC/§6/§7 才准引用——引用了表裡沒有的 PC-n = spec bug。
  response 不回逐條結果——dry_run 失敗回**第一個沒過的** PC 對應的 `error.status`。

#### 常數與佔位符

- 佔位符推導：`<系統>` = `<sop-slug>` 大寫蛇形（`deploy-checklist` →
  `MOCK_DEPLOY_CHECKLIST`），spec 裡直接寫展開後的字面值。
- irreversible endpoint 的 confirm token 給**字面值**：格式 `CONFIRM_<動作大寫蛇形>`
  （例 `CONFIRM_DROP_TABLESPACE`）。`approval_id` strip 後長度 > 0。confirm 缺席、值不符、
  approval_id 缺席都算閘門 3 失敗 → 428（schema 上兩者都是 `Optional[str] = None`，
  422 只管型別）。
- 常數與 audit 固定文案唯一出處：`models/schemas.py`。

#### 型別與行為約定

- 時間欄位一律 ISO8601 秒精度 naive UTC（無微秒、無 Z、無時區後綴）；bool 欄位永遠出現；
  比較性詞彙（最新、之內）給可計算定義**含平手規則**。
- DI：`functools.lru_cache(maxsize=1)` providers ＋ FastAPI `Depends`；測試 seam 提供
  `reset_singletons()`；`main.py` lifespan 呼叫一次 service provider warm-up，
  real 模式缺連線設定 → boot fail-hard。
- 同步模型與並發：明寫 sync/202 與理由、並發防護（狀態機擋 or 「未防護＋風險說明」）、
  冪等行為、**執行中途失敗語意**（外部系統在執行/輪詢途中斷線或逾時：回什麼 HTTP、
  狀態算什麼、audit result 記什麼——只定義「開始前」與「成功後」兩態的 spec 會讓
  實作者發明第三態）。

### §1 Domain Model
實體欄位與型別 → 直接變成 pydantic model 與 mock 狀態。

### §2 Endpoints 總表 ＋ 狀態機
| Method | Path | 風險 | AC 前綴 | SOP 章節 |

**AC 前綴 = 該 endpoint 2–4 個大寫字母縮寫**（自訂，例 `POST /flashback/drop` → `FD`），
在本表宣告即為權威，§3 沿用。

實體有 >1 狀態值 → 轉移表（目前狀態 × endpoint → 結果狀態；其他狀態下呼叫 → ?），
狀態檢查屬於哪個閘門要明寫（含刻意不對稱的理由）。

### §3 各 endpoint 驗收準則（EARS）

格式：`AC-<前綴>-<序號>: WHEN <條件> THE SYSTEM SHALL <可驗證行為>`
每個 endpoint 的 happy/edge/failure 三類缺一不可；request/response 給 JSON 區塊
（含範例值，照 §0 response 形狀）。寫每條 AC 時過一遍追問清單（references/checklists.md）。

### §4 三層架構對應

目錄樹 ＋ repository 介面表 ＋ mock 定義：

- repository 每個外部呼叫一個方法，docstring 寫**完整的原始指令字面值**（真實系統的
  實際語法，含查詢的 view/欄位名與排序鍵；不省略、不發明不存在的欄位名）。
- **repository 永不擲業務錯誤**——查無回空值/None，404/409 判定在 service。
- **基礎設施錯誤通道**（照抄進 spec）：「永不擲業務錯誤」**不含**基礎設施錯誤——
  連線失敗/逾時**不得**與「查無」共用 None（一個 None 載不動 503 與 504 兩種結果）。
  repository 擲 `InfraError(reason)`（reason ∈ `connection` / `timeout`），service 對應
  503 / 504；未列舉的基礎設施錯誤一律 → 503、`error.status` 自訂一個統一碼進 §6。
- mock：初始狀態給**具體字面值表**（與 AC 範例對齊），每個方法的模擬效果寫死
  （含解析類方法的換算公式）。

### §5 設定
環境變數表：預設值、合法範圍、**讀取時機**（boot 快取 or 每 request）。

### §6 錯誤模型
SOP 有故障排除表 → 整張搬入（error_code → 條件 → HTTP → 處置建議）。
沒有（checklist 型 SOP 常見）→ 從 SOP 散落的失敗描述與 Step 1 錯誤清單**自行整理**成
同格式的表。本表的 error_code 欄＝`error.status` 的完整值域；SOP 沒給碼的自訂
SCREAMING_SNAKE，前置條件對應的碼以 `PC-<n>` 編號對照（SOP 自帶步驟編號就用它，
沒有就自訂並在本表宣告，spec 內一致即可）。
**枚舉型欄位**（錯誤原因、狀態字…）的值域在 spec 裡**完整列舉**——寫「見某檔案」＝留白。

### §7 Audit
欄位 schema（含 operator、operation_id）、寫入時機（規則照抄：
**schema 驗證失敗（422）不留；其餘每個 request 恰好一筆**——read endpoint 也算，
含 404/409/428、5xx、dry_run。禁止另寫與此矛盾的句子）、result 封閉枚舉
`success` / `dry_run` / `rejected:<error.status>` / `error:<msg>`
（rejected 的完整值域**每個 endpoint 窮舉成表**，不留實作者自創格式的空間）、
各 operation 欄位對應表、audit 固定文案字面值（集中 `models/schemas.py`）。
儲存機制明寫：mock 模式 = repository 內記憶體 list（測試可讀斷言）；
真實後端由 SOP 或使用者指定，SOP 沒講就列入未決事項。

### §8 測試計畫

- 每條 AC ≥1 測試、測試名含 AC 編號；mock 狀態操縱類案例；audit 各類 result
  至少一次斷言；conftest autouse `reset_singletons()`。
- **hermetic**：conftest 開頭 `os.environ.setdefault` 設好 `MOCK_<系統>=true` 與
  delay/retry 類環境變數的 0 值（setdefault 不覆蓋外部指定；驗證 delay 行為的測試
  自行覆寫）——直接跑 `pytest` 就要全綠，不依賴 shell 先 export。
- **不依賴 cwd**：conftest 把服務根目錄插進 `sys.path`（`Path(__file__).parent.parent`），
  從 repo 根或服務目錄跑都要綠；同 repo 多個服務時 pytest 用 `--import-mode=importlib`
  並在 conftest 處理同名頂層模組（main/models/service/repository）的 sys.modules 衝突。
- **失敗案例（503/504）的測法**：monkeypatch 把 repository/provider 換成擲
  `InfraError(...)` 的假物件——「mock 模式測不到連線失敗/逾時」是誤解，不得留空殼測試。
- 時間格式至少一條斷言（回應時間戳無微秒、無時區後綴，對齊 §0）。

### §9 Out of Scope
SOP 不自動化的步驟（含 SOP「範圍外」節的內容）＋ 原因 ＋ API 替代支援
（與概要「人工保留項」一致，這裡可帶技術細節）。

### §10 實作交付要求
照本 spec 實作三層式 FastAPI（api / service / repository ＋ mock，`MOCK_<系統>=true`
可跑全部測試），服務放 repo 根下 `<sop-slug>-api/` 目錄。**必附 `README.md`**：
- 快速啟動：mock 模式一行起服務
- Endpoint 一覽表（可從概要帶）
- 2–3 個 curl 實走情境，必含風險最高操作的完整流程（dry_run → 實際執行）
- 環境變數表、怎麼跑測試

**實作中發現本 spec 未定義的行為 → 停下回報該處，修 spec 後再繼續；不得自行發明**
（未定義行為 = spec 的 bug，不是實作的自由度）。
