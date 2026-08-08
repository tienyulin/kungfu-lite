# 救回誤刪的表 API 規格書

## 1. 概述

本 API 提供從 Oracle 回收筒救回被誤刪表的能力。原表名未被新表佔用時以原名救回；被佔用時可指定新表名改名救回。執行前系統檢查表是否在回收筒、能否救回、表名有無衝突。救回的表為 DROP 當下的內容；index 與 trigger 會一併回來但名稱為 Oracle 自動命名的暫時名。來源 SOP：`docs/sops/recyclebin/restore-dropped-table.md`。本 API 限 DBA 使用，認證與授權由部署環境的 OAuth 機制統一處理。

## 2. 名詞定義

| 名詞 | 定義 | 系統判斷方式 |
|---|---|---|
| 回收筒 | Oracle 的 RECYCLEBIN：被 DROP 的表在空間被回收前的暫存區，期間可救回 | 查詢 Oracle 系統表 `DBA_RECYCLEBIN`（TYPE='TABLE'） |
| 能救 | 回收筒紀錄的 CAN_UNDROP 欄位值為 'YES' | 檢查 DBA_RECYCLEBIN.CAN_UNDROP；為 'NO' 則無法救 |

## 3. Endpoint 一覽

| Method | Path | 說明 | 風險 |
|--------|------|------|------|
| POST | `/recyclebin/{schema}/restore` | 救回 schema 內被誤刪的表 | 可逆 |

## 4. 共通規範

**認證與授權**

認證與角色授權由部署環境的 OAuth 機制統一處理，不在本規格與實作範圍內，不自建 API key、不自行驗證角色。本 API 限 DBA 使用，作為部署時的授權設定需求。

**Request 與 response 格式**
- 時間欄位一律 ISO 8601 秒精度、UTC、無時區後綴（例 `2026-08-08T14:30:45`）；來源時間有微秒就截斷（截斷＝捨去小數，不四捨五入）
- 欄位值去除前後空白（str.strip()，含 tab 與換行）後為空即視為空白，回 422 INVALID_INPUT
- boolean 欄位一律出現，不以 null 或缺席表示 false
- 成功回應直接回資源內容，不包信封
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
| INVALID_INPUT | 422 | 必填欄位缺席或內容不符格式 | 檢查欄位填寫 |
| SCHEMA_NOT_FOUND | 404 | schema 不存在 | 確認 schema 名稱 |
| TABLE_NOT_IN_RECYCLEBIN | 404 | 表不在回收筒 | 確認表是否已救回或不存在 |
| TABLE_NOT_RESTORABLE | 409 | 表無法救回（CAN_UNDROP='NO'） | 確認回收筒狀態；聯絡系統管理員 |
| TABLE_NAME_CONFLICT | 409 | 原名被佔用但未提供新表名，或新表名已存在 | 提供新表名或改用其他名稱 |
| DATABASE_CONNECTION_ERROR | 503 | 連不上 Oracle | 稍後重試；若問題持續請聯絡系統管理員 |
| DATABASE_TIMEOUT | 504 | Oracle 執行逾時 | 稍後重試；若問題持續請聯絡系統管理員 |

## 5. POST /recyclebin/{schema}/restore

**說明**

救回指定 schema 內被誤刪的表。若該表曾被 DROP 多次、回收筒有多筆同名紀錄，救回 DROPTIME 最新的那一筆。原表名未被現有表佔用時以原名救回；被佔用時必須指定新表名。救回後回收筒內該筆紀錄消失，同表若再被 DROP 後續可再次救回。

**Request**

| 欄位 | 位置 | 型別 | 必填 | 預設 | 說明 |
|---|---|---|---|---|---|
| schema | path | 文字 | 是 | — | 表所屬的 schema；不能為空白；大小寫不敏感 |
| table_name | body | 文字 | 是 | — | 原始表名；不能為空白；大小寫不敏感 |
| new_table_name | body | 文字 | 否 | — | 改名救回時的新表名；原名未被佔用可不提供；若提供不能為空白、不能與該 schema 現有表同名 |

範例（原名救回）：
```json
{
  "table_name": "emp"
}
```

範例（改名救回）：
```json
{
  "table_name": "emp",
  "new_table_name": "emp_restored"
}
```

**處理流程**

1. 驗證 schema 與 table_name 欄位不為空白，否則回 422 INVALID_INPUT
2. 查詢該 schema 是否存在，不存在回 404 SCHEMA_NOT_FOUND
3. 在回收筒內查詢該表；若多筆同名紀錄取 DROPTIME 最新的一筆；查不到回 404 TABLE_NOT_IN_RECYCLEBIN
4. 檢查該表能否救回（CAN_UNDROP='YES'），為 'NO' 回 409 TABLE_NOT_RESTORABLE
5. 表名衝突檢查：檢查原表名是否已被現有表佔用；若被佔用但未提供 new_table_name 回 409 TABLE_NAME_CONFLICT；若提供 new_table_name 則檢查新名是否與現有表同名，同名回 409 TABLE_NAME_CONFLICT
6. 執行救回：執行 Oracle 指令 `FLASHBACK TABLE <schema>.<original_table_name> TO BEFORE DROP RENAME TO <new_table_name>`（如不改名則省略 RENAME 子句；表名與新表名用轉大寫後的值）
7. 驗證：確認表在 schema 內查得到、回收筒內該紀錄已消失

