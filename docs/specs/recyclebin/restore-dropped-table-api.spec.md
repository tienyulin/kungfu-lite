# 表救回 API 規格書

## 1. 概述

本 API 供 DBA 從 Oracle 回收筒中救回誤刪的表。若原表名已被新建的表佔用，必須指定新表名以改名救回；否則以原名救回。執行前系統會檢查表的可救回性與表名衝突，救回的表保留 DROP 當下的內容。來源 SOP：`docs/sops/recyclebin/restore-dropped-table.md`。限 DBA 使用。認證由部署環境 OAuth 機制統一處理（見第 4 節）。本操作可逆：救回的表再 DROP 即回到回收筒。

## 2. 名詞定義

| 名詞 | 定義 | 系統判斷方式 |
|------|------|-----------|
| 回收筒 | Oracle RECYCLEBIN，被 DROP 的表在空間被回收前的暫存區 | 查詢 `dba_recyclebin` 視圖中 `type = 'TABLE'` 的紀錄 |
| 能救回 | 表對應的回收筒紀錄空間尚未被資料庫回收 | DBA_RECYCLEBIN 該筆紀錄的 CAN_UNDROP 欄位為 'YES' |
| 原名已被佔用 | 同 schema 內現有的表已使用了目標表的原始名稱 | 查詢 `dba_tables` 確認表名存在 |

## 3. Endpoint 一覽

| Method | Path | 說明 | 風險 |
|--------|------|------|------|
| POST | `/recyclebin/restore` | 救回被誤刪的表，支援改名 | 可逆 |

## 4. 共通規範

**認證與授權**

認證與角色授權由部署環境的 OAuth 機制統一處理，不在本規格與實作範圍內，不自建 API key、不自行驗證角色。本 API 限 DBA 使用，作為部署時的授權設定需求。

**Request 與 response 格式**

- 時間欄位一律 ISO 8601 秒精度、UTC、無時區後綴（例 `2026-08-08T14:30:45`）；來源時間有微秒就截斷。
- boolean 欄位一律出現，不以 null 或缺席表示 false。
- 成功回應直接回資源內容，不包信封。
- 可逆操作的 response 附復原方式說明。

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

`details` 的形狀依 `error.status` 固定：欄位驗證失敗（422）用 `[{"fieldViolations": [{"field": "...", "description": "..."}]}]`（每個違規欄位一項），其餘用 `[{"reason": "...", "metadata": {}}]`。同一個 `error.status` 永遠用同一種形狀。

**錯誤代碼總表**

| error.status | HTTP | 條件 | 處置建議 |
|--------------|------|------|---------|
| INVALID_INPUT | 422 | schema 或 table_name 為空 | 檢查輸入，補全必填欄位 |
| SCHEMA_NOT_FOUND | 404 | schema 不存在 | 確認 schema 名稱是否正確 |
| TABLE_NOT_IN_RECYCLEBIN | 404 | 表不在回收筒 | 確認表是否曾被 DROP；使用查詢 API 先確認 |
| TABLE_NOT_RESTORABLE | 409 | 表無法救回（空間已被回收等） | 查詢 API 確認 can_restore，若為 false 則無法救回 |
| TABLE_NAME_CONFLICT | 409 | 原名被佔用、未提供 new_table_name | 檢查原表名是否被現有的表佔用，若是請提供 new_table_name |
| NEW_TABLE_NAME_EXISTS | 409 | 新表名與現有的表同名 | 提供不同的 new_table_name |
| DATABASE_CONNECTION_ERROR | 503 | 連不上 Oracle | 檢查資料庫連線，稍後重試 |
| DATABASE_TIMEOUT | 504 | Oracle 操作逾時 | 檢查資料庫負載，稍後重試 |
| RESTORE_VERIFICATION_FAILED | 500 | 救回後驗證未通過（資料庫異常） | 人工檢查資料庫狀態後重試 |

## 5. POST /recyclebin/restore

**說明**

救回被誤刪的表。若原表名已被現有的表佔用，必須提供 `new_table_name` 以改名救回；否則以原名救回。執行前系統先檢查表是否在回收筒、能否救回、表名衝突。執行成功後，表出現在該 schema 內，回收筒紀錄消失。可通過再 DROP 該表回復到救回前的狀態。

**Request**

| 欄位 | 型別 | 必填 | 預設 | 說明 |
|------|------|------|------|------|
| schema | string | 是 | — | 表所屬的 schema（大小寫不敏感） |
| table_name | string | 是 | — | 原始表名（大小寫不敏感） |
| new_table_name | string | 否 | — | 改名救回時的新表名；原名未被佔用可不提供；大小寫不敏感，長度限制同 Oracle 表名 |

