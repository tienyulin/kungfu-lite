# Spec 模板

產出檔：見 SKILL.md「輸入 / 輸出 / 語言」（`docs/specs/<組名>/<sop-slug>-api.spec.md`，
非新佈局退回 `specs/`），結構 = Part A（審批者）＋ Part B（實作 agent）。
**先寫 Part A** —— 寫不出白話摘要代表你還沒讀懂 SOP。

**怎麼用這份模板**：標了「照抄」的區塊逐字複製進 spec；其餘各節照結構與要求填入
該 SOP 的內容。SOP 有未決事項時，spec 開頭加「未決事項」節（見 SKILL.md）。

## 風險分級（Step 2 判定規則）

**先做機械判定**：讀 SOP「做了之後能復原嗎」節——寫「能」→ `reversible`；
寫「不能／回不去」→ `irreversible`。**照抄該節結論，禁止推理、禁止以「取更嚴」為由升級**
（升級會生出 SOP 沒要求的 confirm/審批流程，實作與審批兩頭皆錯；更嚴原則只適用於
SOP 未定義之處）。SOP 沒有這節才用下表判定；判定依據列入未決事項。

| 等級 | 判斷標準 | API 防護 |
|------|---------|---------|
| `read` 🟢 | 純查詢 | 無 |
| `reversible` 🟡 | 可被另一操作撤銷（SOP 有回退步驟） | `dry_run` 預設 `true`；執行 response 必含回退所需資訊（回退方法＋操作前狀態） |
| `irreversible` 🔴 | SOP 標示不可逆/需審批/警告 | `dry_run` 預設 `true` ＋ 必填 `confirm` 固定 token ＋ 必填 `approval_id`；缺一回 428 |

SOP 操作耗時數分鐘以上（停機、重啟、大量資料）→ 明定 sync 或 202+job 模式，寫出選擇理由。

---

## Part A — 審批摘要（白話，禁止 EARS/JSON/狀態機術語）

```markdown
# <名稱> API Spec

> 來源 SOP：<路徑>（<編號>）
> **Part A 給審批者（看完這節即可決定簽不簽）；Part B 給實作 agent。**

## A1. 這個 API 做什麼（三句話以內）
把 <SOP 名> 的人工操作包成 API：哪些事可以用它做、給誰用。

## A2. 端點一覽（白話）
| 端點 | 一句話說明 | 風險 |
|------|-----------|------|
| GET /...  | 查 ○○ | 🟢 查詢 |
| POST /... | 做 ○○，做之前會先檢查 ○○ | 🟡 可逆 |
| POST /... | ○○，**做了就回不去**，需要審批單號 | 🔴 不可逆 |

## A3. 三個典型情境（Given/When/Then 白話）
情境一「<名稱>」：
- Given <現況>
- When 呼叫 <端點>（先 dry_run 看檢查結果，再真的執行）
- Then <結果>，audit 留下紀錄

（至少三個，必含「風險最高的那個操作」的完整流程＋一個被擋下的失敗情境；
SOP 全是 reversible 就用 reversible 示範，不要硬升級成不可逆）

## A4. 安全防護（白話）
- 所有「會動到東西」的操作預設只試算不執行（dry_run）
- 不可逆操作要打兩個通關密語：固定確認字串 ＋ 變更審批單號，缺一不執行
- 每個操作（含試算、被拒絕的）都留審計紀錄：誰、何時、對什麼、結果
- 這個 API「不防護」的事（白話列出殘餘風險，例：兩個人同時操作不會互相擋、
  同步進度要自己回頭查）—— 讓審批者知道防護的邊界在哪

## A5. 不自動化的事（仍需人工）
| SOP 步驟 | 為什麼不自動化 | API 給的替代支援 |

## A6. 審批者簽核點
簽核這份 spec = 同意 A2 的端點範圍、A4 的防護等級、A5 的人工保留項。
```

## Part B — 實作規格（給 agent，零猜測）

### §0 全域規則

#### 閘門順序（照抄進 spec，勿改寫）

```
1.  auth       → 401（缺/錯 API key。SOP 有「誰可以用」限制的端點——不分 read/
                 mutation——一律要驗；只有「無任何權限限制」的純 read 端點可不驗）
1b. 角色檢查   → 403（僅當 SOP 有「誰可以用＋強制擋」；非授權角色一律 403。
                 dev 模式只免閘門 1，不免 1b。SOP 無權限限制 → 本閘門不存在）
2.  schema 驗證 → 422（pydantic：必填、型別、互斥輸入）
3.  資源解析    → 404（請求指到的資源不存在；dry_run 也 404）
4.  風險閘門    → 428（irreversible 且 dry_run=false：confirm/審批缺漏）
5.  前置條件    → 409（領域狀態不允許）
6.  執行
```

dry_run 的走法（照抄進 spec）：
- `dry_run=true`：跑 1–3（404 照常擲出）→ 閘門 5 檢查**依序評估**，第一個沒過的 →
  對應 HTTP 碼＋error 物件（`error.status` = 該檢查的碼）；全過 → 2xx 回應含
  `"dry_run": true`。不進閘門 4、不執行。
