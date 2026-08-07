# 查詢回收筒 API Spec

> 來源 SOP：`docs/sops/recyclebin/query-recyclebin.md`

## 概述

將查詢 Oracle 回收筒（RECYCLEBIN：被 DROP 的表在空間被回收前的暫存區，期間可救回）的 SOP 包成 API。僅 DBA 角色可呼叫，其他人一律拒絕。DBA 可用此 API 查詢單一表是否在回收筒裡、是否能救回，或列出整個 schema 底下回收筒內全部的表。接到誤刪申請單時，DBA 先用此 API 查詢決定是否走救回流程。

## 端點一覽

| 端點 | 說明 | 風險 |
|------|------|------|
| GET /recyclebin?schema=\<schema\>&table_name=\<table_name\> | 查單一表是否在回收筒、是否能救 | 🟢 查詢 |
| GET /recyclebin?schema=\<schema\> | 列該 schema 底下回收筒全部的表，按掉進時間新到舊排序 | 🟢 查詢 |

## 典型情境

情境一「接到誤刪申請單，先查表是否還在」：
- Given：scott schema 有一張被誤刪的 emp 表
- When：呼叫 GET /recyclebin?schema=scott&table_name=emp
- Then：回傳 in_recyclebin=真、can_restore=真，DBA 決定走救回流程

情境二「查詢發現表已不可救」：
- Given：scott schema 有一張表曾被誤刪，但回收筒空間已被資料庫回收
- When：呼叫 GET /recyclebin?schema=scott&table_name=emp_bad
- Then：回傳 in_recyclebin=真、can_restore=假、reason=「空間已被資料庫回收掉」

情境三「整個 schema 掃一遍」：
- Given：scott schema 回收筒有 3 張舊表
- When：呼叫 GET /recyclebin?schema=scott（省略 table_name）
- Then：回傳按掉進時間新到舊排列的表清單，每筆包含原表名、回收筒物件名、掉進時間、能否救

## 安全防護

- 僅 DBA 角色可呼叫，其他人一律拒絕
- 每個查詢操作都留審計紀錄：操作者、時間、查詢對象、結果
- 本 API 為純查詢，不改動任何資料
- 本 API 不防護的事項：
  - 表在回收筒和回傳結果之間可能被 DBA 手動救回，導致查詢與實際狀態時差
  - 無查詢頻率限制

## 人工保留項

| SOP 步驟 | 不自動化的原因 | API 提供的替代支援 |
|----------|---------------|-------------------|
| 連上 Oracle、取得連線設定 | 超出 API 範圍，DBA 負責部署環境 | API 失敗時詳細回報連線/超時錯誤，DBA 據此排查 |
| DBA 根據查詢結果決定後續操作 | 需要人工判斷，不可自動化 | 回傳結構化資訊供決策 |

## 簽核

簽核本文件即同意「端點一覽」的端點範圍、「安全防護」的防護等級、「人工保留項」的保留項目。

---

## 規格

### §0 全域規則

#### 閘門順序

1. auth → 401（header X-API-Key ↔ env RECYCLEBIN_API_KEY，每 request 讀；未設=dev 模式僅免此閘門）
1b. 角色檢查 → 403（X-Operator-Role header，逐字比對 "DBA"，缺席或不符 → 403 PERMISSION_DENIED）
2. schema 驗證 → 422（pydantic：schema 必填、型別；table_name 在「查單一表」時必填）
3. 資源解析 → 404（本 API 純查詢，無資源 ID；如有外部資源參考時使用）
4. 前置條件 → 409（schema 存在檢查；查無時回傳 in_recyclebin=假，不是錯誤）
5. 執行

本 API 純查詢，無 irreversible 防護、無 dry_run。

#### 統一 response 形狀

HTTP 2xx（成功）：直接回業務欄位。

- **查單一表**：
  ```json
  {
    "in_recyclebin": <bool>,
    "can_restore": <bool>,
    "reason": <string|null>
  }
  ```
  其中 reason 欄位：can_restore=假時出現且非空；否則省略。

