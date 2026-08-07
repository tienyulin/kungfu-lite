# 救回誤刪的表 API Spec

> 來源 SOP：`docs/sops/recyclebin/restore-dropped-table.md`

## 概述

提供 DBA 從 Oracle 回收筒救回被誤刪的表。執行前進行三層檢查：表是否在回收筒、能否救回、表名是否衝突。支援以原名救回或指定新表名改名救回。救回的表是 DROP 當下的完整內容；相關 index 與 trigger 一併回來，但名稱由 DBA 事後自行整理。救回操作可撤銷（把救回的表再 DROP 一次即可回到回收筒）。

## Endpoint 一覽

| Endpoint | 說明 | 風險 |
|----------|------|------|
| POST /recyclebin/restore | 從回收筒救回指定的表 | 🟡 可逆 |

## 典型情境

情境一「確認可救回、以原名救回」：
- Given DBA 已用查詢 API 確認表在回收筒且可救回，原表名未被新表佔用
- When 呼叫 `POST /recyclebin/restore` 的 dry_run=true 進行試算（確認無誤）
- Then 回傳試算成功，告知會以原名救回；再以 dry_run=false 實際執行
- Then 表成功救回，audit 記錄救回時間與人員

情境二「表名衝突、改名救回」：
- Given DBA 要救表但原表名已被新建的表佔用
- When 呼叫 `POST /recyclebin/restore` 且指定 new_table_name，dry_run=true 試算
- Then 試算成功，確認新表名可用；改為 dry_run=false 實際執行
- Then 表以新名救回，audit 紀錄新表名與救回人員

情境三「救回失敗、被擋（失敗情境）」：
- Given 表不在回收筒（已被救過或輸入錯誤）
- When 呼叫 `POST /recyclebin/restore`
- Then 請求被擋下並回報原因（表不在回收筒），不執行任何操作

## 安全防護

- 僅 DBA 角色可使用；其他角色的請求於認證層直接拒絕（403）
- 變更類操作預設僅試算（dry_run=true）；執行時先執行全部檢查並回報結果，不做實際變更；設 dry_run=false 後執行真實操作
- 每次操作（含試算、被拒絕的 request）都留 audit 紀錄：操作者、時間、參數、結果
- 本 API 不防護的事項：
  - 救回後 index、trigger 名稱仍是 Oracle 自動命名（BIN$ 開頭），DBA 事後自行改名
  - 不檢驗新表名是否符合命名規範（由 Oracle 在執行時驗證）

## 人工保留項

