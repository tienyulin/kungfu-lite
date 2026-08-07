# 查詢回收筒 API Spec

> 來源 SOP：`docs/sops/recyclebin/query-recyclebin.md`

## 概述

提供 DBA 查詢 Oracle 回收筒（RECYCLEBIN）內的表及其救回狀態。支援查詢特定表或列舉某 schema 底下全部已刪除表，並判斷是否可以救回。每次查詢都會記錄操作者與結果，供後續追蹤。

## Endpoint 一覽

| Endpoint | 說明 | 風險 |
|----------|------|------|
| GET /recyclebin/tables | 查詢或列舉某 schema 回收筒內的表 | 🟢 查詢 |

## 典型情境

情境一「確認誤刪表的救回狀態」：
- Given DBA 收到救表申請單，需先確認該表是否還在回收筒
- When 呼叫 `GET /recyclebin/tables?schema=scott&table_name=emp`
- Then 回傳該表是否在回收筒、能否救回；查詢被記錄在 audit 日誌

情境二「檢視 schema 內全部已刪表」：
- Given DBA 接到申請單前先了解回收筒狀態
- When 呼叫 `GET /recyclebin/tables?schema=scott`（不給 table_name）
- Then 回傳該 schema 回收筒內全部表的清單（按刪除時間新到舊排列），包括原表名、回收筒內的物件名、刪除時間、救回狀態

情境三「查詢不存在的表（失敗情境）」：
- Given 表不在回收筒
- When 呼叫 `GET /recyclebin/tables?schema=scott&table_name=nonexistent`
- Then 回傳成功（不視為錯誤），明確標示表不在回收筒（in_recyclebin=false）

## 安全防護

- 僅 DBA 角色可使用；其他角色的請求於認證層直接拒絕（403）
- 每個查詢（含查詢失敗、結果為空）都留 audit 紀錄：操作者、查詢條件、時間、結果
- 本 API 不防護的事項：
  - 不驗證 schema 是否為真實存在的 schema；查詢不存在的 schema 會回傳「schema 不存在」但不擋請求
  - 不執行查詢結果的後續救回操作

## 人工保留項

| SOP 步驟 | 不自動化的原因 | API 提供的替代支援 |
|----------|---------------|-------------------|
| 基於查詢結果決定是否救回 | DBA 需要人工判斷風險與優先級 | 提供完整查詢結果（狀態、救回可行性、具體原因）供 DBA 決策 |

## 簽核

簽核本文件即同意「Endpoint 一覽」的範圍、「安全防護」的防護等級、「人工保留項」的保留項目。

---

## 規格

### §0 全域規則

#### 認證與授權

- 認證與角色授權由部署環境的 OAuth 機制統一處理，本 spec 與實作不自建 API key、不自行驗證角色
- SOP 限制「只有 DBA 能用」：部署時配置 OAuth 授權設定，僅允許 DBA 角色呼叫本 API；其他角色請求返 403
- 操作者身分（audit 的 actor）取自 OAuth 認證結果；mock 模式與本機測試以 header `X-Operator` 模擬，缺席或 `str.strip()` 後為空 → 記字面值 `"unknown"`

#### 閘門順序

```
（認證與授權在進入服務前由 OAuth 處理，見上節）
1. schema 驗證 → 422（pydantic：必填、型別、互斥輸入）
2. 資源解析    → 404（請求指到的 schema 不存在）
3. 風險閘門    → （本 endpoint 為查詢，無風險閘門）
4. 前置條件    → 409（領域狀態不允許）
5. 執行
```

dry_run 不適用於本 endpoint（純查詢）。

#### 統一 response 形狀

本專案全新，採用預設格式。

**HTTP 2xx（成功）**：直接回資源內容，無信封。
- 查詢單一表 → 平鋪欄位（in_recyclebin、can_restore、reason）
- 列全部表 → 複數名詞當 key 裝陣列：`{"tables": [...]}`

**HTTP 4xx/5xx**：根目錄唯一一個 `error` 鍵：
```json
{
  "error": {
    "code": <HTTP 狀態碼>,
    "message": "<簡述>",
    "status": "<大寫錯誤狀態字>",
    "details": [...]
  }
}
```