- **列全部**：
  ```json
  {
    "recyclebin_objects": [
      {
        "original_table_name": <string>,
        "recyclebin_object_name": <string>,
        "drop_time": <string>,
        "can_restore": <bool>
      }
    ]
  }
  ```
  清單為空時 recyclebin_objects=[]，也視為成功。

HTTP 4xx/5xx（被擋、驗證失敗、錯誤）：
```json
{
  "error": {
    "code": <HTTP 狀態碼>,
    "message": "<簡述>",
    "status": "<錯誤碼>",
    "details": [ <詳細物件或空陣列> ]
  }
}
```

error.message 為人讀簡述，文案集中 models/schemas.py，不屬 API 契約；程式判斷一律以 error.status 為準。

其中 details 規格：
- 輸入驗證失敗（422）→ `[{"fieldViolations": [{"field": "<欄位>", "description": "<原因>"}]}]`
- 前置條件失敗（409）→ `[{"reason": "<機器可讀原因>", "metadata": {...}}]`
- 基礎設施錯誤（503/504）→ `[{"reason": "...", "metadata": {}}]`（或 `[]` 若無附加資訊）

#### 前置條件權威表

| PC 編號 | 條件 | HTTP | error.status | 檢查順序 |
|--------|------|------|--------------|----------|
| PC-0 | X-API-Key 一致（未設 env 時 dev 模式免檢） | 401 | UNAUTHENTICATED | 1 |
| PC-0b | X-Operator-Role 為 "DBA" | 403 | PERMISSION_DENIED | 1b |
| PC-1 | schema 不能為空或空白 | 422 | INVALID_ARGUMENT | 2 |
| PC-2 | 查單一表時，table_name 不能為空或空白 | 422 | INVALID_ARGUMENT | 3 |
| PC-3 | schema 在 Oracle 中存在 | 409 | SCHEMA_NOT_FOUND | 4 |

#### 身分與權限

auth 檢查（PC-0）：
- header X-API-Key 與 env 變數 RECYCLEBIN_API_KEY 用 `secrets.compare_digest` 逐位元組比對，區分大小寫
- 每個 request 讀取 env；未設 RECYCLEBIN_API_KEY 時視為 dev 模式，PC-0 免檢（但 PC-0b 仍檢查）
- 不一致 → 401 UNAUTHENTICATED

角色檢查（PC-0b）：
- header X-Operator-Role 逐字比對 "DBA"，**區分大小寫**（"dba"、" DBA " 都不符 → 403 PERMISSION_DENIED）
- 審計 actor 從 X-Operator header 取，缺席或 strip 後空字串記作 "unknown"

#### 常數與佔位符

- `MOCK_QUERY_RECYCLEBIN`：環境變數名，=true 時使用 mock 模式（真實模式缺→boot fail-hard）
- `RECYCLEBIN_API_KEY`：API key 環境變數（驗證用）

#### 型別與行為約定

- **時間欄位**（drop_time）：Oracle 回的時間視為 UTC，去除微秒（截斷不四捨五入），不做時區轉換。秒精度 naive UTC，無微秒、無時區後綴。例：`2024-08-08T12:34:56`
- **bool 欄位**（in_recyclebin、can_restore）：永遠出現
- **大小寫規則**：
  - 輸入：schema、table_name 所有輸入 → UPPER() 後與 Oracle 比對
  - 輸出：original_table_name、recyclebin_object_name 等所有回傳欄位照 Oracle 實際儲存值（大寫）
- **排序**：列全部時按 drop_time 降序（最新先）；同時間戳的紀錄順序由 Oracle 決定
- **操作耗時**：連 Oracle 可能數秒，但 API 本身是同步查詢（sync 模型）；超時由 Oracle 連線層處理
- **並發**：無防護，同時多個查詢不互相擋；兩個查詢可並行執行
- **冪等**：同請求打兩次回傳相同結果（除非回收筒狀態實際變化）

### §1 Domain Model

