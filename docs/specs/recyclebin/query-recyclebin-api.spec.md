# 查詢回收筒 API 規格書

## 1. 概述

本 API 提供查詢 Oracle 回收筒內被誤刪表的能力。DBA 接到誤刪申請時，可用本 API 確認表是否還在回收筒、能否救回。亦可列出特定 schema 回收筒內的全部表以協助 DBA 判斷後續處理方案。本 API 只讀取資料，不做任何變更。來源 SOP：`docs/sops/recyclebin/query-recyclebin.md`。本 API 限 DBA 使用，認證與授權由部署環境的 OAuth 機制統一處理。

## 2. 名詞定義

| 名詞 | 定義 | 系統判斷方式 |
|---|---|---|
| 回收筒 | Oracle 的 RECYCLEBIN：被 DROP 的表在空間被回收前的暫存區，期間可救回 | 查詢 Oracle 系統表 `DBA_RECYCLEBIN`（TYPE='TABLE'） |
| 能救 | 回收筒紀錄的 CAN_UNDROP 欄位值為 'YES' | 檢查 DBA_RECYCLEBIN.CAN_UNDROP；為 'NO' 則無法救，一律對應 reason=SPACE_RECLAIMED |

## 3. Endpoint 一覽

| Method | Path | 說明 | 風險 |
|--------|------|------|------|
| GET | `/recyclebin/{schema}` | 列出 schema 回收筒內全部表 | 查詢 |
| GET | `/recyclebin/{schema}/table/{table_name}` | 查詢單一表是否在回收筒及能否救回 | 查詢 |

## 4. 共通規範

**認證與授權**

認證與角色授權由部署環境的 OAuth 機制統一處理，不在本規格與實作範圍內，不自建 API key、不自行驗證角色。本 API 限 DBA 使用，作為部署時的授權設定需求。

**Request 與 response 格式**
- 時間欄位一律 ISO 8601 秒精度、UTC、無時區後綴（例 `2026-08-08T14:30:45`）；來源時間有微秒就截斷（截斷＝捨去小數，不四捨五入）
- 欄位值去除前後空白（str.strip()，含 tab 與換行）後為空即視為空白，回 422 INVALID_INPUT
- boolean 欄位一律出現，不以 null 或缺席表示 false
- 成功回應直接回資源內容，不包信封；清單用複數名詞作 key 裝陣列
- 「最新」按 DROPTIME DESC, OBJECT_NAME DESC 排序（DROPTIME 同秒時以物件名字典序由大到小）
- 輸入參數大小寫不敏感（內部轉大寫比對），回傳的表名與物件名一律為 Oracle 實際儲存值（大寫）

**錯誤格式**

所有 4xx/5xx 回應由統一的 exception handler 產出，格式如下。`error.code` 等於 HTTP 狀態碼；`error.status` 的值域見錯誤代碼總表；`message` 為人讀的簡述，文字內容不屬於 API 契約；程式判斷一律依據 `error.status`。

```json
{
  "error": {
    "code": 409,
    "message": "說明文字",
    "status": "ERROR_CODE",
    "details": []
  }
}
```

`details` 的形狀依 `error.status` 固定：欄位驗證失敗（422）用 `[{"fieldViolations": [{"field": "...", "description": "..."}]}]`；其餘用 `[{"reason": "...", "metadata": {}}]`。同一個 `error.status` 永遠用同一種形狀。

**錯誤代碼總表**

| error.status | HTTP | 條件 | 處置建議 |
|--------------|------|------|---------|
| INVALID_INPUT | 422 | 必填欄位缺席或內容不符格式（例空白字串） | 檢查欄位填寫 |
| SCHEMA_NOT_FOUND | 404 | schema 不存在 | 確認 schema 名稱 |
| DATABASE_CONNECTION_ERROR | 503 | 連不上 Oracle | 稍後重試；若問題持續請聯絡系統管理員 |
| DATABASE_TIMEOUT | 504 | Oracle 查詢逾時 | 稍後重試；若問題持續請聯絡系統管理員 |

## 5. GET /recyclebin/{schema}

**說明**

列出指定 schema 回收筒內全部被誤刪的表。若回收筒為空回傳空清單。結果依 DROPTIME DESC, OBJECT_NAME DESC 排序，最新掉入的表排在前面。