- `dry_run=false`：reversible 過 1–3、5 後直接執行（閘門 4 只管 irreversible）；
  irreversible 過 1–3 後先過閘門 4 再 5、6。

#### 統一 response 形狀

**先選版**（寫 spec 前判定一次）：
- **既有專案**（目標 repo 已有 API 回傳慣例——看現有 endpoints、openapi、README）→
  **照舊格式**，把該格式完整定義進本節取代預設（例：既有慣例是
  `{"success": bool, "detail": <內容>}` 就照它寫死）。跟著舊格式是為了同一專案
  內一致；spec 仍要把形狀逐欄位寫死，維持零猜測。
- **全新專案／repo 無既有慣例** → 用下面的預設（照抄進 spec）。

預設——HTTP 2xx（成功，含 dry_run 通過）：**沒有信封**，直接回資源內容。
- 單一資源／操作結果 → 平鋪該端點的業務欄位（欄位由 §1/§3 定義）。
- 清單 → 複數名詞當 key 裝陣列，需要分頁時搭 `nextPageToken`：
  `{"<複數名詞>": [ {...}, ... ], "nextPageToken"?: str}`。
- 試算回應含 `"dry_run": true` 欄位；真執行的回應**不帶**這個欄位。

HTTP 4xx/5xx（被擋、驗證失敗、錯誤——統一 exception handler 產出）：
根目錄**只有一個 `error` 鍵**，內部固定四欄位：

```json
{
  "error": {
    "code": <HTTP 狀態碼數字，例 409>,
    "message": "<白話簡述>",
    "status": "<大寫錯誤狀態字，例 NAME_CONFLICT / PERMISSION_DENIED / INVALID_ARGUMENT>",
    "details": [ <更具體的細節物件，可為空陣列> ]
  }
}
```

- `error.code` 一律等於 HTTP 狀態碼；`error.status` 值域＝§6 錯誤表的 error_code 欄
  （SOP 沒給碼的自編 SCREAMING_SNAKE 並在 §6 宣告，spec 內一致）。
- `details` 兩種標準形：參數驗證失敗（400/422）→
  `[{"fieldViolations": [{"field": "<欄位>", "description": "<原因>"}]}]`；
  其他 → `[{"reason": "<機器可讀原因>", "metadata": {<補充鍵值>}}]`，沒有就給 `[]`。
- 前置條件編號 `PC-<n>`：**先列 PC 權威表**（本節或 §3 開頭：編號 → 條件 → HTTP →
  error.status → 評估順序），AC/§6/§7 才准引用——引用了表裡沒有的 PC-n = spec bug。
  response 不回逐條結果——dry_run 失敗回**第一個沒過的** PC 對應的 `error.status`。

#### 身分與權限

- auth：header `X-API-Key` ↔ env `<SERVICE>_API_KEY`，`secrets.compare_digest` 比對；
  env **每 request 讀**，未設（env 不存在或空字串）= dev 模式不驗（僅免閘門 1）。
- SOP 有「誰可以用＋強制擋」→ 403 行為**必須定義**（error.status、AC、audit 記 rejected），
  不得蒸發成未決事項；只有「角色怎麼取得/驗證」的正式機制（SSO/LDAP/gateway）可列未決。
- 暫行身分/角色約定（照抄進 spec，別每份重新發明）：
  - 操作者身分（審計 actor 唯一來源）＝header `X-Operator`：字串、`str.strip()` 後
    1–128 字元，缺席或 strip 後為空 → 記字面值 `"unknown"`
  - 角色檢查用**獨立** header（例 `X-Operator-Role`），比對**逐字、區分大小寫**，
    缺席＝未授權 → 403。身分與角色是兩個 header，不得混用

#### 常數與佔位符

- 佔位符推導：`<SERVICE>`、`<系統>` = `<sop-slug>` 大寫蛇形（`deploy-checklist` →
  `DEPLOY_CHECKLIST_API_KEY`、`MOCK_DEPLOY_CHECKLIST`），spec 裡直接寫展開後的字面值。
- irreversible 端點的 confirm token 給**字面值**：格式 `CONFIRM_<動作大寫蛇形>`
  （例 `CONFIRM_DROP_TABLESPACE`）。`approval_id` strip 後長度 > 0。confirm 缺席、值不符、
  approval_id 缺席都算閘門 4 失敗 → 428（schema 上兩者都是 `Optional[str] = None`，
  422 只管型別）。
- 常數與審計固定文案唯一出處：`models/schemas.py`。

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

**AC 前綴 = 該端點 2–4 個大寫字母縮寫**（自訂，例 `POST /flashback/drop` → `FD`），
在本表宣告即為權威，§3 沿用。

實體有 >1 狀態值 → 轉移表（目前狀態 × 端點 → 結果狀態；其他狀態下呼叫 → ?），
狀態檢查屬於哪個閘門要明寫（含刻意不對稱的理由）。