| 欄位名 | 型態 | 說明 |
|-------|------|------|
| schema | string | Oracle schema 名；由 SOP 定義不能空白；不區分大小寫 |
| table_name | string | 表名；用於查單一表時；不區分大小寫 |
| in_recyclebin | bool | 表是否在回收筒裡 |
| can_restore | bool | 表是否能救回 |
| reason | string | 不能救的原因（機器碼）。值域：`SPACE_RECLAIMED` = 空間已被資料庫回收掉。can_restore=false 時非空；新增原因須改 spec |
| original_table_name | string | 原表名 |
| recyclebin_object_name | string | 回收筒物件名（BIN$ 開頭） |
| drop_time | string | 掉進回收筒的時間（ISO8601） |

### §2 Endpoints 總表

| Method | Path | 風險 | AC 前綴 | SOP 章節 |
|--------|------|------|--------|---------|
| GET | /recyclebin | 🟢 讀 | QR | 步驟 1–2 |

此表涵蓋兩種模式（查單一表 vs 列全部），由 query 參數決定。無狀態轉移。

### §3 各端點驗收準則

#### AC-QR-1：查單一表，表在回收筒且能救

**WHEN** 呼叫 GET /recyclebin?schema=scott&table_name=emp，該表在回收筒且能救  
**THE SYSTEM SHALL** 回傳 HTTP 200，body in_recyclebin=真、can_restore=真、reason 不出現

**Request**：
```
GET /recyclebin?schema=scott&table_name=emp
```

**Response**：
```json
{
  "in_recyclebin": true,
  "can_restore": true
}
```

**逼問清單檢查**：
- optional 欄位 reason：能救時不出現 ✓
- optional 欄位 can_restore：always present ✓
- 大小寫轉換：輸入轉 UPPER()、輸出取 Oracle 實際值 ✓
- 冪等性：同請求打兩次回傳相同值 ✓
- 並發：多人同時查無防護，但不影響結果 ✓

---

#### AC-QR-2：查單一表，表不在回收筒

**WHEN** 呼叫 GET /recyclebin?schema=scott&table_name=nonexistent，該表不在回收筒  
**THE SYSTEM SHALL** 回傳 HTTP 200，body in_recyclebin=假、can_restore=假、reason 不出現

**Request**：
```
GET /recyclebin?schema=scott&table_name=nonexistent
```

**Response**：
```json
{
  "in_recyclebin": false,
  "can_restore": false
}
```

**逼問清單檢查**：
- 查無結果：回傳業務事實（不是錯誤），SOP 明文 ✓

---

#### AC-QR-3：查單一表，表在回收筒但不能救

**WHEN** 呼叫 GET /recyclebin?schema=scott&table_name=emp_bad，該表在回收筒但空間已被資料庫回收  
**THE SYSTEM SHALL** 回傳 HTTP 200，body in_recyclebin=真、can_restore=假、reason 出現且說明原因

**Request**：
```
GET /recyclebin?schema=scott&table_name=emp_bad
```

**Response**：
```json
{
  "in_recyclebin": true,
  "can_restore": false,
  "reason": "SPACE_RECLAIMED"
}
```

**逼問清單檢查**：
- optional 欄位 reason：false 時出現 ✓

---

#### AC-QR-4：查單一表，大小寫不敏感

**WHEN** 分別呼叫 GET /recyclebin?schema=scott&table_name=EMP 及 GET /recyclebin?schema=scott&table_name=emp  
**THE SYSTEM SHALL** 兩請求回傳相同結果（均查到同一張表）

**Request 1**：
```
GET /recyclebin?schema=scott&table_name=EMP
```

**Request 2**：
```
GET /recyclebin?schema=scott&table_name=emp
```

**Response**（兩者相同）：
```json
{
  "in_recyclebin": true,
  "can_restore": true
}
```

**逼問清單檢查**：
- 大小寫轉換由 API 完成，用者無需關心 ✓

---

#### AC-QR-5：列全部，回收筒有多張表，按時間新到舊排序

**WHEN** 呼叫 GET /recyclebin?schema=scott（省略 table_name）  
**THE SYSTEM SHALL** 回傳 HTTP 200，body 含排序正確的表清單

