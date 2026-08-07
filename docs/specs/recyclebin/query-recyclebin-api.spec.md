# 回收筒查詢 API 規格書

## 1. 概述

本 API 供 DBA 查詢 Oracle 回收筒（RECYCLEBIN）中被 DROP 的表，判斷是否還能救回。支援查單一表或列出某 schema 內的全部被刪表。來源 SOP：`docs/sops/recyclebin/query-recyclebin.md`。限 DBA 使用。認證由部署環境 OAuth 機制統一處理（見第 4 節）。

## 2. 名詞定義

| 名詞 | 定義 | 系統判斷方式 |
|------|------|-----------|
| 回收筒 | Oracle RECYCLEBIN，被 DROP 的表在空間被回收前的暫存區 | 查詢 `dba_recyclebin` 視圖中 `type = 'TABLE'` 的紀錄 |
| 能救回 | 表對應的回收筒紀錄空間尚未被資料庫回收 | DBA_RECYCLEBIN 該筆紀錄的 CAN_UNDROP 欄位為 'YES' |

## 3. Endpoint 一覽

| Method | Path | 說明 | 風險 |
|--------|------|------|------|
| GET | `/recyclebin` | 查詢 schema 內的被刪表（可選指定單一表或列全部） | 查詢 |

## 4. 共通規範

**認證與授權**

認證與角色授權由部署環境的 OAuth 機制統一處理，不在本規格與實作範圍內，不自建 API key、不自行驗證角色。本 API 限 DBA 使用，作為部署時的授權設定需求。操作者身分取自 OAuth 認證結果；mock 模式與本機測試以 header `X-Operator` 模擬，缺席或去除空白後為空時記為 `unknown`。

**Request 與 response 格式**

- 時間欄位一律 ISO 8601 秒精度、UTC、無時區後綴（例 `2026-08-08T14:30:45`）；來源時間有微秒就截斷。
- boolean 欄位一律出現，不以 null 或缺席表示 false。
- 成功回應直接回資源內容，不包信封；清單用複數名詞作 key 裝陣列。
- 「最新」指掉進回收筒最晚的紀錄；drop_time 相同時，以 recyclebin_object_name 由大到小排序。

**錯誤格式**

所有 4xx/5xx 回應由統一的 exception handler 產出，格式如下。`error.code` 等於 HTTP 狀態碼；`error.status` 的值域見錯誤代碼總表；`message` 為人讀的簡述，程式判斷一律依據 `error.status`。

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

`details` 的形狀依 `error.status` 固定：欄位驗證失敗（422）用 `[{"fieldViolations": [{"field": "...", "description": "..."}]}]`（每個違規欄位一項），其餘用 `[{"reason": "...", "metadata": {}}]`。同一個 `error.status` 永遠用同一種形狀。Audit 不儲存 details 內容。

**錯誤代碼總表**

| error.status | HTTP | 條件 | 處置建議 |
|--------------|------|------|---------|
| INVALID_INPUT | 422 | schema 或 table_name 為空 | 檢查輸入，補全必填欄位 |
| SCHEMA_NOT_FOUND | 404 | schema 不存在 | 確認 schema 名稱是否正確 |
| DATABASE_CONNECTION_ERROR | 503 | 連不上 Oracle | 檢查資料庫連線，稍後重試 |
| DATABASE_TIMEOUT | 504 | Oracle 查詢逾時 | 檢查資料庫負載，稍後重試 |

## 5. GET /recyclebin

**說明**

查詢指定 schema 下回收筒內的被刪表。若提供 `table_name` 則查單一表，否則列出該 schema 回收筒內的全部表。查詢成功時，若表不在回收筒則回報「不在回收筒」，此情形不視為錯誤。

**Request**

| 欄位 | 型別 | 必填 | 預設 | 說明 |
|------|------|------|------|------|
| schema | string | 是 | — | 表所屬的 schema，大小寫不敏感 |
| table_name | string | 否 | — | 要查的表名（大小寫不敏感）；不提供時列出整個 schema 的回收筒內容 |

範例 1（查單一表）：
```http
GET /recyclebin?schema=scott&table_name=emp
```

範例 2（列全部）：
```http
GET /recyclebin?schema=scott
```

**處理流程**