**Request**

| 欄位 | 位置 | 型別 | 必填 | 說明 |
|---|---|---|---|---|
| schema | path | 文字 | 是 | 表所屬的 schema；不能為空白；大小寫不敏感 |

範例：
```
GET /recyclebin/scott
```

**處理流程**

1. 驗證 schema 欄位不為空白，否則回 422 INVALID_INPUT
2. 查詢該 schema 是否存在，不存在回 404 SCHEMA_NOT_FOUND
3. 查詢該 schema 回收筒內全部表，依掉入時間由新到舊排序
4. 組裝結果回傳

**Response**

成功回應範例：
```json
{
  "tables": [
    {
      "original_table_name": "EMP",
      "recyclebin_object_name": "BIN$abc123==$0",
      "drop_time": "2026-08-08T10:30:45",
      "can_restore": true
    },
    {
      "original_table_name": "DEPT",
      "recyclebin_object_name": "BIN$def456==$0",
      "drop_time": "2026-08-08T09:15:30",
      "can_restore": false
    }
  ]
}
```

| 欄位 | 型別 | 必出現 | 說明 |
|---|---|---|---|
| tables | 陣列 | 是 | 表清單，為空陣列時表示回收筒無內容 |
| original_table_name | 文字 | 是（表內） | 原表名（大寫） |
| recyclebin_object_name | 文字 | 是（表內） | 回收筒內的物件名（格式 BIN$...$0，Oracle 自動命名） |
| drop_time | ISO 8601 日期時間 | 是（表內） | 表掉入回收筒的時間 |
| can_restore | boolean | 是（表內） | 該表是否能被救回；false 表示 CAN_UNDROP='NO' |

**錯誤**

適用的錯誤代碼：INVALID_INPUT (422)、SCHEMA_NOT_FOUND (404)、DATABASE_CONNECTION_ERROR (503)、DATABASE_TIMEOUT (504)

**行為細節**

冪等性：同一 request 重複執行會取得相同結果（回收筒內容可能因其他操作而變化）。

## 6. GET /recyclebin/{schema}/table/{table_name}

**說明**

查詢單一表是否在回收筒及能否救回。表不在回收筒時回傳 `in_recyclebin: false`，此情況下 `can_restore` 為 false、`reason` 無值。若該表曾被 DROP 多次、回收筒有多筆同名紀錄，以最新的那一筆判斷；排序規則同列全部：DROPTIME 由新到舊，同秒時以 OBJECT_NAME 字典序由大到小。

**Request**

| 欄位 | 位置 | 型別 | 必填 | 說明 |
|---|---|---|---|---|
| schema | path | 文字 | 是 | 表所屬的 schema；不能為空白；大小寫不敏感 |
| table_name | path | 文字 | 是 | 要查詢的表名；不能為空白；大小寫不敏感 |

範例：
```
GET /recyclebin/scott/table/emp
GET /recyclebin/scott/table/EMP
```

**處理流程**

1. 驗證 schema 與 table_name 欄位都不為空白，否則回 422 INVALID_INPUT
2. 查詢該 schema 是否存在，不存在回 404 SCHEMA_NOT_FOUND
3. 在回收筒內查詢該表；若多筆同名紀錄取最新的一筆
4. 組裝結果回傳

**Response**

成功回應範例（表在回收筒且能救）：
```json
{
  "in_recyclebin": true,
  "can_restore": true,
  "reason": null
}
```

成功回應範例（表不在回收筒）：
```json
{
  "in_recyclebin": false,
  "can_restore": false,
  "reason": null
}
```

成功回應範例（表在回收筒但空間已被回收）：
```json
{
  "in_recyclebin": true,
  "can_restore": false,
  "reason": "SPACE_RECLAIMED"
}
```

| 欄位 | 型別 | 必出現 | 說明 |
|---|---|---|---|
| in_recyclebin | boolean | 是 | 表是否在回收筒 |
| can_restore | boolean | 是 | 能否救回；僅在 in_recyclebin 為 true 且 CAN_UNDROP='NO' 時為 false |
| reason | 文字或 null | 是 | 不能救的原因代碼；in_recyclebin 為 false 或能救時為 null。值域：SPACE_RECLAIMED |