範例 1（以原名救回）：
```json
{
  "schema": "scott",
  "table_name": "emp"
}
```

範例 2（改名救回）：
```json
{
  "schema": "scott",
  "table_name": "emp",
  "new_table_name": "emp_restored"
}
```

**處理流程**

1. **欄位驗證**：schema 和 table_name 經 str.strip() 後皆不為空 → 通過；否則回 422 INVALID_INPUT。JSON null 或未提供欄位視同缺席。若提供 new_table_name，經 str.strip() 後不為空 → 通過；提供但為空（包括空字串）則回 422 INVALID_INPUT。

2. **Schema 存在性檢查**：查詢資料庫確認 schema 存在 → 通過；不存在回 404 SCHEMA_NOT_FOUND。

3. **回收筒存在性檢查**：查詢資料庫確認表在回收筒內 → 通過；不在回 404 TABLE_NOT_IN_RECYCLEBIN。同一表若被 DROP 多次、回收筒有多筆紀錄，定位最新掉進回收筒的那一筆（以 DROPTIME 由新到舊，相同時以 recyclebin_object_name 字典序由大到小）。輸入的識別字（去除空白後）於系統內部轉為大寫後比對；回傳的表名為 Oracle 實際儲存值（大寫）。

4. **可救回性檢查**：檢查回收筒紀錄的 CAN_UNDROP 欄位，確認為 'YES' → 通過；為 'NO' 回 409 TABLE_NOT_RESTORABLE，details 的 reason 為 `SPACE_RECLAIMED`。

5. **表名衝突檢查**：
   - 檢查原表名是否被現有的表佔用：
     - 未被佔用 → 通過；若提供 new_table_name 則忽略。
     - 被佔用 → 檢查是否提供 new_table_name：
       - 未提供 → 回 409 TABLE_NAME_CONFLICT。
       - 已提供 → 檢查 new_table_name 是否與該 schema 現有的表同名：
         - 不同名 → 通過。
         - 同名 → 回 409 NEW_TABLE_NAME_EXISTS。

6. **執行救回**：執行 Oracle FLASHBACK TABLE 指令。若需改名，指令為 `FLASHBACK TABLE <schema>."<recyclebin_object_name>" TO BEFORE DROP RENAME TO <UPPER(new_table_name)>`；否則 `FLASHBACK TABLE <schema>."<recyclebin_object_name>" TO BEFORE DROP`。RENAME TO 目標名不帶 schema 前綴，用轉大寫後的新名。此步驟前的所有檢查均通過、無副作用。

7. **驗證**：確認表在 schema 內查得到、回收筒內該筆紀錄已消失 → 操作成功。驗證未通過（FLASHBACK 未回報錯誤但表查不到或回收筒紀錄仍在，屬資料庫異常，正常情況不會發生）→ 回 500，error.status = RESTORE_VERIFICATION_FAILED。

**Response**

成功範例：
```json
{
  "restored_table_name": "EMP",
  "recyclebin_object_name": "BIN$abc123==",
  "restore_time": "2026-08-08T14:30:45"
}
```

改名救回成功範例：
```json
{
  "restored_table_name": "EMP_RESTORED",
  "recyclebin_object_name": "BIN$abc123==",
  "restore_time": "2026-08-08T14:30:45"
}
```

欄位說明：

| 欄位 | 型別 | 說明 |
|------|------|------|
| restored_table_name | string | 實際救回使用的表名（原名或新名），Oracle 實際儲存值（大寫） |
| recyclebin_object_name | string | 救回的表在回收筒內的原始物件名（BIN$ 開頭） |
| restore_time | string | FLASHBACK 執行成功、完成驗證時的系統時間，ISO 8601 格式 |

*復原方式*：救回的表已出現在 schema 內，可執行 `DROP TABLE <schema>.<restored_table_name>` 將其重新放入回收筒，達到救回前的狀態。

**錯誤**

本 endpoint 適用的錯誤代碼：INVALID_INPUT、SCHEMA_NOT_FOUND、TABLE_NOT_IN_RECYCLEBIN、TABLE_NOT_RESTORABLE、TABLE_NAME_CONFLICT、NEW_TABLE_NAME_EXISTS、DATABASE_CONNECTION_ERROR、DATABASE_TIMEOUT。

**行為細節**

*冪等性*：救回後該筆回收筒紀錄消失，再以相同參數執行會被擋下回 404 TABLE_NOT_IN_RECYCLEBIN；若原表隨後又被 DROP，則救回的是新紀錄，屬正常流程。