1. **欄位驗證**：schema 經 str.strip() 後不為空 → 通過；否則回 422 INVALID_INPUT。JSON null 或未提供欄位視同缺席。
2. **條件驗證**：若提供 table_name，經 str.strip() 後不為空 → 通過；提供但為空（包括空字串）則回 422 INVALID_INPUT。
3. **Schema 存在性檢查**：查詢資料庫確認 schema 存在 → 通過；不存在回 404 SCHEMA_NOT_FOUND。
4. **回收筒查詢**：依 schema 與 table_name（如有）查詢 `dba_recyclebin`。同一表若被 DROP 多次、回收筒有多筆紀錄，取最新掉進回收筒的那一筆（以 DROPTIME 由新到舊，相同時以 recyclebin_object_name 字典序由大到小）。輸入的識別字（去除空白後）於系統內部轉為大寫後比對；回傳的表名為 Oracle 實際儲存值（大寫）。
5. **結果整理**：依查詢類型組裝 response。

**Response**

查單一表成功範例：
```json
{
  "in_recyclebin": true,
  "can_restore": true,
  "reason": ""
}
```

其他結果範例：
```json
{
  "in_recyclebin": false,
  "can_restore": false,
  "reason": ""
}
```

或：
```json
{
  "in_recyclebin": true,
  "can_restore": false,
  "reason": "SPACE_RECLAIMED"
}
```

列全部成功範例（按 drop_time 由新到舊排序）：
```json
{
  "tables": [
    {
      "original_table_name": "EMP",
      "recyclebin_object_name": "BIN$abc123==",
      "drop_time": "2026-08-08T14:30:45",
      "can_restore": true
    },
    {
      "original_table_name": "DEPT",
      "recyclebin_object_name": "BIN$def456==",
      "drop_time": "2026-08-08T13:20:10",
      "can_restore": false
    }
  ]
}
```

查單一表時欄位說明：

| 欄位 | 型別 | 說明 |
|------|------|------|
| in_recyclebin | boolean | 表是否在回收筒 |
| can_restore | boolean | 若在回收筒，能否救回 |
| reason | string | 不能救的原因代碼。只有一種：`SPACE_RECLAIMED`（空間已被資料庫回收）；能救或表不在回收筒時為空字串 |

列全部時欄位說明：

| 欄位 | 型別 | 說明 |
|------|------|------|
| tables | array | 回收筒內的表列表，由新到舊排序；空 schema 回空陣列 |
| original_table_name | string | 表的原始名稱，Oracle 實際儲存值（大寫） |
| recyclebin_object_name | string | 回收筒內的物件名（BIN$ 開頭，Oracle 自動命名） |
| drop_time | string | 表掉進回收筒的時間，ISO 8601 格式 |
| can_restore | boolean | 該表能否救回 |

**錯誤**

本 endpoint 適用的錯誤代碼：INVALID_INPUT、SCHEMA_NOT_FOUND、DATABASE_CONNECTION_ERROR、DATABASE_TIMEOUT。

**行為細節**

*冪等性*：相同 request 重複執行回傳相同結果（假設資料庫狀態不變）。

*並發*：兩個 request 同時查詢同一 schema 無防護需求，純讀取。

*執行中斷*：外部系統在查詢途中斷線或逾時，回傳 503 DATABASE_CONNECTION_ERROR 或 504 DATABASE_TIMEOUT；查詢結果算失敗，audit 記錄對應 error status。

*耗時與時間*：同步查詢，預期耗時秒級內（取決於回收筒大小）。查詢超過 30 秒時 Oracle 驅動將逾時，回傳 504。時間處理：截斷表示捨去小數部分，不進位；Oracle 回傳的時間視為 UTC，不做時區轉換。

## 6. Audit

除格式驗證失敗（422）外，每個 request 恰好記錄一筆 audit，包括被前置檢查擋下與基礎設施錯誤的情形。

| 欄位 | 型別 | 說明 |
|------|------|------|
| operation_id | string | 唯一識別符（UUID） |
| operator | string | 操作者身分。正式環境取自 OAuth 認證，忽略 X-Operator；僅 mock 模式讀 X-Operator header，缺席或去除空白後為空時記為 `unknown` |
| operation | string | 操作名稱，固定為 `recyclebin_query` |
| target | string | 操作對象：`<schema>` 或 `<schema>.<table_name>`（若有提供） |
| request_params | object | 原始請求參數：`{"schema": "...", "table_name": "..."}` |
| timestamp | string | request 處理完成時間，ISO 8601 格式 |
| result | string | 結果枚舉：`success` / `rejected:<error.status>` / `error:<error.status>` |
| error_status | string | 若 result 為 rejected 或 error，記錄對應的 error.status 值（純代碼，無前綴） |