### §3 各端點驗收準則（EARS）

格式：`AC-<前綴>-<序號>: WHEN <條件> THE SYSTEM SHALL <可驗證行為>`
每端點 happy/edge/failure 三類缺一不可；request/response 給 formal JSON 區塊
（含範例值，照 §0 response 形狀）。寫每條 AC 時過一遍逼問清單（references/checklists.md）。

### §4 三層落點

目錄樹 ＋ repository 介面表 ＋ mock 定義：

- repository 每個外部呼叫一個方法，docstring 寫**原始指令字面值**（真實系統的實際語法，
  含排序/選取鍵；別發明不存在的欄位名）。
- **repository 永不擲業務錯誤**——查無回空值/None，404/409 判定在 service。
- **基礎設施錯誤通道**（照抄進 spec）：「永不擲業務錯誤」**不含**基礎設施錯誤——
  連線失敗/逾時**不得**與「查無」共用 None（一個 None 載不動 503 與 504 兩種結果）。
  repository 擲 `InfraError(reason)`（reason ∈ `connection` / `timeout`），service 映射
  503 / 504；未列舉的基礎設施錯誤兜底 → 503、`error.status` 自編一個兜底碼進 §6。
- mock：初始狀態給**具體字面值表**（與 AC 範例對齊），每個方法的模擬效果寫死
  （含解析類方法的換算公式）。

### §5 設定
環境變數表：預設值、合法範圍、**讀取時機**（boot 快取 or 每 request）。

### §6 錯誤模型
SOP 有故障排除表 → 整張搬入（error_code → 條件 → HTTP → 處置建議）。
沒有（checklist 型 SOP 常見）→ 從 SOP 散落的失敗描述與 Step 1 錯誤清單**自行合成**
同格式的表。本表的 error_code 欄＝`error.status` 的完整值域；SOP 沒給碼的自編
SCREAMING_SNAKE，前置條件對應的碼以 `PC-<n>` 編號對照（SOP 自帶步驟編號就用它，
沒有就自編並在本表宣告，spec 內一致即可）。

### §7 審計
欄位 schema（含 operator＝X-Operator、operation_id）、寫入時機（規則照抄：
**401（閘門 1）與 422（閘門 2）一律不留；其餘每個 request 恰好一筆**——read 端點也算，
含 403、404/409/428、5xx、dry_run。禁止另寫與此矛盾的句子，例如「每 request 都留
（包括 401）」）、result 封閉枚舉 `success` / `dry_run` /
`rejected:<error.status>` / `error:<msg>`（rejected 的完整值域**每端點窮舉成表**，
不留實作者自創格式的空間）、各 operation 欄位對應表、審計固定文案字面值（集中
`models/schemas.py`）。儲存機制明寫：mock 模式 = repository 內記憶體 list
（測試可讀斷言）；真實後端由 SOP 或使用者指定，SOP 沒講就列入未決事項。

### §8 測試計畫

- 每條 AC ≥1 測試、測試名含 AC 編號；mock 狀態操縱類案例；audit 各類 result
  至少一次斷言；conftest autouse `reset_singletons()`。
- **hermetic**：conftest 開頭 `os.environ.setdefault` 設好 `MOCK_<系統>=true` 與
  delay/retry 類環境變數的 0 值（setdefault 不覆蓋外部指定；驗證 delay 行為的測試
  自行覆寫）——裸跑 `pytest` 就要全綠，不依賴 shell 先 export。
- **不依賴 cwd**：conftest 把服務根目錄插進 `sys.path`（`Path(__file__).parent.parent`），
  從 repo 根或服務目錄跑都要綠；同 repo 多個服務時 pytest 用 `--import-mode=importlib`
  並在 conftest 處理同名頂層模組（main/models/service/repository）的 sys.modules 衝突。
- **失敗案例（503/504）的測法**：monkeypatch 把 repository/provider 換成擲
  `InfraError(...)` 的假物件——「mock 模式測不到連線失敗/逾時」是誤解，不得留空殼測試。
- 時間格式至少一條斷言（回應時間戳無微秒、無時區後綴，對齊 §0）。

### §9 Out of Scope
SOP 不自動化步驟（含 SOP「範圍外／已知的怪現象」節的內容）＋ 原因 ＋ API 替代支援
（與 Part A5 一致，這裡可帶技術細節）。

### §10 實作交付要求
照本 spec 蓋三層式 FastAPI（api / service / repository ＋ mock，`MOCK_<系統>=true`
可跑全部測試），服務放 repo 根下 `<sop-slug>-api/` 目錄。**必附 `README.md`**：
- 快速啟動：mock 模式一行起服務
- 端點白話表（可從 Part A2 帶）
- 2–3 個 curl 實走情境，必含風險最高操作的完整流程（dry_run → 真執行）
- 環境變數表、怎麼跑測試

**實作中發現本 spec 未定義的行為 → 停下回報該處，修 spec 後再繼續；不得自行發明**
（未定義行為 = spec 的 bug，不是實作的自由度）。