| SOP 步驟 | 不自動化的原因 | API 提供的替代支援 |
|----------|---------------|-------------------|
| 救回後 index、trigger 改名 | Oracle 自動命名，整理方式因人而異，不適合自動化 | 回傳 recyclebin_object_name，DBA 據此查詢 index 名稱後手動改名 |
| 選擇新表名 | DBA 基於業務邏輯決定 | API 驗證新表名有無衝突、可否使用 |

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
2. 資源解析    → 404（request 指到的資源不存在；dry_run 也 404）
3. 風險閘門    → （本 endpoint 為 reversible，無 irreversible 的 confirm/審批）
4. 前置條件    → 409（領域狀態不允許）
5. 執行
```

dry_run 的走法：
- `dry_run=true`：跑 1–2（404 照常擲出）→ 閘門 4 的檢查**依序評估**，第一個沒過的 → 對應 HTTP 碼＋error 物件；全過 → 2xx 回應含 `"dry_run": true`。不進閘門 3、不執行。
- `dry_run=false`：reversible 過 1–2、4 後直接執行。

#### 統一 response 形狀

本專案全新，採用預設格式。

**HTTP 2xx（成功，含 dry_run 通過）**：直接回資源內容，無信封。
- 操作結果 → 平鋪欄位（restored_table_name、recyclebin_object_name、restore_time）
- dry_run 通過的 response 含 `"dry_run": true` 欄位；實際執行的回應**不帶**這個欄位

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

#### 前置條件權威表

| PC 編號 | 條件 | HTTP | error.status | 評估順序 |
|---------|------|------|--------------|---------|
| PC-1 | schema 不能為空 | 422 | INVALID_ARGUMENT | 1 |
| PC-2 | table_name 不能為空 | 422 | INVALID_ARGUMENT | 2 |
| PC-3 | schema 存在 | 404 | SCHEMA_NOT_FOUND | 3 |
| PC-4 | 表在回收筒內 | 404 | TABLE_NOT_IN_RECYCLEBIN | 4 |
| PC-5 | 表可救回（空間未被回收） | 409 | TABLE_NOT_RESTORABLE | 5 |
| PC-6 | 原表名未被佔用或有提供 new_table_name | 409 | TABLE_NAME_CONFLICT | 6 |
| PC-7 | new_table_name（若提供）未被佔用 | 409 | NEW_TABLE_NAME_EXISTS | 7 |

PC-6 與 PC-7 的區別：
- PC-6 檢查原表名是否已被現有表佔用；若被佔用且未提供 new_table_name → 409 TABLE_NAME_CONFLICT
- PC-7 檢查若有提供 new_table_name，該名稱是否已被現有表佔用；若被佔用 → 409 NEW_TABLE_NAME_EXISTS

#### 常數與佔位符

本 API 為 reversible endpoint，無 irreversible 的 confirm/approval 需求。

#### 型別與行為約定

- 時間欄位一律 ISO8601 秒精度 naive UTC（無微秒、無 Z、無時區後綴）；例：`2026-08-08T14:30:45`
- boolean 欄位一律出現，不以 null 或缺席表示 false
- 大小寫不敏感：schema、table_name、new_table_name 輸入任意大小寫，系統內部統一轉為大寫查詢與執行；response 中 restored_table_name 以實際使用的名稱回傳（原名大小寫或新名提供時的大小寫）
- 冪等性：同一 request（相同 schema、table_name、new_table_name）重複執行
  - 第一次成功：表被救回，audit 記錄成功
  - 第二次執行：表已不在回收筒（PC-4 失敗）→ 404 TABLE_NOT_IN_RECYCLEBIN；audit 記錄失敗
  - 若該表其後再被 DROP，第三次執行救的是新的那筆紀錄，屬正常流程
- 中斷復原：救回執行到一半連線中斷，Oracle 指令要嘛完成、要嘛未執行（不停在中間狀態）
  - DBA 重新執行即可；重新執行時系統會再次檢查表是否在回收筒，按前置條件評估

### §1 Domain Model

#### 請求欄位

| 欄位 | 型態 | 必填 | 說明 |
|------|------|------|------|
| schema | string | 是 | 表所屬的 schema；不能為空或純空白；大小寫不敏感 |
| table_name | string | 是 | 原始表名；不能為空或純空白；大小寫不敏感 |
| new_table_name | string \| null | 否 | 改名救回時的新表名；原名被佔用時必填；不能為空或純空白（若提供）；大小寫不敏感 |
| dry_run | boolean | 否 | 預設值 true；true 時試算不執行，false 時實際執行 |

#### Response 欄位

| 欄位 | 型態 | 說明 |
|------|------|------|
| restored_table_name | string | 實際救回使用的表名（原名或新名），以實際使用的大小寫回傳 |
| recyclebin_object_name | string | 原本在回收筒內的物件名，以 `BIN$` 開頭 |
| restore_time | string (ISO8601) | 救回時間，秒精度 UTC；dry_run=true 時該欄位表示試算完成時間（未實際執行） |
| dry_run | boolean | （僅在 dry_run=true 時出現）試算狀態標記 |

### §2 Endpoints 總表 ＋ 狀態機

| Method | Path | 風險 | AC 前綴 | SOP 章節 |
|--------|------|------|--------|---------|
| POST | /recyclebin/restore | 🟡 可逆 | FD | 救回誤刪的表 |

無狀態機（單一表的救回操作不涉及狀態轉移）。

### §3 各 endpoint 驗收準則

#### POST /recyclebin/restore

**Request Body (JSON):**

```json
{
  "schema": "scott",
  "table_name": "emp",
  "new_table_name": null,
  "dry_run": true
}
```

---

**AC-FD-1：試算、原名未被佔用、可救回**

WHEN 呼叫 `POST /recyclebin/restore` 且 dry_run=true，表在回收筒、可救回、原名未被佔用  
THE SYSTEM SHALL 回傳 200，response：
- `dry_run`: true
- `restored_table_name`: "emp"（原名）
- `recyclebin_object_name`: "BIN$..."（回收筒物件名）
- `restore_time`: 試算完成時間（未實際執行，無表被建立）

驗證方法：audit 記錄 result=`dry_run`；表未出現在 schema 中。

```json
{
  "dry_run": true,
  "restored_table_name": "emp",
  "recyclebin_object_name": "BIN$abcd1234efgh5678ijkl9012",
  "restore_time": "2026-08-08T14:30:45"
}
```

**AC-FD-2：實際執行、原名未被佔用、成功救回**

WHEN 呼叫 `POST /recyclebin/restore` 且 dry_run=false，表在回收筒、可救回、原名未被佔用  
THE SYSTEM SHALL 回傳 200，response：
- `restored_table_name`: "emp"
- `recyclebin_object_name`: 回收筒物件名
- `restore_time`: 實際救回時間
- **不含** `dry_run` 欄位

驗證方法：audit 記錄 result=`success`；表出現在 schema 中；回收筒紀錄消失。

```json
{
  "restored_table_name": "emp",
  "recyclebin_object_name": "BIN$abcd1234efgh5678ijkl9012",
  "restore_time": "2026-08-08T14:30:46"
}
```

**AC-FD-3：試算、原名被佔用、提供新表名、新名未被佔用**

WHEN 呼叫 `POST /recyclebin/restore` 且 dry_run=true，原名被新表佔用、提供 new_table_name 且該名未被佔用  
THE SYSTEM SHALL 回傳 200，response：
- `dry_run`: true
- `restored_table_name`: 所提供的新表名
- `restore_time`: 試算完成時間

```json
{
  "dry_run": true,
  "restored_table_name": "emp_restored",
  "recyclebin_object_name": "BIN$...",
  "restore_time": "2026-08-08T14:30:47"
}
```

**AC-FD-4：實際執行、以新名救回**

WHEN 呼叫 `POST /recyclebin/restore` 且 dry_run=false，原名被佔用、指定 new_table_name  
THE SYSTEM SHALL 回傳 200，response：
- `restored_table_name`: 新表名
- **不含** `dry_run` 欄位
- 表以新名出現在 schema 中

```json
{
  "restored_table_name": "emp_restored",
  "recyclebin_object_name": "BIN$abcd1234efgh5678ijkl9012",
  "restore_time": "2026-08-08T14:30:48"
}
```

**AC-FD-5：表不在回收筒**

WHEN 呼叫 `POST /recyclebin/restore`（任何 dry_run 值），表不在回收筒  
THE SYSTEM SHALL 回傳 404，error.status = `TABLE_NOT_IN_RECYCLEBIN`

```json
{
  "error": {
    "code": 404,
    "message": "表不在回收筒",
    "status": "TABLE_NOT_IN_RECYCLEBIN",
    "details": []
  }
}
```

驗證方法：audit 記錄 result=`rejected:TABLE_NOT_IN_RECYCLEBIN`；無操作發生。

**AC-FD-6：表在回收筒但空間已被回收、不可救回**

WHEN 呼叫 `POST /recyclebin/restore`，表在回收筒但無法救回（空間已被資料庫回收）  
THE SYSTEM SHALL 回傳 409，error.status = `TABLE_NOT_RESTORABLE`

```json
{
  "error": {
    "code": 409,
    "message": "表無法救回",
    "status": "TABLE_NOT_RESTORABLE",
    "details": [
      {
        "reason": "SPACE_RECLAIMED",
        "metadata": {}
      }
    ]
  }
}
```

驗證方法：audit 記錄 result=`rejected:TABLE_NOT_RESTORABLE`；無操作發生。

**AC-FD-7：schema 不存在**

WHEN 呼叫 `POST /recyclebin/restore`，schema 不存在  
THE SYSTEM SHALL 回傳 404，error.status = `SCHEMA_NOT_FOUND`

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

**AC-FD-8：原名被佔用、未提供 new_table_name**

WHEN 呼叫 `POST /recyclebin/restore`，原表名已被現有表佔用、且 new_table_name 為 null 或未提供  
THE SYSTEM SHALL 回傳 409，error.status = `TABLE_NAME_CONFLICT`

```json
{
  "error": {
    "code": 409,
    "message": "原名已被佔用，請提供新表名",
    "status": "TABLE_NAME_CONFLICT",
    "details": [
      {
        "reason": "original_name_exists",
        "metadata": {}
      }
    ]
  }
}
```

驗證方法：audit 記錄 result=`rejected:TABLE_NAME_CONFLICT`；無操作發生。

**AC-FD-9：新表名已被現有表佔用**

WHEN 呼叫 `POST /recyclebin/restore`，提供的 new_table_name 已被現有表佔用  
THE SYSTEM SHALL 回傳 409，error.status = `NEW_TABLE_NAME_EXISTS`

```json
{
  "error": {
    "code": 409,
    "message": "新表名已存在，請改用其他名稱",
    "status": "NEW_TABLE_NAME_EXISTS",
    "details": [
      {
        "reason": "new_name_exists",
        "metadata": {}
      }
    ]
  }
}
```

驗證方法：audit 記錄 result=`rejected:NEW_TABLE_NAME_EXISTS`；無操作發生。

**AC-FD-10：同一表被 DROP 多次、救最新的**

WHEN 呼叫 `POST /recyclebin/restore`，table_name 在回收筒有多筆紀錄（多次 DROP）  
THE SYSTEM SHALL 救**最新**掉進回收筒的那一筆，其他舊紀錄保留

驗證方法：確認救回的是最新的那筆（recyclebin_object_name 與時間對應最新紀錄）。

**AC-FD-11：大小寫不敏感**

WHEN 呼叫 `POST /recyclebin/restore` 且 schema=scott，table_name=EMP（大寫）  
THE SYSTEM SHALL 照常查詢並救回，restored_table_name 以提供的大小寫回傳

**AC-FD-12：schema 參數為空或純空白**

WHEN 呼叫 `POST /recyclebin/restore`，schema 為空或純空白  
THE SYSTEM SHALL 回傳 422，error.status = `INVALID_ARGUMENT`

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

**AC-FD-13：table_name 參數為空或純空白**

WHEN 呼叫 `POST /recyclebin/restore`，table_name 為空或純空白  
THE SYSTEM SHALL 回傳 422，error.status = `INVALID_ARGUMENT`

**AC-FD-14：new_table_name 提供但為空或純空白**

WHEN 呼叫 `POST /recyclebin/restore`，new_table_name 提供了但為空或純空白  
THE SYSTEM SHALL 回傳 422，error.status = `INVALID_ARGUMENT`

**AC-FD-15：冪等性 — 救回後重複執行**

WHEN 表已成功救回、再以相同參數呼叫 `POST /recyclebin/restore`  
THE SYSTEM SHALL 回傳 404，error.status = `TABLE_NOT_IN_RECYCLEBIN`（表已不在回收筒）

驗證方法：audit 記錄第二次執行為失敗；表仍存在於 schema 中。

**AC-FD-16：中斷復原 — 救回成功但連線中斷報告失敗**

WHEN 救回執行到一半連線中斷  
THE SYSTEM SHALL（由 Oracle 的原子性保證）要嘛完全成功、要嘛完全未執行，不停在中間狀態

DBA 重新執行請求時：
- 若救回已成功（表已在 schema 中）→ 再次執行回 404 TABLE_NOT_IN_RECYCLEBIN（冪等性）
- 若救回未成功（表仍在回收筒）→ 正常重試

**AC-FD-17：Infrastructure 錯誤 — 連線失敗**

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

驗證方法：audit 記錄 result=`error:SERVICE_UNAVAILABLE`；無操作發生。

**AC-FD-18：Infrastructure 錯誤 — 執行逾時**

WHEN Oracle 執行逾時（>30 秒）  
THE SYSTEM SHALL 回傳 504，error.status = `GATEWAY_TIMEOUT`

```json
{
  "error": {
    "code": 504,
    "message": "操作逾時，請稍後重試",
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
restore-dropped-table-api/
├── main.py                 # FastAPI 應用入口、路由定義
├── models/
│   └── schemas.py         # Pydantic model、request/response 結構、常數定義
├── service/
│   └── restore.py         # 業務邏輯、前置條件檢查、錯誤判定、復原邏輯
├── repository/
│   └── oracle.py          # Oracle 連線、FLASHBACK 執行、表名衝突檢查
├── mock.py                # Mock 模式的 repository 實作
├── tests/
│   ├── conftest.py        # pytest 共用設定、fixture、環境變數預設
│   └── test_api.py        # 各 AC 對應測試
├── README.md              # 快速啟動、endpoint 一覽、curl 實走例、環境變數表
└── .env.example           # 環境變數範本
```

#### Repository 介面（Oracle 實作與 Mock 實作）

**方法簽名與 docstring**

```python
class OracleRepository:
    """
    Oracle FLASHBACK 與表名衝突檢查實作
    """
    
    def check_schema_exists(self, schema: str) -> bool:
        """
        檢查 schema 是否存在
        
        原始 SQL：
          SELECT 1 FROM dba_users WHERE username = UPPER(?) FETCH FIRST 1 ROW ONLY
        
        :param schema: schema 名稱（大小寫不敏感）
        :return: 存在返 True，否則 False
        :raises InfraError: 連線失敗或查詢逾時
        """
    
    def check_table_in_recyclebin(self, schema: str, table_name: str) -> dict | None:
        """
        檢查表是否在回收筒且可救回
        
        can_restore 判定：CAN_UNDROP = 'YES' 時回傳 True；反之 False
        
        原始 SQL（取最新紀錄）：
          SELECT OWNER, OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP 
          FROM DBA_RECYCLEBIN 
          WHERE OWNER = UPPER(:schema) AND UPPER(ORIGINAL_NAME) = UPPER(:table_name) AND TYPE = 'TABLE' 
          ORDER BY DROPTIME DESC, OBJECT_NAME DESC FETCH FIRST 1 ROW ONLY
        
        :param schema: schema 名稱
        :param table_name: 表名
        :return: 若在回收筒回傳 dict with keys {recyclebin_object_name, drop_time, can_restore}；
                 否則回傳 None
        :raises InfraError: 連線失敗或查詢逾時
        """
    
    def check_table_name_exists(self, schema: str, table_name: str) -> bool:
        """
        檢查現有表中是否已存在該表名
        
        原始 SQL：
          SELECT 1 FROM DBA_TABLES 
          WHERE OWNER = UPPER(:schema) AND TABLE_NAME = UPPER(:table_name) 
          FETCH FIRST 1 ROW ONLY
        
        :param schema: schema 名稱
        :param table_name: 表名
        :return: 存在返 True，否則 False
        :raises InfraError: 連線失敗或查詢逾時
        """
    
    def restore_table(self, schema: str, table_name: str, new_table_name: str | None) -> dict:
        """
        執行表的救回操作
        
        原始指令：
          若 new_table_name 為 None（以原名救回）：
            FLASHBACK TABLE <owner>.<table_name> TO BEFORE DROP
          若 new_table_name 有提供（改名救回）：
            FLASHBACK TABLE <owner>.<table_name> TO BEFORE DROP RENAME TO <new_table_name>
        
        執行完畢後確認：
          SELECT TABLE_NAME FROM DBA_TABLES 
          WHERE OWNER = UPPER(:schema) AND TABLE_NAME = UPPER(:actual_name)
          
          SELECT 1 FROM DBA_RECYCLEBIN 
          WHERE OWNER = UPPER(:schema) AND ORIGINAL_NAME = UPPER(:table_name)
        
        :param schema: schema 名稱
        :param table_name: 原表名
        :param new_table_name: 新表名（若為 None 使用原名）
        :return: dict with keys {restored_table_name, recyclebin_object_name, restore_time}
        :raises InfraError: 連線失敗或執行逾時
        """
```

**Repository 永不擲業務錯誤**：
- 查無 → 回 None（由 service 判定為對應錯誤）
- 表名衝突檢查失敗 → 回 False（由 service 判定為 409）
- Oracle 連線失敗 / 逾時 → 擲 `InfraError(reason='connection')` 或 `InfraError(reason='timeout')`

#### Mock 初始狀態

```python
# mock.py

MOCK_RECYCLEBIN_DATA = {
    "SCOTT": {
        "EMP": {
            "recyclebin_object_name": "BIN$abcd1234efgh5678ijkl9012",
            "drop_time": "2026-08-08T14:30:45",
            "can_undrop": "YES"
        }
    }
}

MOCK_EXISTING_TABLES = {
    "SCOTT": {
        "DEPT",  # 現有表，EMP_RESTORED 不存在
        "SALGRADE"
    }
}

class MockRepository:
    def check_schema_exists(self, schema: str) -> bool:
        return schema.upper() in MOCK_RECYCLEBIN_DATA
    
    def check_table_in_recyclebin(self, schema: str, table_name: str) -> dict | None:
        schema_upper = schema.upper()
        table_upper = table_name.upper()
        
        if schema_upper not in MOCK_RECYCLEBIN_DATA:
            return None
        
        if table_upper not in MOCK_RECYCLEBIN_DATA[schema_upper]:
            return None
        
        record = MOCK_RECYCLEBIN_DATA[schema_upper][table_upper]
        can_restore = record["can_undrop"] == "YES"
        return {
            "recyclebin_object_name": record["recyclebin_object_name"],
            "drop_time": record["drop_time"],
            "can_restore": can_restore
        }
    
    def check_table_name_exists(self, schema: str, table_name: str) -> bool:
        schema_upper = schema.upper()
        table_upper = table_name.upper()
        return table_upper in MOCK_EXISTING_TABLES.get(schema_upper, set())
    
    def restore_table(self, schema: str, table_name: str, new_table_name: str | None) -> dict:
        schema_upper = schema.upper()
        table_upper = table_name.upper()
        
        # 從 recyclebin 移除（模擬 Oracle 行為）
        if schema_upper in MOCK_RECYCLEBIN_DATA and table_upper in MOCK_RECYCLEBIN_DATA[schema_upper]:
            record = MOCK_RECYCLEBIN_DATA[schema_upper].pop(table_upper)
        
        # 加到現有表列表
        actual_name = new_table_name or table_name
        if schema_upper not in MOCK_EXISTING_TABLES:
            MOCK_EXISTING_TABLES[schema_upper] = set()
        MOCK_EXISTING_TABLES[schema_upper].add(actual_name.upper())
        
        return {
            "restored_table_name": actual_name,
            "recyclebin_object_name": record.get("recyclebin_object_name", "BIN$..."),
            "restore_time": "2026-08-08T14:30:46"
        }
```

### §5 設定

| 環境變數 | 預設值 | 合法範圍 | 讀取時機 | 說明 |
|---------|--------|---------|---------|------|
| `MOCK_RESTORE_DROPPED_TABLE` | `true` | `true` \| `false` | 啟動時 | 是否使用 mock 模式 |
| `ORACLE_HOST` | （無） | 非空字串 | 啟動時 | Oracle 伺服器主機；MOCK=false 時必填 |
| `ORACLE_PORT` | `1521` | 正整數 | 啟動時 | Oracle 伺服器連線埠 |
| `ORACLE_SID` | （無） | 非空字串 | 啟動時 | Oracle database SID；MOCK=false 時必填 |
| `ORACLE_USER` | （無） | 非空字串 | 啟動時 | 連線使用者；MOCK=false 時必填 |
| `ORACLE_PASSWORD` | （無） | 非空字串 | 啟動時 | 連線密碼；MOCK=false 時必填 |
| `RESTORE_TIMEOUT_SEC` | `30` | 正整數 | 啟動時 | 單一救回操作的超時秒數 |

### §6 錯誤模型

| error_code | 條件 | HTTP | 前置條件編號 | 處置建議 |
|------------|------|------|------------|---------|
| INVALID_ARGUMENT | schema、table_name、new_table_name 為空或純空白 | 422 | PC-1、PC-2 | 檢查輸入值 |
| SCHEMA_NOT_FOUND | schema 不存在於 Oracle 中 | 404 | PC-3 | 確認 schema 名稱拼寫 |
| TABLE_NOT_IN_RECYCLEBIN | 表不在回收筒（已救回或輸入錯誤） | 404 | PC-4 | 用查詢 API 確認表是否在回收筒 |
| TABLE_NOT_RESTORABLE | 表在回收筒但無法救回（空間已被回收） | 409 | PC-5 | 確認應用其他解決方案（e.g. 從備份恢復） |
| TABLE_NAME_CONFLICT | 原表名已被現有表佔用、未提供 new_table_name | 409 | PC-6 | 提供 new_table_name 改名救回 |
| NEW_TABLE_NAME_EXISTS | 所提供的 new_table_name 已被現有表佔用 | 409 | PC-7 | 更換新表名 |
| SERVICE_UNAVAILABLE | Oracle 連線失敗 | 503 | — | 檢查網路連線與 Oracle 狀態，稍後重試 |
| GATEWAY_TIMEOUT | 救回操作耗時超過限制（30 秒） | 504 | — | 檢查 Oracle 狀態，稍後重試 |

### §7 Audit

#### Schema

| 欄位 | 型態 | 說明 |
|------|------|------|
| operation_id | string (UUID) | 唯一操作識別碼，由系統自動生成 |
| operator | string | 操作者身分（來自 OAuth 認證或 X-Operator header） |
| operation | string | 固定值：`RESTORE_DROPPED_TABLE` |
| timestamp | string (ISO8601) | 操作時間，秒精度 UTC |
| request_schema | string | 請求的 schema（記使用者原始輸入，不轉大寫） |
| request_table_name | string | 請求的原表名（記使用者原始輸入，不轉大寫） |
| request_new_table_name | string \| null | 請求的新表名（若有；記使用者原始輸入，不轉大寫） |
| request_dry_run | boolean | 請求的 dry_run 值 |
| result_status | string | `success` / `dry_run` / `rejected:<error.status>` / `error:<msg>` |
| error_status | string \| null | 若結果為失敗，記錄 error.status；否則為 null |
| restored_table_name | string \| null | 成功時的實際救回表名；失敗時為 null |

#### 寫入時機

**規則**（照抄）：schema 驗證失敗（422）不留；其餘每個 request 恰好一筆。
- 包括：試算成功（dry_run=true）、實際救回成功、失敗（404/409/503/504）

#### Result 封閉枚舉

本 endpoint 可能的 result 值：

| 值 | 情況 | 何時記錄 |
|-------|------|---------|
| `dry_run` | 試算成功（dry_run=true，通過所有前置條件） | dry_run=true 時 |
| `success` | 實際救回成功（dry_run=false，操作完成） | dry_run=false 且無錯誤時 |
| `rejected:TABLE_NOT_IN_RECYCLEBIN` | 表不在回收筒 | PC-4 失敗 |
| `rejected:TABLE_NOT_RESTORABLE` | 表無法救回 | PC-5 失敗 |
| `rejected:TABLE_NAME_CONFLICT` | 原名被佔用且未提供新名 | PC-6 失敗 |
| `rejected:NEW_TABLE_NAME_EXISTS` | 新名已被佔用 | PC-7 失敗 |
| `rejected:SCHEMA_NOT_FOUND` | schema 不存在 | PC-3 失敗 |
| `rejected:INVALID_ARGUMENT` | 輸入驗證失敗 | PC-1 或 PC-2 失敗 |
| `error:SERVICE_UNAVAILABLE` | Oracle 連線失敗 | 基礎設施錯誤 |
| `error:GATEWAY_TIMEOUT` | 操作逾時 | 基礎設施錯誤 |

#### 儲存機制

- **Mock 模式**：repository 內記憶體 list（`MockRepository.audit_log: list[AuditRecord]`），測試可讀斷言
- **真實後端**：由使用者指定，本 spec 未定義——列入未決事項

### §8 測試計畫

#### 測試範疇

每條 AC ≥1 測試、測試名含 AC 編號；dry_run vs. 實際執行兩類；audit 各類 result 至少一次；冪等性驗證。

#### Conftest

```python
# tests/conftest.py

import os
import sys
from pathlib import Path

os.environ.setdefault("MOCK_RESTORE_DROPPED_TABLE", "true")
os.environ.setdefault("RESTORE_TIMEOUT_SEC", "0")

sys.path.insert(0, str(Path(__file__).parent.parent))

@pytest.fixture(autouse=True)
def reset_singletons():
    """重設單例與 mock 狀態"""
    # 以深拷貝的初始狀態重建 MOCK_RECYCLEBIN_DATA 與 MOCK_EXISTING_TABLES，並清空 audit list
    # 各測試需要自行操縱 mock 狀態（添加或移除表）
    pass
```

#### 測試案例範例

- AC-FD-1 test_dry_run_original_name_restorable
- AC-FD-2 test_restore_original_name_success
- AC-FD-3 test_dry_run_new_name_not_exists
- AC-FD-4 test_restore_new_name_success
- AC-FD-5 test_table_not_in_recyclebin
- AC-FD-8 test_original_name_conflict_no_new_name
- AC-FD-15 test_idempotency_after_restore
- AC-FD-16 test_connection_interruption_scenario
- Audit result 各類至少一次
- 時間格式驗證

### §9 Out of Scope

| SOP 範圍外項目 | 原因 | API 替代支援 |
|---------------|------|------------|
| 救回後 index、trigger 改名 | Oracle 自動命名，整理方式因人而異，不適合自動化 | 操作成功時 audit 記錄救回表名與時間，供 DBA 後續查詢 index 名稱並手動改名 |
| 「以時間點回溯表內容」的 FLASHBACK 功能 | 與本功能不同，超出 DROP 救回的範圍 | 本功能僅提供 FLASHBACK TABLE ... TO BEFORE DROP，不支援任意時間點回溯 |

### §10 實作交付要求

按本 spec 實作三層式 FastAPI 服務（api / service / repository），放在專案根下 `restore-dropped-table-api/` 目錄。

#### 必附檔案

**README.md**：
- 快速啟動：mock 模式 `MOCK_RESTORE_DROPPED_TABLE=true python -m uvicorn main:app --reload`
- Endpoint 一覽表（引自概要）
- 3 個 curl 實走例：
  - 試算（dry_run=true）→ 實際救回（dry_run=false）的完整流程
  - 原名被佔用、改名救回
  - 表不在回收筒的失敗例
- 環境變數表、測試執行方式、冪等性說明

**測試全綠**：`pytest` 直接跑全綠，不依賴 shell export 與 cwd

**實作中發現本 spec 未定義的行為 → 停下回報該處**，不自行發明。

---

## 未決事項

### Audit 儲存後端

SOP 未明確指定 audit log 的儲存機制（資料庫表、日誌檔、日誌服務等）。

**暫行假設**：Mock 模式使用記憶體 list；真實後端由部署環境指定。

**待補項**：部署文件或環境配置需要定義真實後端的 audit log 儲存位置與查詢方式。