**Request**：
```
GET /recyclebin?schema=scott
```

**Response**：
```json
{
  "recyclebin_objects": [
    {
      "original_table_name": "emp_new",
      "recyclebin_object_name": "BIN$abc123==0",
      "drop_time": "2024-08-08T12:34:56",
      "can_restore": true
    },
    {
      "original_table_name": "dept",
      "recyclebin_object_name": "BIN$def456==0",
      "drop_time": "2024-08-07T10:00:00",
      "can_restore": false
    },
    {
      "original_table_name": "salgrade",
      "recyclebin_object_name": "BIN$ghi789==0",
      "drop_time": "2024-08-06T08:15:30",
      "can_restore": true
    }
  ]
}
```

**逼問清單檢查**：
- 排序：新到舊（drop_time 降序）✓
- 分頁：SOP 未提及；暫行假設無分頁需求（本 API 不支援 nextPageToken）✓
- 並發：無防護 ✓

---

#### AC-QR-6：列全部，回收筒為空

**WHEN** 呼叫 GET /recyclebin?schema=empty_schema（該 schema 回收筒為空）  
**THE SYSTEM SHALL** 回傳 HTTP 200，body recyclebin_objects=[]

**Request**：
```
GET /recyclebin?schema=empty_schema
```

**Response**：
```json
{
  "recyclebin_objects": []
}
```

**逼問清單檢查**：
- 空清單視為成功，SOP 明文 ✓

---

#### AC-QR-7（失敗）：查單一表，schema 空白

**WHEN** 呼叫 GET /recyclebin?schema=&table_name=emp（schema 為空字串）  
**THE SYSTEM SHALL** 回傳 HTTP 422，error.code=422、error.status=INVALID_ARGUMENT、details 含 schema 欄位違反

**Request**：
```
GET /recyclebin?schema=&table_name=emp
```

**Response**：
```json
{
  "error": {
    "code": 422,
    "message": "Input validation failed",
    "status": "INVALID_ARGUMENT",
    "details": [
      {
        "fieldViolations": [
          {
            "field": "schema",
            "description": "cannot be empty"
          }
        ]
      }
    ]
  }
}
```

**逼問清單檢查**：
- schema 驗證順序為 PC-1，位於 PC-2 之前 ✓

---

#### AC-QR-8（失敗）：查單一表，table_name 空白

**WHEN** 呼叫 GET /recyclebin?schema=scott&table_name=（明確為空字串，不是缺席）  
**THE SYSTEM SHALL** 回傳 HTTP 422，error.code=422、error.status=INVALID_ARGUMENT、details 含 table_name 欄位違反

**Request**：
```
GET /recyclebin?schema=scott&table_name=
```

**Response**：
```json
{
  "error": {
    "code": 422,
    "message": "Input validation failed",
    "status": "INVALID_ARGUMENT",
    "details": [
      {
        "fieldViolations": [
          {
            "field": "table_name",
            "description": "cannot be empty when provided"
          }
        ]
      }
    ]
  }
}
```

**逼問清單檢查**：
- table_name 驗證順序為 PC-2 ✓

---

#### AC-QR-9（失敗）：schema 不存在

**WHEN** 呼叫 GET /recyclebin?schema=nonexistent_schema&table_name=emp  
**THE SYSTEM SHALL** 回傳 HTTP 409，error.code=409、error.status=SCHEMA_NOT_FOUND

**Request**：
```
GET /recyclebin?schema=nonexistent_schema&table_name=emp
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "Schema does not exist",
    "status": "SCHEMA_NOT_FOUND",
    "details": [
      {
        "reason": "schema_lookup",
        "metadata": {
          "schema_name": "nonexistent_schema"
        }
      }
    ]
  }
}
```

**逼問清單檢查**：
- 前置條件 PC-3 失敗 ✓

---

#### AC-QR-10（失敗）：列全部時 schema 不存在

**WHEN** 呼叫 GET /recyclebin?schema=nonexistent_schema（省略 table_name，列全部）  
**THE SYSTEM SHALL** 回傳 HTTP 409，error.code=409、error.status=SCHEMA_NOT_FOUND