**Response**

成功回應範例（原名救回）：
```json
{
  "restored_table_name": "EMP",
  "recyclebin_object_name": "BIN$abc123==$0",
  "restore_time": "2026-08-08T10:35:20"
}
```

成功回應範例（改名救回）：
```json
{
  "restored_table_name": "EMP_RESTORED",
  "recyclebin_object_name": "BIN$abc123==$0",
  "restore_time": "2026-08-08T10:35:20"
}
```

| 欄位 | 型別 | 必出現 | 說明 |
|---|---|---|---|
| restored_table_name | 文字 | 是 | 實際救回使用的表名（原名或新名，大寫） |
| recyclebin_object_name | 文字 | 是 | 該表在回收筒內的物件名（格式 BIN$...$0，Oracle 自動命名） |
| restore_time | ISO 8601 日期時間 | 是 | FLASHBACK 執行成功並完成驗證時的系統時間 |

復原方式：再次執行 `DROP TABLE <schema>.<restored_table_name>` 即可將表放回回收筒。

**錯誤**

適用的錯誤代碼：INVALID_INPUT (422)、SCHEMA_NOT_FOUND (404)、TABLE_NOT_IN_RECYCLEBIN (404)、TABLE_NOT_RESTORABLE (409)、TABLE_NAME_CONFLICT (409)、DATABASE_CONNECTION_ERROR (503)、DATABASE_TIMEOUT (504)

**行為細節**

冪等性：同一 request 重複執行時，首次執行成功後回收筒紀錄消失，第二次執行會被擋下並回 404 TABLE_NOT_IN_RECYCLEBIN。

並發：若兩個 request 同時救回同一表，因 Oracle FLASHBACK 指令在資料庫層有內部鎖定機制，會有一個執行成功、另一個執行時發現紀錄已消失而回 404 TABLE_NOT_IN_RECYCLEBIN。無需在應用層額外防護。

執行中斷：Oracle FLASHBACK 指令要嘛完成、要嘛未執行，不會停在中間狀態。若執行途中連線中斷或逾時，repository 擲 InfraError，service 回 503/504；DBA 重新執行同一 request 即可；系統會再次檢查表是否在回收筒。

## 6. 架構與實作要求

**三層式 FastAPI 結構**

- api（路由與驗證）→ service（業務規則、前置檢查）→ repository（外部系統存取，真實與 mock 兩種實作，以 `MOCK_ORACLE` 環境變數切換）
- 服務放 repo 根目錄下 `restore-dropped-table-api/`

**Repository 介面表**

| 方法 | 參數 | 回傳 | 原始指令 |
|---|---|---|---|
| `find_table_in_recyclebin(schema: str, table_name: str) -> Optional[RecyclebinRecord]` | schema（大小寫不敏感）, table_name（大小寫不敏感） | 該表在回收筒最新的紀錄，或 None；紀錄含 original_table_name, recyclebin_object_name, can_undrop | `SELECT OWNER, OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP FROM DBA_RECYCLEBIN WHERE TYPE='TABLE' AND UPPER(OWNER)=UPPER(:schema) AND UPPER(ORIGINAL_NAME)=UPPER(:table_name) ORDER BY DROPTIME DESC, OBJECT_NAME DESC FETCH FIRST 1 ROW ONLY` |
| `table_exists(schema: str, table_name: str) -> bool` | schema（大小寫不敏感）, table_name（大小寫不敏感） | 該表名在該 schema 內是否已存在 | `SELECT 1 FROM DBA_TABLES WHERE UPPER(OWNER)=UPPER(:schema) AND UPPER(TABLE_NAME)=UPPER(:table_name)` |
| `restore_table(schema: str, original_table_name: str, new_table_name: Optional[str]) -> tuple[str, str, str]` | schema、original_table_name、new_table_name（若改名）；皆大小寫不敏感 | 回傳 (restored_table_name, recyclebin_object_name, restore_time)；restore_time 為 ISO 8601 秒精度字串 | `FLASHBACK TABLE <schema>.<original_table_name> TO BEFORE DROP [RENAME TO <new_table_name>]` |
| `schema_exists(schema: str) -> bool` | schema（大小寫不敏感） | 該 schema 是否存在 | `SELECT 1 FROM DBA_USERS WHERE UPPER(USERNAME)=UPPER(:schema)` |

Repository 不擲業務錯誤——查無資源回 None 或 False；404/409 由 service 判定。基礎設施錯誤擲 `InfraError(reason)`（reason 為 `connection` 或 `timeout`），service 對應 503。

**Mock 定義**