result 的值域及 error_status 對應：
- `success`：操作成功（包括表不在回收筒的查詢成功情形）；error_status 空白
- `rejected:INVALID_INPUT`：422、`rejected:SCHEMA_NOT_FOUND`：404
- `error:DATABASE_CONNECTION_ERROR`：503、`error:DATABASE_TIMEOUT`：504

Audit 不儲存 details 內容。


## 7. 架構與實作要求

**三層架構**

- **API 層**：`api/recyclebin.py`，路由定義與 request 驗證。
- **Service 層**：`service/recyclebin_service.py`，業務規則（大小寫轉換、回收筒查詢邏輯、結果組裝）、前置檢查、audit 記錄。
- **Repository 層**：`repository/recyclebin_repository.py` 與 `repository/recyclebin_repository_mock.py`，Oracle 連線與查詢；mock 版本提供內記憶體實現，以 `MOCK_RECYCLEBIN` 環境變數切換。

**Repository 介面**

```python
class RecyclebinRepository:
    def schema_exists(self, schema: str) -> bool:
        """
        檢查 schema 是否存在。
        
        原始指令：SELECT COUNT(*) FROM DBA_USERS 
          WHERE USERNAME = UPPER(:schema)
        
        回傳 True 若 schema 存在。
        """
        pass
    
    def query_table_in_recyclebin(self, schema: str, table_name: str) -> dict | None:
        """
        查詢指定 schema 下、特定原始表名在回收筒內的紀錄。
        
        原始指令：SELECT object_name, DROPTIME, can_undrop 
          FROM dba_recyclebin 
          WHERE type = 'TABLE' 
          AND UPPER(owner) = UPPER(:schema) 
          AND UPPER(original_name) = UPPER(:table_name) 
          ORDER BY DROPTIME DESC, object_name DESC FETCH FIRST 1 ROW ONLY
        
        回傳 dict 包含 {
          'recyclebin_object_name': 'BIN$...',
          'drop_time': datetime（repository 轉換 DROPTIME 欄位為 drop_time key）,
          'can_undrop': 'YES'|'NO'
        }，或 None 若查無此表。
        """
        pass
    
    def list_tables_in_recyclebin(self, schema: str) -> list:
        """
        列出指定 schema 下回收筒內的全部表。
        
        原始指令：SELECT original_name, object_name, DROPTIME, can_undrop 
          FROM dba_recyclebin 
          WHERE type = 'TABLE' 
          AND UPPER(owner) = UPPER(:schema) 
          ORDER BY DROPTIME DESC, object_name DESC
        
        回傳 list of dict，每筆包含 {
          'original_table_name': '...（Oracle 實際儲存值，大寫）',
          'recyclebin_object_name': 'BIN$...',
          'drop_time': datetime（repository 轉換 DROPTIME 欄位為 drop_time key）,
          'can_undrop': 'YES'|'NO'
        }。空 schema 回 []。
        """
        pass
```

Repository 不擲業務錯誤；查無資源回 None 或 []；Oracle 連線/逾時擲 `InfraError(reason)` 其中 reason 為 `'connection'` 或 `'timeout'`。Service 層判定 404/503/504。Service 層檢查 can_undrop 欄位判斷能否救回：'YES' 表示能救，'NO' 表示不能救。

**Mock 實作**

初始資料用字面值列出，對齊測試案例：
- `schema_exists('scott')` 回 True；其餘 False
- `query_table_in_recyclebin('scott', 'emp')` 回 `{'recyclebin_object_name': 'BIN$abc123==', 'drop_time': datetime(2026,8,8,14,30,45), 'can_undrop': 'YES'}`
- `query_table_in_recyclebin('scott', 'emp')` 若標記為「已被回收」則 can_undrop='NO'
- `query_table_in_recyclebin('scott', 'nonexistent')` 回 None
- `list_tables_in_recyclebin('scott')` 回：
  ```python
  [
    {'original_table_name': 'EMP', 'recyclebin_object_name': 'BIN$abc123==', 'drop_time': datetime(2026,8,8,14,30,45), 'can_undrop': 'YES'},
    {'original_table_name': 'DEPT', 'recyclebin_object_name': 'BIN$def456==', 'drop_time': datetime(2026,8,8,13,20,10), 'can_undrop': 'YES'}
  ]
  ```
  或空 list（案例 7）