**Request**：
```
GET /recyclebin?schema=nonexistent_schema
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "Schema does not exist",
    "status": "SCHEMA_NOT_FOUND",
    "details": [
      {
        "reason": "schema_lookup",
        "metadata": {
          "schema_name": "nonexistent_schema"
        }
      }
    ]
  }
}
```

---

#### AC-QR-11（邊界）：單一表被 DROP 多次，回傳最新紀錄

**WHEN** 呼叫 GET /recyclebin?schema=scott&table_name=emp，該表在回收筒有多筆紀錄（被 DROP 多次）  
**THE SYSTEM SHALL** 回傳最新那筆紀錄的狀態

**Request**：
```
GET /recyclebin?schema=scott&table_name=emp
```

**Response**（回傳最新紀錄的狀態）：
```json
{
  "in_recyclebin": true,
  "can_restore": true
}
```

**逼問清單檢查**：
- 多筆記錄時挑最新，SOP 明文 ✓

---

#### AC-QR-12（失敗）：未授權（非 DBA 角色）

**WHEN** 呼叫 GET /recyclebin?schema=scott&table_name=emp，header 提供 X-Operator-Role=ANALYST（非 "DBA"）  
**THE SYSTEM SHALL** 回傳 HTTP 403，error.code=403、error.status=PERMISSION_DENIED

**Request**：
```
GET /recyclebin?schema=scott&table_name=emp
Headers:
  X-API-Key: valid_key
  X-Operator-Role: ANALYST
```

**Response**：
```json
{
  "error": {
    "code": 403,
    "message": "Permission denied",
    "status": "PERMISSION_DENIED",
    "details": [
      {
        "reason": "insufficient_role",
        "metadata": {
          "required_role": "DBA",
          "current_role": "ANALYST"
        }
      }
    ]
  }
}
```

**逼問清單檢查**：
- 角色檢查：X-Operator-Role 必須逐字比對 "DBA" ✓
- 審計記錄 rejected:PERMISSION_DENIED ✓

---

### §4 三層落點

**目錄樹**：
```
query-recyclebin-api/
├── main.py
├── models/
│   └── schemas.py
├── api/
│   └── endpoints.py
├── service/
│   └── query_service.py
├── repository/
│   └── oracle_repository.py
├── tests/
│   ├── conftest.py
│   └── test_endpoints.py
└── README.md
```

**Repository 介面**：

```python
class OracleRepository:
    """
    Oracle 查詢層。永不擲業務錯誤。
    """
    
    def query_recyclebin_table(
        self,
        schema: str,
        table_name: str
    ) -> Optional[Dict]:
        """
        查詢單一表在回收筒的狀態。
        
        Original SQL:
            SELECT OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP
            FROM DBA_RECYCLEBIN
            WHERE OWNER = UPPER(:schema) AND ORIGINAL_NAME = UPPER(:table_name) AND TYPE='TABLE'
            ORDER BY DROPTIME DESC
            FETCH FIRST 1 ROWS ONLY
        
        能不能救 ← CAN_UNDROP='YES'
        
        回傳：
        - None：查無或 schema 不存在（基礎設施錯誤走 InfraError）
        - {"recyclebin_object_name": <OBJECT_NAME>, "original_table_name": <ORIGINAL_NAME>, "drop_time": <DROPTIME>, "can_restore": <CAN_UNDROP=='YES'>}：查到
        """
        pass
    
    def list_recyclebin_tables(
        self,
        schema: str
    ) -> List[Dict]:
        """
        列出 schema 底下回收筒全部表。
        
        Original SQL:
            SELECT OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP
            FROM DBA_RECYCLEBIN
            WHERE OWNER = UPPER(:schema) AND TYPE='TABLE'
            ORDER BY DROPTIME DESC
        
        能不能救 ← CAN_UNDROP='YES'
        
        回傳：
        - []：schema 不存在或回收筒為空
        - [{"recyclebin_object_name": <OBJECT_NAME>, "original_table_name": <ORIGINAL_NAME>, "drop_time": <DROPTIME>, "can_restore": <CAN_UNDROP=='YES'>}, ...]：查到
        """
        pass
    
    def schema_exists(self, schema: str) -> bool:
        """
        檢查 schema 是否存在。
        
        Original SQL:
            SELECT COUNT(*) FROM DBA_USERS WHERE USERNAME = UPPER(:schema)
        
        回傳：True（schema 存在）；False（查無列 = schema 不存在）
        """
        pass
```