- `error.code` 等於 HTTP 狀態碼
- `error.status` 值域見 §6 錯誤表
- `details` 同一 error.status 永遠用同一形狀

#### 前置條件權威表

| PC 編號 | 條件 | HTTP | error.status |
|---------|------|------|--------------|
| PC-1 | schema 不能為空 | 422 | INVALID_ARGUMENT |
| PC-2 | 查單一表時 table_name 不能為空 | 422 | INVALID_ARGUMENT |
| PC-3 | schema 存在 | 404 | SCHEMA_NOT_FOUND |

#### 常數與佔位符

本 API 無 irreversible endpoint，不需 confirm token。

#### 型別與行為約定

- 時間欄位一律 ISO8601 秒精度 naive UTC（無微秒、無 Z、無時區後綴）；例：`2026-08-08T14:30:45`
- boolean 欄位一律出現，不以 null 或缺席表示 false（不使用 null 或缺席表達 false）
- `in_recyclebin` / `can_restore` 值只能是 true 或 false
- 大小寫不敏感：schema 與 table_name 輸入任意大小寫，系統內部統一轉為大寫查詢，結果中的 original_table_name 以原表實際大小寫回傳
- 排序穩定性（列全部時）：按 drop_time 由新到舊排列；drop_time 相同時按 recyclebin_object_name 字典序由大到小

### §1 Domain Model

#### 單一表查詢結果

| 欄位 | 型態 | 說明 |
|------|------|------|
| in_recyclebin | boolean | 表是否在回收筒內 |
| can_restore | boolean | 若 in_recyclebin=true 時是否可救回（對應 Oracle DBA_RECYCLEBIN.CAN_UNDROP = 'YES'）；若 in_recyclebin=false 則值固定為 false |
| reason | string \| null | 不可救回的原因（封閉值：`SPACE_RECLAIMED` = 空間已被資料庫回收）；can_restore=true 或 in_recyclebin=false 時值為 null |

#### 回收筒表清單項目

| 欄位 | 型態 | 說明 |
|------|------|------|
| original_table_name | string | 原始表名（大小寫同原表） |
| recyclebin_object_name | string | Oracle 在回收筒內的自動命名，以 `BIN$` 開頭 |
| drop_time | string (ISO8601) | 表掉進回收筒的時間，精度秒 |
| can_restore | boolean | 當前是否可救回 |

### §2 Endpoints 總表 ＋ 狀態機

| Method | Path | 風險 | AC 前綴 | SOP 章節 |
|--------|------|------|--------|---------|
| GET | /recyclebin/tables | 🟢 查詢 | QRT | 查詢回收筒 |

本 API 無狀態機（純查詢）。

### §3 各 endpoint 驗收準則

#### GET /recyclebin/tables

**Query Parameters:**

| 參數名 | 型態 | 必填 | 說明 |
|--------|------|------|------|
| schema | string | 是 | 欲查詢的 schema 名稱；不能為空或純空白；大小寫不敏感 |
| table_name | string | 否 | 特定表名；不指定時列全部表；指定時不能為空或純空白；大小寫不敏感 |

---

**AC-QRT-1：查詢單一表且在回收筒、可救回**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott&table_name=emp`，表在回收筒且可救回  
THE SYSTEM SHALL 回傳 200，response 欄位：
- `in_recyclebin`: true
- `can_restore`: true
- `reason`: null

```json
{
  "in_recyclebin": true,
  "can_restore": true,
  "reason": null
}
```

**AC-QRT-2：查詢單一表且在回收筒、不可救回**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott&table_name=emp`，表在回收筒但空間已被回收  
THE SYSTEM SHALL 回傳 200，response 欄位：
- `in_recyclebin`: true
- `can_restore`: false
- `reason`: "SPACE_RECLAIMED"

```json
{
  "in_recyclebin": true,
  "can_restore": false,
  "reason": "SPACE_RECLAIMED"
}
```