*並發*：兩個 request 同時救回同一表時，先執行者成功、後執行者被擋下回 404 TABLE_NOT_IN_RECYCLEBIN（回收筒紀錄已消失）。若執行 FLASHBACK 時該筆紀錄已被另一請求救走，Oracle 回錯誤，映射為 404 TABLE_NOT_IN_RECYCLEBIN。實作無額外並發防護，原因是 Oracle 的 FLASHBACK 操作原子性由資料庫保證，且回收筒紀錄唯一性由 Oracle 維護。

*執行中斷*：若 Oracle 在執行途中斷線或逾時，FLASHBACK 指令要嘛完全執行、要嘛完全未執行，不會停在中間狀態（由 Oracle 事務特性保證）。錯誤時回傳 503 DATABASE_CONNECTION_ERROR 或 504 DATABASE_TIMEOUT；DBA 可重新執行，系統會再次檢查表是否在回收筒、能否救回。

*耗時與時間*：sync 模式，預期耗時秒級內（取決於表大小與資料庫負載）。操作超過 60 秒時 Oracle 驅動將逾時，回傳 504。時間處理：截斷表示捨去小數部分，不進位；Oracle 回傳的時間視為 UTC，不做時區轉換。

## 6. 架構與實作要求

**三層架構**

- **API 層**：`api/recyclebin.py`，路由定義與 request 驗證。
- **Service 層**：`service/recyclebin_service.py`，業務規則（表名衝突判定、救回執行、驗證）與前置檢查順序。
- **Repository 層**：`repository/recyclebin_repository.py` 與 `repository/recyclebin_repository_mock.py`，Oracle 連線與操作；mock 版本提供內記憶體實現，以 `MOCK_RECYCLEBIN` 環境變數切換。

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
    
    def get_table_in_recyclebin(self, schema: str, table_name: str) -> dict | None:
        """
        查詢指定 schema 下、特定原始表名在回收筒內的最新紀錄。
        
        原始指令：SELECT object_name, DROPTIME, can_undrop 
          FROM dba_recyclebin 
          WHERE type = 'TABLE' 
          AND UPPER(owner) = UPPER(:schema) 
          AND UPPER(original_name) = UPPER(:table_name) 
          ORDER BY DROPTIME DESC, object_name DESC FETCH FIRST 1 ROW ONLY
        
        回傳 dict 包含 {
          'recyclebin_object_name': 'BIN$...',
          'drop_time': datetime（repository 負責將 Oracle 的 DROPTIME 欄位轉換為 drop_time key）,
          'can_undrop': 'YES'|'NO'
        }，或 None 若查無此表。
        """
        pass
    
    def table_exists(self, schema: str, table_name: str) -> bool:
        """
        檢查原表名是否被現有的表佔用。
        
        原始指令：SELECT COUNT(*) FROM dba_tables 
          WHERE UPPER(owner) = UPPER(:schema) AND UPPER(table_name) = UPPER(:table_name)
        
        回傳 True 若表存在。
        """
        pass
    
    def restore_table(self, schema: str, recyclebin_object_name: str, 
                     new_table_name: str | None = None) -> str:
        """
        執行 FLASHBACK TABLE 救回表，回傳實際救回的表名。
        
        若 new_table_name 為 None：
          原始指令：FLASHBACK TABLE <schema>."<recyclebin_object_name>" 
            TO BEFORE DROP
        
        若 new_table_name 不為 None（已轉大寫的標準識別字，無特殊字元）：
          原始指令：FLASHBACK TABLE <schema>."<recyclebin_object_name>" 
            TO BEFORE DROP RENAME TO <new_table_name>
          RENAME TO 目標不帶 schema 前綴、用轉大寫後的識別字、不加引號；
          本 API 不支援需引號的特殊字元表名（輸入含此類字元由 Oracle 執行時報錯）。
        
        回傳實際救回的表名（原名或新名，大寫）；基礎設施錯誤時擲 InfraError(reason) 其中 reason 為 'connection' 或 'timeout'。
        """
        pass