**Service 層**：

- `query_service.get_recyclebin_table(schema, table_name)` → 呼叫 repository.query_recyclebin_table；若回傳 None 檢查 schema 是否存在（schema 不存在 → 409；否則回傳 in_recyclebin=false）。can_restore=false 時由 service 層填 reason=SPACE_RECLAIMED（目前值域唯一值）；repository 只回 CAN_UNDROP 原始值
- `query_service.list_recyclebin_tables(schema)` → 呼叫 repository.schema_exists（不存在 → 409）；再呼叫 repository.list_recyclebin_tables，整理結果排序後回傳
- 基礎設施錯誤通道：repository 擲 `InfraError(reason ∈ ["connection", "timeout"])`，service 映射 503 / 504

**API 層**（FastAPI）：

- `GET /recyclebin` endpoint：
  - Query 參數：schema（必填）、table_name（選填）
  - 判定：table_name 存在且非空 → 查單一表；否則列全部
  - 呼叫 service 方法，catch InfraError 映射 503/504
  - 每個 request 留審計紀錄（見 §7）

**Mock 定義**：

初始狀態（`MOCK_QUERY_RECYCLEBIN=true` 時）：

```python
MOCK_RECYCLEBIN_DATA = {
    "scott": {
        "emp": [
            {
                "recyclebin_object_name": "BIN$abc123==0",
                "original_table_name": "emp",
                "drop_time": "2024-08-08T12:34:56",
                "can_restore": True,
            },
            # 同一表被 DROP 多次的歷史紀錄
            {
                "recyclebin_object_name": "BIN$old123==0",
                "original_table_name": "emp",
                "drop_time": "2024-08-07T10:00:00",
                "can_restore": True,
            },
        ],
        "emp_bad": [
            {
                "recyclebin_object_name": "BIN$bad456==0",
                "original_table_name": "emp_bad",
                "drop_time": "2024-08-06T08:15:30",
                "can_restore": False,
                "reason": "SPACE_RECLAIMED",
            },
        ],
        "dept": [
            {
                "recyclebin_object_name": "BIN$def456==0",
                "original_table_name": "dept",
                "drop_time": "2024-08-05T15:45:00",
                "can_restore": True,
            },
        ],
    },
    "empty_schema": {},
    # "nonexistent_schema" 不存在，schema 檢查回傳 False
}
```

repository mock 實作：
- `schema_exists()` → 查 MOCK_RECYCLEBIN_DATA 是否有該 key
- `query_recyclebin_table()` → 查對應表的最新紀錄
- `list_recyclebin_tables()` → 回傳整個 schema 的表清單，按 drop_time 降序

### §5 設定

| 變數名 | 預設值 | 合法範圍 | 讀取時機 | 說明 |
|-------|--------|--------|--------|------|
| MOCK_QUERY_RECYCLEBIN | false | true/false | 程式啟動時快取 | true 時使用 mock 模式，不連 Oracle |
| RECYCLEBIN_API_KEY | （無預設） | 任意字串 | 每 request 讀 | API 驗證金鑰；未設時視為 dev 模式（PC-0 免檢） |
| ORACLE_DSN | （無預設） | 有效連線字串 | 程式啟動時快取 | Oracle 連線 DSN；真實模式缺→boot fail-hard |
| ORACLE_USER | （無預設） | 有效使用者 | 程式啟動時快取 | Oracle 使用者；真實模式缺→boot fail-hard |
| ORACLE_PASSWORD | （無預設） | 密碼 | 程式啟動時快取 | Oracle 密碼；真實模式缺→boot fail-hard |
| ORACLE_PORT | 1521 | 1–65535 | 程式啟動時快取 | Oracle 連線埠；真實模式缺→boot fail-hard |
| ORACLE_TIMEOUT_SEC | 30 | 1–300 | 程式啟動時快取 | 連 Oracle 的逾時秒數 |