**AC-QRT-3：查詢單一表且不在回收筒**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott&table_name=nonexistent`  
THE SYSTEM SHALL 回傳 200（查無不視為錯誤），response 欄位：
- `in_recyclebin`: false
- `can_restore`: false
- `reason`: null

```json
{
  "in_recyclebin": false,
  "can_restore": false,
  "reason": null
}
```

**AC-QRT-4：大小寫不敏感查詢**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott&table_name=EMP`（大寫）與 `schema=SCOTT&table_name=emp`（小寫）  
THE SYSTEM SHALL 兩次回傳相同結果（系統內部統一查詢，但 original_table_name 欄位回傳原表實際大小寫）

**AC-QRT-5：列全部表（有資料）**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott`（不給 table_name），回收筒內有多張表  
THE SYSTEM SHALL 回傳 200，response 結構：
```json
{
  "tables": [
    {
      "original_table_name": "EMP",
      "recyclebin_object_name": "BIN$abcd1234",
      "drop_time": "2026-08-08T14:30:45",
      "can_restore": true
    },
    {
      "original_table_name": "DEPT",
      "recyclebin_object_name": "BIN$efgh5678",
      "drop_time": "2026-08-08T13:00:00",
      "can_restore": true
    }
  ]
}
```
- 按 drop_time 新到舊排列（最新的在前）；drop_time 相同時按 recyclebin_object_name 字典序由大到小
- 筆數等於回收筒內的表數

**AC-QRT-6：列全部表（無資料）**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott`，回收筒為空  
THE SYSTEM SHALL 回傳 200，response：
```json
{
  "tables": []
}
```

**AC-QRT-7：schema 不存在**

WHEN 呼叫 `GET /recyclebin/tables?schema=nonexistent`  
THE SYSTEM SHALL 回傳 404，error.status = `SCHEMA_NOT_FOUND`，message = "schema 不存在"

```json
{
  "error": {
    "code": 404,
    "message": "schema 不存在",
    "status": "SCHEMA_NOT_FOUND",
    "details": []
  }
}
```

**AC-QRT-8：schema 參數為空或純空白**

WHEN 呼叫 `GET /recyclebin/tables?schema=` 或 `schema=%20%20`  
THE SYSTEM SHALL 回傳 422，error.status = `INVALID_ARGUMENT`，details 標明 schema 欄位違反

```json
{
  "error": {
    "code": 422,
    "message": "schema 不能為空",
    "status": "INVALID_ARGUMENT",
    "details": [
      {
        "fieldViolations": [
          {
            "field": "schema",
            "description": "必填欄位"
          }
        ]
      }
    ]
  }
}
```