初始資料：
```python
# RecyclebinRecord 的 mock 初始資料
mock_recyclebin = {
    "scott": [
        {
            "original_table_name": "EMP",
            "recyclebin_object_name": "BIN$abc123==$0",
            "can_undrop": "YES"
        },
        {
            "original_table_name": "DEPT",
            "recyclebin_object_name": "BIN$def456==$0",
            "can_undrop": "NO"
        }
    ]
}

# 現有表清單的 mock 初始資料
mock_existing_tables = {
    "scott": ["EXISTING_TABLE", "DEPT"]
}
```

方法行為：
- `find_table_in_recyclebin("scott", "emp")` 回傳 EMP 紀錄（can_undrop='YES'）
- `find_table_in_recyclebin("scott", "nonexistent")` 回傳 None
- `find_table_in_recyclebin("scott", "dept")` 回傳 DEPT 紀錄（can_undrop='NO'）
- `table_exists("scott", "existing_table")` 回傳 True（大小寫不敏感）
- `table_exists("scott", "emp")` 回傳 False（已救回過）
- `table_exists("scott", "nonexistent")` 回傳 False
- `restore_table("scott", "emp", None)` 移除 EMP 紀錄，回傳 ("EMP", "BIN$abc123==$0", restore_time)；restore_time 回當下系統時間（ISO 8601 秒精度）
- `restore_table("scott", "emp", "emp_restored")` 移除 EMP 紀錄，回傳 ("EMP_RESTORED", "BIN$abc123==$0", restore_time)；restore_time 回當下系統時間（ISO 8601 秒精度）
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
- 二到三個 curl 操作範例（含改名與不改名）
- 環境變數表
- 測試執行方式

## 7. 測試案例

| # | 情境 | 輸入 | 預期結果 |
|---|------|------|---------|
| 1 | 救回表，原名未被佔用 | POST /recyclebin/scott/restore；body: {table_name: "emp"} | 200；restored_table_name="EMP"、recyclebin_object_name="BIN$abc123==$0" |
| 2 | 救回表，改名救回 | POST /recyclebin/scott/restore；body: {table_name: "emp", new_table_name: "emp_restored"} | 200；restored_table_name="EMP_RESTORED"、recyclebin_object_name="BIN$abc123==$0" |
| 3 | 救回表，表不在回收筒 | POST /recyclebin/scott/restore；body: {table_name: "nonexistent"} | 404；error.status=TABLE_NOT_IN_RECYCLEBIN |
| 4 | 救回表，原名被佔用但未提供新名 | POST /recyclebin/scott/restore；body: {table_name: "existing_table"}；EXISTING_TABLE 已存在 | 409；error.status=TABLE_NAME_CONFLICT |
| 5 | 救回表，新名與現有表同名 | POST /recyclebin/scott/restore；body: {table_name: "emp", new_table_name: "existing_table"}；EXISTING_TABLE 已存在 | 409；error.status=TABLE_NAME_CONFLICT |
| 6 | 救回表，空間已被回收 | POST /recyclebin/scott/restore；body: {table_name: "dept"}；DEPT 的 can_undrop='NO' | 409；error.status=TABLE_NOT_RESTORABLE |
| 7 | 救回表，schema 不存在 | POST /recyclebin/nonexistent/restore；body: {table_name: "emp"} | 404；error.status=SCHEMA_NOT_FOUND |
| 8 | table_name 欄位為空白 | POST /recyclebin/scott/restore；body: {table_name: ""} | 422；error.status=INVALID_INPUT；fieldViolations 含 table_name |
| 9 | schema 欄位為空白 | POST /recyclebin//restore；或 path 中 schema 為 %20 | 422；error.status=INVALID_INPUT；fieldViolations 含 schema |
| 10 | 大小寫不敏感 | POST /recyclebin/scott/restore；body: {table_name: "EMP"} | 200；restored_table_name="EMP" |
| 11 | 冪等性測試 1 | 二次執行相同 request | 第一次 200；第二次 404 TABLE_NOT_IN_RECYCLEBIN |
| 12 | 同一表被 DROP 多次，回收筒多筆 | POST /recyclebin/scott/restore；mock 中 EMP 有多筆紀錄 | 200；救回 DROPTIME 最新紀錄 |
| 13 | Oracle 連線失敗 | 正常請求但 repository 擲 InfraError(reason="connection") | 503；error.status=DATABASE_CONNECTION_ERROR |
| 14 | Oracle 執行逾時 | 正常請求但 repository 擲 InfraError(reason="timeout") | 504；error.status=DATABASE_TIMEOUT |
| 15 | 驗證時間格式 | 任意成功回應 | restore_time 格式為 ISO 8601 秒精度、無微秒、無時區後綴 |

## 8. 範圍外

- 救回後 index、trigger 的名稱仍是回收筒內的暫時名（BIN$ 開頭），功能正常，由 DBA 事後自行改名
- FLASHBACK 時間點回溯表內容（Oracle 的另一個 FLASHBACK 功能）不在本 API 範圍
- 核准單號驗證不在本 API 範圍（SOP 未要求；如日後需要，由前端或 gateway 層處理）