### §6 錯誤模型

| error_code | 條件 | HTTP | 處置建議 |
|------------|------|------|--------|
| UNAUTHENTICATED | X-API-Key 不一致或缺席 | 401 | 檢查 API key，重新提交 |
| PERMISSION_DENIED | X-Operator-Role 不是 "DBA" 或缺席 | 403 | 確認操作者為 DBA 角色 |
| INVALID_ARGUMENT | schema 或 table_name（查單一表時）為空 | 422 | 檢查輸入，重新提交 |
| SPACE_RECLAIMED | 空間已被資料庫回收掉；can_restore=false 時回傳此原因 | 409 | reason 欄值 = SPACE_RECLAIMED |
| SCHEMA_NOT_FOUND | 指定的 schema 在 Oracle 中不存在 | 409 | 檢查 schema 名拼寫，確認授權 |
| ORACLE_CONNECTION_ERROR | 無法連上 Oracle 資料庫 | 503 | 確認資料庫服務狀態，DBA 重試 |
| ORACLE_TIMEOUT | 查詢 Oracle 逾時 | 504 | 系統繁忙，DBA 稍後重試 |
| ORACLE_UNAVAILABLE | 未列舉的基礎設施錯誤 | 503 | 確認資料庫服務狀態，DBA 重試 |

### §7 審計

**Schema**：

```python
class AuditLog:
    operation_id: str  # UUID
    timestamp: str  # ISO8601，秒精度
    operator: str  # X-Operator header，缺席或空 → "unknown"
    resource_type: str  # "query_recyclebin"
    resource_id: str  # schema:table_name（查單一表） 或 schema（列全部）
    action: str  # "query"
    http_method: str  # "GET"
    http_path: str  # "/recyclebin?..."
    result: str  # "success" / "rejected:<error.status>" / "error:<原因>"
    response_code: int  # HTTP 狀態碼
```

**寫入時機**（照抄）：

`401` 與 `422` 一律不留。其餘每個 request **恰好一筆**：
- `200` → result="success"
- `403` → result="rejected:PERMISSION_DENIED"
- `409` → result="rejected:SCHEMA_NOT_FOUND"
- `503`/`504` → result="error:<InfraError.reason>"

**審計固定文案**（集中 `models/schemas.py`）：

```python
AUDIT_RESOURCE_TYPE = "query_recyclebin"
AUDIT_ACTION = "query"
```

**儲存機制**：

- Mock 模式：repository 內記憶體 list（測試可讀斷言）
- 真實後端：未決項（見下「未決事項」）

### §8 測試計畫

**測試範圍**：

- 每條 AC ≥1 測試，測試名含 AC 編號
- mock 狀態操縱（fixture 注入不同的初始回收筒狀態）
- audit 各類 result 至少一次斷言（success、rejected、error）

**Conftest**：

```python
# conftest.py
import os
from pathlib import Path

# 服務根目錄注入 sys.path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

# Mock 模式環境設定
os.environ.setdefault("MOCK_QUERY_RECYCLEBIN", "true")
os.environ.setdefault("ORACLE_TIMEOUT_SEC", "30")

@pytest.fixture(autouse=True)
def reset_singletons():
    """重置 mock repository 的記憶體狀態"""
    from repository.oracle_repository import reset_mock_state
    yield
    reset_mock_state()
```

**Hermetic 測試**：

- 裸跑 `pytest` 無需先 `export MOCK_QUERY_RECYCLEBIN=true`
- conftest 用 `setdefault` 確保 mock 模式啟動
- mock repository 初始狀態固定（對齊 AC 範例）

**測試案例清單**：