**AC-QRT-9：指定 table_name 但為空或純空白**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott&table_name=` 或 `table_name=%20%20`  
THE SYSTEM SHALL 回傳 422，error.status = `INVALID_ARGUMENT`，details 標明 table_name 欄位違反

```json
{
  "error": {
    "code": 422,
    "message": "table_name 不能為空",
    "status": "INVALID_ARGUMENT",
    "details": [
      {
        "fieldViolations": [
          {
            "field": "table_name",
            "description": "指定時不能為空"
          }
        ]
      }
    ]
  }
}
```

**AC-QRT-10：同一表被 DROP 多次、回收筒有多筆**

WHEN 呼叫 `GET /recyclebin/tables?schema=scott&table_name=emp`，emp 在回收筒內有多筆紀錄（多次 DROP）  
THE SYSTEM SHALL 以**最新**掉進回收筒的那一筆判斷狀態並回傳

**AC-QRT-11：Infrastructure 錯誤 — 連線失敗**

WHEN Oracle 連線失敗  
THE SYSTEM SHALL 回傳 503，error.status = `SERVICE_UNAVAILABLE`

```json
{
  "error": {
    "code": 503,
    "message": "連線失敗，請稍後重試",
    "status": "SERVICE_UNAVAILABLE",
    "details": [
      {
        "reason": "connection",
        "metadata": {}
      }
    ]
  }
}
```

**AC-QRT-12：Infrastructure 錯誤 — 查詢逾時**

WHEN Oracle 查詢逾時（>30 秒）  
THE SYSTEM SHALL 回傳 504，error.status = `GATEWAY_TIMEOUT`

```json
{
  "error": {
    "code": 504,
    "message": "查詢逾時，請稍後重試",
    "status": "GATEWAY_TIMEOUT",
    "details": [
      {
        "reason": "timeout",
        "metadata": {}
      }
    ]
  }
}
```

### §4 三層架構對應

#### 目錄結構

```
query-recyclebin-api/
├── main.py                 # FastAPI 應用入口、路由定義
├── models/
│   └── schemas.py         # Pydantic model、response 結構、常數定義
├── service/
│   └── recyclebin.py      # 業務邏輯、前置條件檢查、錯誤判定
├── repository/
│   └── oracle.py          # Oracle 連線、查詢 SQL
├── mock.py                # Mock 模式的 repository 實作
├── tests/
│   ├── conftest.py        # pytest 共用設定、fixture、環境變數預設
│   └── test_api.py        # 各 AC 對應測試
├── README.md              # 快速啟動、endpoint 一覽、curl 實走例、環境變數表
└── .env.example           # 環境變數範本
```

#### Repository 介面（Oracle 實作與 Mock 實作）

**方法簽名與 docstring（含完整原始指令）**

```python
class OracleRepository:
    """
    Oracle RECYCLEBIN 查詢實作
    """
    
    def schema_exists(self, schema: str) -> bool:
        """
        檢查 schema 是否存在
        
        原始 SQL：
          SELECT COUNT(*) FROM DBA_USERS WHERE USERNAME = UPPER(:schema)
        
        :param schema: schema 名稱（大小寫不敏感）
        :return: 存在返 True，否則 False
        :raises InfraError: 連線失敗或查詢逾時
        """
    
    def query_table_in_recyclebin(self, schema: str, table_name: str | None) -> RecyclebinQueryResult | list[RecyclebinTableRecord]:
        """
        查詢 Oracle 回收筒（DBA_RECYCLEBIN view）
        
        can_restore 判定：CAN_UNDROP = 'YES' 時回傳 True；反之 False
        
        原始 SQL 指令：
        - 查詢單一表（取最新的一筆）：
          SELECT OWNER, OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP 
          FROM DBA_RECYCLEBIN 
          WHERE OWNER = UPPER(:schema) AND UPPER(ORIGINAL_NAME) = UPPER(:table_name) AND TYPE = 'TABLE' 
          ORDER BY DROPTIME DESC, OBJECT_NAME DESC FETCH FIRST 1 ROW ONLY
        
        - 列全部表（按掉入時間由新到舊；同時間按 OBJECT_NAME 字典序由大到小）：
          SELECT OWNER, OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP 
          FROM DBA_RECYCLEBIN 
          WHERE OWNER = UPPER(:schema) AND TYPE = 'TABLE' 
          ORDER BY DROPTIME DESC, OBJECT_NAME DESC
        
        :param schema: schema 名稱（大小寫不敏感）
        :param table_name: 表名（若為 None 表示列全部；若指定則查單一表）
        :return: 若查單一表回傳 RecyclebinQueryResult（查無 → None）；列全部表回傳 list[RecyclebinTableRecord]（可為空 []）
        :raises InfraError: 連線失敗或查詢逾時（reason='connection' 或 'timeout'）
        """
```

**Repository 永不擲業務錯誤**：
- 表不在回收筒 → 查單一表回 None；列全部表回 []（由 service 回傳 in_recyclebin=false 或空清單，都是 200）
- Oracle 連線失敗 / 逾時 → 擲 `InfraError(reason='connection')` 或 `InfraError(reason='timeout')`
- schema 存在性由 service 透過呼叫 `schema_exists()` 方法進行獨立判定

#### Mock 初始狀態（§4 mock 定義）

```python
# mock.py

MOCK_RECYCLEBIN_DATA = {
    "SCOTT": {
        "EMP": {
            "recyclebin_object_name": "BIN$abcd1234efgh5678ijkl9012",
            "drop_time": "2026-08-08T14:30:45",
            "can_undrop": "YES"  # Oracle DBA_RECYCLEBIN.CAN_UNDROP 欄位值
        },
        "DEPT": {
            "recyclebin_object_name": "BIN$mnop3456qrst7890uvwx1234",
            "drop_time": "2026-08-08T13:00:00",
            "can_undrop": "YES"
        },
        "EMP_BACKUP": {
            "recyclebin_object_name": "BIN$xyza5678bcde9012fghi3456",
            "drop_time": "2026-08-08T12:00:00",
            "can_undrop": "NO"  # 空間已被回收，不可救回
        }
    }
}