**環境變數**

| 名稱 | 預設值 | 合法範圍 | 讀取時機 |
|------|--------|---------|---------|
| `MOCK_RECYCLEBIN` | `false` | `true` 或 `false` | 應用啟動時 |
| `ORACLE_HOST` | 無 | 非空字串 | 應用啟動時（real 模式必填） |
| `ORACLE_PORT` | `1521` | 1–65535 | 應用啟動時 |
| `ORACLE_SERVICE_NAME` | 無 | 非空字串 | 應用啟動時（real 模式必填） |
| `ORACLE_USER` | 無 | 非空字串 | 應用啟動時（real 模式必填） |
| `ORACLE_PASSWORD` | 無 | 非空字串 | 應用啟動時（real 模式必填） |

**DI 與 Singleton**

用 `functools.lru_cache(maxsize=1)` provider 加 FastAPI `Depends`，repository 單例注入到 service，service 注入到路由。提供 `reset_singletons()` 函式供測試重設。

**啟動失敗條件**

- Real 模式（`MOCK_RECYCLEBIN=false`）且缺少任一 Oracle 連線設定。
- Real 模式下 Oracle 連線失敗（啟動時測試連線）。

## 8. 測試案例

| # | 情境 | 輸入 | 預期結果 |
|---|------|------|---------|
| 1 | 表在回收筒且能救 | GET `/recyclebin?schema=scott&table_name=emp` | 200，`in_recyclebin=true`、`can_restore=true`、`reason=''`、`original_table_name='EMP'` |
| 2 | 大小寫不敏感 | GET `/recyclebin?schema=scott&table_name=EMP` 與 `table_name=emp` | 兩者結果相同 |
| 3 | 表不在回收筒 | GET `/recyclebin?schema=scott&table_name=nonexistent` | 200，`in_recyclebin=false`、`can_restore=false` |
| 4 | 表在回收筒但無法救回 | GET `/recyclebin?schema=scott&table_name=emp` 其中 emp 空間已被回收 | 200，`in_recyclebin=true`、`can_restore=false`、`reason='SPACE_RECLAIMED'`、`original_table_name='EMP'` |
| 5 | Schema 不存在 | GET `/recyclebin?schema=nonexistent` | 404，SCHEMA_NOT_FOUND |
| 6 | 列全部，回收筒有多張表 | GET `/recyclebin?schema=scott`（不給 table_name），回收筒含 EMP 與 DEPT | 200，`tables` 陣列有兩筆（`original_table_name='EMP'`、`'DEPT'`），按 drop_time 由新到舊排序 |
| 7 | 列全部，回收筒為空 | GET `/recyclebin?schema=scott`（不給 table_name），回收筒無表 | 200，`tables=[]` |
| 8 | Schema 為空 | GET `/recyclebin?schema=` | 422，INVALID_INPUT |
| 9 | table_name 為空但已提供 | GET `/recyclebin?schema=scott&table_name=` | 422，INVALID_INPUT |
| 10 | 同一表被 DROP 多次 | GET `/recyclebin?schema=scott&table_name=emp`，回收筒有多筆同名紀錄 | 200，以最新那筆判斷，回傳其 can_restore 狀態 |
| 11 | Oracle 連線失敗 | 任意 request，monkeypatch repository 擲 InfraError(reason='connection') | 503，DATABASE_CONNECTION_ERROR |
| 12 | Oracle 逾時 | 任意 request，monkeypatch repository 擲 InfraError(reason='timeout') | 504，DATABASE_TIMEOUT |
| 13 | 時間格式驗證 | 查詢含 drop_time 的 response | 時間為 ISO 8601、秒精度、無微秒、無時區後綴（例 `2026-08-08T14:30:45`） |

## 9. 範圍外

- 查詢結果中的物件名本為 BIN$ 開頭的 Oracle 自動命名，功能上無需轉換或改名。
- 以時間點回溯表內容的 FLASHBACK 查詢功能是另一個操作，不在本 API 範圍。

## 10. 簽核

簽核本文件即同意 Endpoint 一覽的範圍（單一 GET endpoint）、共通規範的防護方式（OAuth 認證、統一錯誤格式、4 個錯誤代碼）與範圍外的保留項目。