**錯誤**

適用的錯誤代碼：INVALID_INPUT (422)、SCHEMA_NOT_FOUND (404)、DATABASE_CONNECTION_ERROR (503)、DATABASE_TIMEOUT (504)

**行為細節**

冪等性：同一 request 重複執行會取得相同結果（回收筒內容可能因其他操作而變化）。

## 7. 架構與實作要求

**三層式 FastAPI 結構**

- api（路由與驗證）→ service（業務規則、前置檢查）→ repository（外部系統存取，真實與 mock 兩種實作，以 `MOCK_ORACLE` 環境變數切換）
- 服務放 repo 根目錄下 `query-recyclebin-api/`

**Repository 介面表**

| 方法 | 參數 | 回傳 | 原始指令 |
|---|---|---|---|
| `find_table_in_recyclebin(schema: str, table_name: str) -> Optional[RecyclebinRecord]` | schema（大小寫不敏感）, table_name（大小寫不敏感） | 該表在回收筒最新的紀錄，或 None；紀錄含 original_table_name, recyclebin_object_name, droptime, can_undrop | `SELECT OWNER, OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP FROM DBA_RECYCLEBIN WHERE TYPE='TABLE' AND UPPER(OWNER)=UPPER(:schema) AND UPPER(ORIGINAL_NAME)=UPPER(:table_name) ORDER BY DROPTIME DESC, OBJECT_NAME DESC FETCH FIRST 1 ROW ONLY` |
| `list_tables_in_recyclebin(schema: str) -> list[RecyclebinRecord]` | schema（大小寫不敏感） | 該 schema 回收筒內全部表，按 DROPTIME DESC, OBJECT_NAME DESC 排序；清單為空表示回收筒無內容 | `SELECT OWNER, OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP FROM DBA_RECYCLEBIN WHERE TYPE='TABLE' AND UPPER(OWNER)=UPPER(:schema) ORDER BY DROPTIME DESC, OBJECT_NAME DESC` |
| `schema_exists(schema: str) -> bool` | schema（大小寫不敏感） | 該 schema 是否存在 | `SELECT 1 FROM DBA_USERS WHERE UPPER(USERNAME)=UPPER(:schema)` |

Repository 不擲業務錯誤——查無資源回 None 或空 list；404/409 由 service 判定。基礎設施錯誤擲 `InfraError(reason)`（reason 為 `connection` 或 `timeout`），service 對應 503。

**Mock 定義**

初始資料：
```python
# RecyclebinRecord 的 mock 初始資料
mock_data = {
    "scott": [
        {
            "original_table_name": "EMP",
            "recyclebin_object_name": "BIN$abc123==$0",
            "droptime": "2026-08-08T10:30:45",
            "can_undrop": "YES"
        },
        {
            "original_table_name": "DEPT",
            "recyclebin_object_name": "BIN$def456==$0",
            "droptime": "2026-08-08T09:15:30",
            "can_undrop": "NO"
        },
        {
            "original_table_name": "EMP",
            "recyclebin_object_name": "BIN$ghi789==$0",
            "droptime": "2026-08-07T14:00:00",
            "can_undrop": "YES"
        }
    ]
}
```

方法行為：
- `find_table_in_recyclebin("scott", "emp")` 回傳第一筆（最新）EMP 紀錄（can_undrop='YES'）
- `find_table_in_recyclebin("scott", "nonexistent")` 回傳 None
- `find_table_in_recyclebin("nonexistent", "emp")` 回傳 None
- `list_tables_in_recyclebin("scott")` 回傳 scott 的全部表，按 DROPTIME DESC, OBJECT_NAME DESC 排序
- `list_tables_in_recyclebin("nonexistent")` 回傳空 list
- `schema_exists("scott")` 回傳 True
- `schema_exists("nonexistent")` 回傳 False

**環境變數表**