class MockRepository:
    def schema_exists(self, schema: str) -> bool:
        """檢查 schema 是否存在（在本 mock 中固定檢查 SCOTT）"""
        return schema.upper() in MOCK_RECYCLEBIN_DATA
    
    def query_table_in_recyclebin(self, schema: str, table_name: str | None) -> ...:
        schema_upper = schema.upper()
        
        # schema 不存在時回 None（查單一表）或 []（列全部表）
        if schema_upper not in MOCK_RECYCLEBIN_DATA:
            return None if table_name else []
        
        schema_data = MOCK_RECYCLEBIN_DATA[schema_upper]
        
        # 列全部表
        if table_name is None:
            result = []
            for orig_name, record in sorted(
                schema_data.items(), 
                key=lambda x: x[1]["drop_time"], 
                reverse=True  # 按時間新到舊
            ):
                can_restore = record["can_undrop"] == "YES"
                result.append(RecyclebinTableRecord(
                    original_table_name=orig_name,
                    recyclebin_object_name=record["recyclebin_object_name"],
                    drop_time=record["drop_time"],
                    can_restore=can_restore
                ))
            return result
        
        # 查單一表
        table_upper = table_name.upper()
        if table_upper not in schema_data:
            return None  # 表不在回收筒
        
        record = schema_data[table_upper]
        can_restore = record["can_undrop"] == "YES"
        return RecyclebinQueryResult(
            in_recyclebin=True,
            can_restore=can_restore,
            reason="SPACE_RECLAIMED" if not can_restore else None
        )
```

### §5 設定

| 環境變數 | 預設值 | 合法範圍 | 讀取時機 | 說明 |
|---------|--------|---------|---------|------|
| `MOCK_QUERY_RECYCLEBIN` | `true` | `true` \| `false` | 啟動時 | 是否使用 mock 模式；true 時連接 mock repository，false 時連接真實 Oracle |
| `ORACLE_HOST` | （無） | 非空字串 | 啟動時 | Oracle 伺服器主機；MOCK=false 時必填 |
| `ORACLE_PORT` | `1521` | 正整數 | 啟動時 | Oracle 伺服器連線埠 |
| `ORACLE_SID` | （無） | 非空字串 | 啟動時 | Oracle database SID；MOCK=false 時必填 |
| `ORACLE_USER` | （無） | 非空字串 | 啟動時 | 連線使用者；MOCK=false 時必填 |
| `ORACLE_PASSWORD` | （無） | 非空字串 | 啟動時 | 連線密碼；MOCK=false 時必填 |
| `QUERY_TIMEOUT_SEC` | `30` | 正整數 | 啟動時 | 單一查詢的超時秒數 |

### §6 錯誤模型

| error_code | 條件 | HTTP | 前置條件編號 | 處置建議 |
|------------|------|------|------------|---------|
| INVALID_ARGUMENT | schema 或 table_name 為空或純空白 | 422 | PC-1、PC-2 | 檢查輸入值 |
| SCHEMA_NOT_FOUND | schema 不存在於 Oracle 中 | 404 | PC-3 | 確認 schema 名稱拼寫 |
| SERVICE_UNAVAILABLE | Oracle 連線失敗 | 503 | — | 檢查網路連線與 Oracle 狀態，稍後重試 |
| GATEWAY_TIMEOUT | 查詢耗時超過限制（30 秒） | 504 | — | 檢查 Oracle 狀態，調整查詢範圍或稍後重試 |

### §7 Audit

#### Schema

| 欄位 | 型態 | 說明 |
|------|------|------|
| operation_id | string (UUID) | 唯一操作識別碼，由系統自動生成 |
| operator | string | 操作者身分（來自 OAuth 認證或 X-Operator header） |
| operation | string | 操作類型：table_name 有給 → `QUERY_RECYCLEBIN`；未給 → `LIST_RECYCLEBIN` |
| timestamp | string (ISO8601) | 操作時間，秒精度 UTC |
| query_schema | string | 查詢的 schema |
| query_table_name | string \| null | 查詢的表名（若為 null 表示列全部） |
| result_status | string | `success` / `dry_run`（不適用此 API） / `rejected:<error.status>` / `error:<msg>` |
| error_status | string \| null | 若結果為失敗，記錄 error.status；否則為 null |
| rows_returned | integer | 結果筆數（查單一表時為 1 或 0；列全部時為實際筆數） |

#### 寫入時機

**規則**（照抄）：schema 驗證失敗（422）不留；其餘每個 request 恰好一筆。
- 包括：查詢成功、查無結果（in_recyclebin=false）、404、503、504

#### Result 封閉枚舉

本 endpoint 可能的 result 值：
- `rejected:<error.status>` 值域（封閉）：SCHEMA_NOT_FOUND、INVALID_ARGUMENT
- `error:<msg>` 格式（非封閉）：<msg> 為異常摘要字串，如 "connection timeout"、"query cancelled"；詳細異常資訊由 error.status 與 details 提供

| 值 | 情況 |
|-------|------|
| `success` | 查詢完成（含查無結果 in_recyclebin=false） |
| `rejected:SCHEMA_NOT_FOUND` | schema 不存在 |
| `rejected:INVALID_ARGUMENT` | 輸入驗證失敗 |
| `error:SERVICE_UNAVAILABLE` | Oracle 連線失敗 |
| `error:GATEWAY_TIMEOUT` | 查詢逾時 |

#### 儲存機制

- **Mock 模式**：repository 內記憶體 list（`MockRepository.audit_log: list[AuditRecord]`），測試可讀斷言
- **真實後端**：由使用者指定，本 spec 未定義——列入未決事項

### §8 測試計畫

#### 測試範疇

每條 AC ≥1 測試、測試名含 AC 編號；mock 狀態操縱；audit 各類 result 至少一次。

#### Conftest

```python
# tests/conftest.py