1. AC-QR-1：查單一表，表在回收筒且能救
2. AC-QR-2：查單一表，表不在回收筒（回傳 in_recyclebin=false）
3. AC-QR-3：查單一表，表在回收筒但不能救（回傳 reason）
4. AC-QR-4：大小寫不敏感（fixture 同時設置大小寫變體）
5. AC-QR-5：列全部，按時間新到舊排序（手動驗證排序）
6. AC-QR-6：列全部，回收筒為空（回傳 []）
7. AC-QR-7：schema 空白（422 INVALID_ARGUMENT）
8. AC-QR-8：table_name 空白（422 INVALID_ARGUMENT）
9. AC-QR-9/10：schema 不存在（409 SCHEMA_NOT_FOUND）
10. AC-QR-11：同一表被 DROP 多次（回傳最新紀錄）
11. **授權檢查**：
    - X-Operator-Role 不是 "DBA" 時回傳 403 PERMISSION_DENIED
    - X-Operator-Role 缺席時回傳 403 PERMISSION_DENIED
12. **時間格式斷言**：drop_time 無微秒、無時區後綴，秒精度 ISO8601
13. **冪等性測試**：同請求打兩次，回傳相同 response
14. **審計各類 result**：
    - result="success"（200 cases）
    - result="rejected:PERMISSION_DENIED"（403 case）
    - result="rejected:SCHEMA_NOT_FOUND"（409 case）
    - result="rejected:INVALID_ARGUMENT"（422 cases）
    - 基礎設施模擬：mock 模式不測 503/504（真實部署測試時另補）

**失敗案例（503/504）的測法**：

Mock 模式中，repository 預設正常回傳。測試 infra 錯誤時 monkeypatch 把 oracle_repository 換成擲 `InfraError` 的假物件：

```python
def test_oracle_connection_error(monkeypatch):
    def mock_query_error(*args, **kwargs):
        from repository.oracle_repository import InfraError
        raise InfraError("connection")
    
    monkeypatch.setattr(
        "service.query_service.repository.query_recyclebin_table",
        mock_query_error
    )
    
    response = client.get(
        "/recyclebin?schema=scott&table_name=emp",
        headers={"X-API-Key": "valid_key", "X-Operator-Role": "DBA"}
    )
    assert response.status_code == 503
    assert response.json()["error"]["status"] == "ORACLE_CONNECTION_ERROR"
```

**InfraError 兜底**：

未列舉的基礎設施錯誤（非 connection 或 timeout）應映射為 503、error.status=ORACLE_UNAVAILABLE。

### §9 Out of Scope

| SOP 步驟 | 不自動化的原因 | API 替代支援 |
|----------|---------------|------------|
| 連 Oracle、取得連線設定 | 超出 API 應用範圍；DBA 負責部署環境與授權 | API 失敗時回傳詳細錯誤（503/504），DBA 據此排查資料庫問題 |
| DBA 根據查詢結果決定是否救回 | 需要人工判斷，不可自動化 | 回傳結構化資訊（in_recyclebin、can_restore、原因），供 DBA 決策 |
| 大量查詢時的效能優化 | 超出本 API 設計範圍 | 如需大量掃描，建議 DBA 直連 Oracle 或用後端批作業 |

### §10 實作交付要求

照本 spec 蓋三層式 FastAPI（api / service / repository ＋ mock，`MOCK_QUERY_RECYCLEBIN=true` 可跑全部測試），服務放 repo 根下 `query-recyclebin-api/` 目錄。

**必附 `README.md`**：
- 快速啟動：mock 模式一行起服務
- 端點一覽表（可從概要「端點一覽」帶）
- 2–3 個 curl 實走情境：
  1. 查單一表在回收筒且能救
  2. 查單一表不在回收筒
  3. 列全部表清單
- 環境變數表、怎麼跑測試

**實作中發現本 spec 未定義的行為** → 停下回報該處，修 spec 後再繼續；不得自行發明。

reason 值域（can_restore=false 時）集中 models/schemas.py，見該檔定義。

---

## 未決事項

無。本 spec 覆蓋 SOP 全部需求，無缺漏的業務判斷或系統機械面。