| 名稱 | 預設值 | 合法範圍 | 讀取時機 | 說明 |
|---|---|---|---|---|
| `MOCK_ORACLE` | `false` | `true` 或 `false` | 應用啟動時 | 為 true 時使用 mock repository；false 時連接真實 Oracle |
| `ORACLE_HOST` | （必須設定）| 非空字串 | 應用啟動時；MOCK_ORACLE 為 false 時必填 | Oracle 伺服器地址 |
| `ORACLE_PORT` | `1521` | 1–65535 | 應用啟動時；MOCK_ORACLE 為 false 時使用 | Oracle 伺服器通訊埠 |
| `ORACLE_SID` | （必須設定）| 非空字串 | 應用啟動時；MOCK_ORACLE 為 false 時必填 | Oracle 服務識別符 |
| `ORACLE_USER` | （必須設定）| 非空字串 | 應用啟動時；MOCK_ORACLE 為 false 時必填 | Oracle 連接帳號 |
| `ORACLE_PASSWORD` | （必須設定）| 非空字串 | 應用啟動時；MOCK_ORACLE 為 false 時必填 | Oracle 連接密碼 |

**DI 與測試**

使用 `functools.lru_cache(maxsize=1)` provider 加 FastAPI `Depends` 提供 repository 單例；提供 `reset_singletons()` 供測試重設。Real 模式缺連線設定時啟動失敗。

**交付需附 README**

應含：
- mock 模式啟動指令
- endpoint 一覽（表格）
- 二到三個 curl 操作範例
- 環境變數表
- 測試執行方式

## 8. 測試案例

| # | 情境 | 輸入 | 預期結果 |
|---|------|------|---------|
| 1 | 查詢單一表，在回收筒且能救 | GET /recyclebin/scott/table/emp | 200；in_recyclebin=true、can_restore=true、reason=null |
| 2 | 查詢單一表，大小寫不敏感 | GET /recyclebin/scott/table/EMP 與 GET /recyclebin/scott/table/emp | 200；結果相同，original_table_name="EMP" |
| 3 | 查詢單一表，不在回收筒 | GET /recyclebin/scott/table/nonexistent | 200；in_recyclebin=false、can_restore=false、reason=null |
| 4 | 查詢單一表，在回收筒但空間已被回收 | GET /recyclebin/scott/table/dept | 200；in_recyclebin=true、can_restore=false、reason="SPACE_RECLAIMED" |
| 5 | 查詢單一表，schema 不存在 | GET /recyclebin/nonexistent/table/emp | 404；error.status=SCHEMA_NOT_FOUND |
| 6 | 列全部，回收筒有多張表 | GET /recyclebin/scott | 200；tables 陣列含 3 筆，依 DROPTIME DESC, OBJECT_NAME DESC 排序 |
| 7 | 列全部，回收筒為空 | 使用 mock 初始資料無該 schema 或該 schema 回收筒無資料 | 200；tables=[] |
| 8 | 列全部，schema 不存在 | GET /recyclebin/nonexistent | 404；error.status=SCHEMA_NOT_FOUND |
| 9 | schema 欄位為空白 | GET /recyclebin/ 或 GET /recyclebin/%20 | 422；error.status=INVALID_INPUT；fieldViolations 含 schema |
| 10 | table_name 欄位為空白 | GET /recyclebin/scott/table/ 或 GET /recyclebin/scott/table/%20 | 422；error.status=INVALID_INPUT；fieldViolations 含 table_name |
| 11 | 同一 request 重複執行 | 二次查詢 emp | 兩次回傳相同結果 |
| 12 | 同一表被 DROP 多次，回收筒多筆 | GET /recyclebin/scott/table/emp；mock 中該表有多筆紀錄 | 200；回傳最新紀錄（DROPTIME 最晚） |
| 13 | Oracle 連線失敗 | 正常請求但 repository 擲 InfraError(reason="connection") | 503；error.status=DATABASE_CONNECTION_ERROR |
| 14 | Oracle 查詢逾時 | 正常請求但 repository 擲 InfraError(reason="timeout") | 504；error.status=DATABASE_TIMEOUT |
| 15 | 驗證時間格式 | 任意回傳含時間的回應 | drop_time 格式為 ISO 8601 秒精度、無微秒、無時區後綴 |

## 9. 範圍外

- 查詢結果列出的物件名本來就是 BIN$ 開頭的 Oracle 自動命名，不需要處理或轉換
- 被刪表的救回功能由另一個 API 提供