import os
import sys
from pathlib import Path

# 預設 mock 模式與 timeout 為 0（測試用）
os.environ.setdefault("MOCK_QUERY_RECYCLEBIN", "true")
os.environ.setdefault("QUERY_TIMEOUT_SEC", "0")

# 不依賴 cwd：把服務根目錄插進 sys.path
sys.path.insert(0, str(Path(__file__).parent.parent))

@pytest.fixture(autouse=True)
def reset_singletons():
    """重設單例（若有 DI singletons）"""
    # 實作參考 main.py 的 provider 定義
    pass
```

#### 測試案例範例

- AC-QRT-1 test_query_single_table_restorable
- AC-QRT-2 test_query_single_table_not_restorable
- AC-QRT-5 test_list_all_tables
- AC-QRT-7 test_schema_not_found
- AC-QRT-8 test_schema_empty
- AC-QRT-11 test_connection_failure
- Audit result 各類至少一次
- 時間格式驗證（無微秒、無時區後綴）

### §9 Out of Scope

| SOP 範圍外項目 | 原因 | API 替代支援 |
|---------------|------|------------|
| 查詢結果列出的物件名處理（BIN$ 開頭的 Oracle 自動命名） | Oracle 自動命名，本功能不需轉換 | API 回傳原汁原味的 recyclebin_object_name，供 DBA 後續操作使用 |
| 基於查詢結果決定是否救回 | DBA 人工判斷 | 提供完整查詢結果（狀態、救回可行性、原因詳細說明） |

### §10 實作交付要求

按本 spec 實作三層式 FastAPI 服務（api / service / repository），放在專案根下 `query-recyclebin-api/` 目錄。

#### 必附檔案

**README.md**：
- 快速啟動：mock 模式 `MOCK_QUERY_RECYCLEBIN=true python -m uvicorn main:app --reload`
- Endpoint 一覽表（引自概要）
- 2–3 個 curl 實走例：
  - 查詢單一表（在回收筒、可救回）
  - 列全部表
  - 查詢不存在的 schema（失敗例）
- 環境變數表、測試執行方式

**測試全綠**：`pytest` 直接跑全綠，不依賴 shell export 與 cwd

**實作中發現本 spec 未定義的行為 → 停下回報該處**，不自行發明。