```

Repository 不擲業務錯誤；查無資源回 None 或 False；Oracle 連線/逾時擲 `InfraError(reason)` 其中 reason 為 `'connection'` 或 `'timeout'`。Service 層檢查 can_undrop 欄位判斷能否救回：'YES' 表示能救，'NO' 表示不能救（對應 409 TABLE_NOT_RESTORABLE）；判定 503/504。

**Mock 實作**

初始資料用字面值列出，對齊測試案例；每個方法的模擬行為：
- `schema_exists('scott')` 回 True；其餘 False
- `get_table_in_recyclebin('scott', 'emp')` 回 `{'recyclebin_object_name': 'BIN$abc123==', 'drop_time': datetime(2026,8,8,14,30,45), 'can_undrop': 'YES'}`
- 若測試案例標記 emp 無法救回，該方法回 `'can_undrop': 'NO'`
- `get_table_in_recyclebin('scott', 'nonexistent')` 回 None
- `table_exists('scott', 'emp')` 初始回 False；若需測試原名被佔用的情況，用 fixture 或 monkeypatch 改為 True
- `table_exists('scott', 'existing_table')` 回 True
- `restore_table('scott', 'BIN$abc123==', None)` 回 `'EMP'`（大寫）
- `restore_table('scott', 'BIN$abc123==', 'emp_restored')` 回 `'EMP_RESTORED'`（大寫）

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

## 7. 測試案例

| # | 情境 | 輸入 | 預期結果 |
|---|------|------|---------|
| 1 | 以原名救回 | POST，`schema=scott, table_name=emp`（不給 new_table_name），原名未被佔用 | 200，`restored_table_name='EMP'` |
| 2 | 改名救回 | POST，`schema=scott, table_name=emp, new_table_name=emp_restored`，原名被佔用 | 200，`restored_table_name='EMP_RESTORED'` |
| 3 | 表不在回收筒 | POST，`schema=scott, table_name=nonexistent` | 404，TABLE_NOT_IN_RECYCLEBIN |
| 4 | 救回後再執行 | POST，`schema=scott, table_name=emp`（已救回過、回收筒紀錄已消失） | 404，TABLE_NOT_IN_RECYCLEBIN |
| 5 | 原名被佔用、未提供新名 | POST，`schema=scott, table_name=emp`（不給 new_table_name），原名被佔用 | 409，TABLE_NAME_CONFLICT |
| 6 | 新表名衝突 | POST，`schema=scott, table_name=emp, new_table_name=existing_table`，新名與現有表同名 | 409，NEW_TABLE_NAME_EXISTS |
| 7 | 多筆同名紀錄 | POST，`schema=scott, table_name=emp`（被 DROP 多次、回收筒有多筆）| 200，救最新那一筆 |
| 8 | 表無法救回 | POST，`schema=scott, table_name=emp`，表在回收筒但空間已被回收 | 409，TABLE_NOT_RESTORABLE、details 的 reason=`SPACE_RECLAIMED` |
| 9 | Schema 不存在 | POST，`schema=nonexistent, table_name=emp` | 404，SCHEMA_NOT_FOUND |
| 10 | 大小寫不敏感 | POST，`schema=scott, table_name=EMP`（大寫）| 200、救回成功 |
| 11 | Schema 為空 | POST，`schema=, table_name=emp` | 422，INVALID_INPUT |
| 12 | table_name 為空 | POST，`schema=scott, table_name=` | 422，INVALID_INPUT |
| 13 | 救回成功後重複執行 | POST 同案例 1 的參數執行兩次 | 第一次 200 success，第二次 404 TABLE_NOT_IN_RECYCLEBIN |
| 14 | Oracle 連線失敗 | POST 任意 request，monkeypatch repository 擲 InfraError(reason='connection') | 503，DATABASE_CONNECTION_ERROR |
| 15 | Oracle 逾時 | POST 任意 request，monkeypatch repository 擲 InfraError(reason='timeout') | 504，DATABASE_TIMEOUT |
| 16 | 時間格式驗證 | POST 成功 request | response 中 restore_time 為 ISO 8601、秒精度、無微秒、無時區後綴 |
| 17 | 並發測試 | 兩個 thread/task 同時執行相同 POST request | 第一個 200 success，第二個 404 TABLE_NOT_IN_RECYCLEBIN |
| 18 | 驗證失敗（資料庫異常） | POST 成功，monkeypatch 使驗證查詢回「表不存在」（FLASHBACK 未報錯但表查不到） | 500，RESTORE_VERIFICATION_FAILED |

## 8. 範圍外

- 救回後 index、trigger、constraint 的名稱仍為 Oracle 自動命名的暫時名（BIN$ 開頭），功能正常但名稱不整齊；由 DBA 事後自行改名，不在本 API 範圍。
- 「以時間點回溯表內容」的 FLASHBACK 查詢功能是另一個操作，與回收筒救回無關。
- 事前備份、隔離層級、事務隔離等進階 Oracle 特性不在本 API 範圍。


