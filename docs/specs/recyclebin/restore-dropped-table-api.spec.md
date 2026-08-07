# 救回誤刪的表 API Spec

> 來源 SOP：`docs/sops/recyclebin/restore-dropped-table.md`

## 概述

將救回誤刪表的 SOP 包成 API。僅 DBA 角色可呼叫，其他人一律拒絕。DBA 用這個 API 從 Oracle 回收筒（RECYCLEBIN：被 DROP 的表在空間被回收前的暫存區，期間可救回）救回被誤刪的表。若原表名已被佔走，可指定新名救回。操作執行前預設試算（dry_run），確認無誤後實際執行。救回可被撤銷（撤銷＝把救回的表再 DROP 回回收筒）。

## 端點一覽

| 端點 | 說明 | 風險 |
|------|------|------|
| POST /recyclebin/restore | 救回表，支援改名；預設試算，需確認後執行 | 🟡 可逆 |

## 典型情境

情境一「原名沒被佔走，直接救回」：
- Given：scott schema 有一張被誤刪的 emp 表在回收筒
- When：先呼叫 POST /recyclebin/restore（dry_run=true，試算檢查）確認無誤，再呼叫一次（dry_run=false，真正執行）
- Then：dry_run 回應含 restored_table_name=emp；真執行回傳 restored_table_name=emp 和 recyclebin_object_name、restore_time，表回到 scott schema

情境二「原名已被佔走，改名救回」：
- Given：scott schema 的 emp 表被誤刪，但現在有新的 emp 表已建立；回收筒有舊的 emp 紀錄
- When：呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, new_table_name=emp_restored, dry_run=true）試算，確認 new_table_name 不衝突，再執行
- Then：dry_run 回傳試算結果含 restored_table_name=emp_restored；真執行回傳表以新名 emp_restored 救回

情境三「操作被擋下」（失敗情境）：
- Given：scott schema，企圖救一張根本不在回收筒的表
- When：呼叫 POST /recyclebin/restore（schema=scott, table_name=nonexistent, dry_run=true）
- Then：dry_run 即被擋 409 TABLE_NOT_IN_RECYCLEBIN，不進行試算；真執行也一樣被擋

## 安全防護

- 僅 DBA 角色可呼叫，其他人一律拒絕
- 會變更狀態的操作預設僅試算不執行（dry_run）
- 每個操作（含試算與被拒絕的請求）都留審計紀錄：操作者、時間、對象、結果
- 本 API 不防護的事項：
  - 救回後自動建的 index、trigger 名仍是回收筒裡的亂碼（BIN$ 開頭），DBA 事後手動改名
  - 兩個 DBA 同時救同一張表不會互相擋；後執行的會因「表已不在回收筒」被擋（冪等性保護但無互斥）。屬可接受的設計——後執行者會被安全擋下，不會產生錯誤狀態

## 人工保留項

| SOP 步驟 | 不自動化的原因 | API 提供的替代支援 |
|----------|---------------|-------------------|
| DBA 決定是否需要改名 | 需人工判斷，何時衝突、改什麼名字 | API 會檢查名字衝突並詳細報告（原名被佔走、新名已存在），DBA 決策後重新呼叫 |
| 救回後整理 index/trigger 名 | 回收筒物件名由 Oracle 管理，改名屬 DBA 後續運維 | API 回傳 recyclebin_object_name 供 DBA 查詢對應；出現在 response 但超出 API 範圍 |
| 連接 Oracle 與預先檢查 | DBA 負責環境設置 | API 失敗時詳細報告（503/504），DBA 排查 |

## 簽核

簽核本文件即同意「端點一覽」的端點範圍、「安全防護」的防護等級、「人工保留項」的保留項目。

---

## 規格

### §0 全域規則

#### 閘門順序

1. auth → 401（header X-API-Key ↔ env RECYCLEBIN_API_KEY，每 request 讀；未設=dev 模式僅免此閘門）
1b. 角色檢查 → 403（X-Operator-Role header，逐字比對 "DBA"，缺席或不符 → 403 PERMISSION_DENIED）
2. schema 驗證 → 422（pydantic：必填、型別、邏輯互斥）
3. 資源解析 → 404（本 API 不用，但若有其他資源參考時）
4. 風險閘門 → 428（irreversible 才用；本 API reversible，無需）
5. 前置條件 → 409（schema 存在、表在回收筒、能救、名字不衝突等）
6. 執行

dry_run 的走法（照抄）：
- `dry_run=true`：跑 1–3 → 閘門 5 檢查依序評估，第一個沒過 → 對應 HTTP 碼＋error；全過 → 2xx 回應含 `"dry_run": true`。不執行。
- `dry_run=false`：跑 1–3 → 5 → 6。執行。

#### 統一 response 形狀

HTTP 2xx（成功，含 dry_run 通過）：直接回業務欄位。

- 試算回應（dry_run=true）含 `"dry_run": true` 欄位，含 restored_table_name、recyclebin_object_name；無 restore_time（試算不回傳時間戳）
- 真執行（dry_run=false）不帶 dry_run 欄位，含 restored_table_name、recyclebin_object_name、restore_time

error.message 為人讀簡述，文案集中 models/schemas.py，不屬 API 契約；程式判斷一律以 error.status 為準。

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

#### 前置條件權威表

| PC 編號 | 條件 | HTTP | error.status | 檢查順序 | 備註 |
|--------|------|------|-----------|---------|------|
| PC-0 | X-API-Key 一致（未設 env 時 dev 模式免檢） | 401 | UNAUTHENTICATED | 1 | auth 驗證 |
| PC-0b | X-Operator-Role 為 "DBA" | 403 | PERMISSION_DENIED | 1b | 角色檢查 |
| PC-1 | schema 不能為空或空白 | 422 | INVALID_ARGUMENT | 2 | schema 驗證 |
| PC-2 | table_name 不能為空或空白 | 422 | INVALID_ARGUMENT | 3 | table_name 驗證 |
| PC-3 | new_table_name（若有）不能為空或空白 | 422 | INVALID_ARGUMENT | 4 | 邏輯驗證 |
| PC-4 | schema 在 Oracle 中存在 | 409 | SCHEMA_NOT_FOUND | 5 | 前置條件 |
| PC-5 | 表在回收筒 | 409 | TABLE_NOT_IN_RECYCLEBIN | 6 | 前置條件 |
| PC-6 | 表能救回（空間未被回收） | 409 | TABLE_NOT_RESTORABLE | 7 | 前置條件 |
| PC-7 | 原名被佔走時必須提供 new_table_name | 409 | ORIGINAL_NAME_REQUIRED_NEW_NAME | 8 | 前置條件 |
| PC-8 | 提供的 new_table_name 不與現有表同名（含 new_table_name 等於原名的情況） | 409 | NEW_TABLE_NAME_EXISTS | 9 | 前置條件 |

dry_run 失敗時回傳第一個沒過的 PC 對應的 error。檢查順序 7→8。

#### 身分與權限

auth 檢查（PC-0）：
- header X-API-Key 與 env 變數 RECYCLEBIN_API_KEY 用 `secrets.compare_digest` 逐位元組比對，區分大小寫
- 每個 request 讀取 env；未設 RECYCLEBIN_API_KEY 時視為 dev 模式，PC-0 免檢（但 PC-0b 仍檢查）
- 不一致 → 401 UNAUTHENTICATED

角色檢查（PC-0b）：
- header X-Operator-Role 逐字比對 "DBA"，**區分大小寫**（"dba"、" DBA " 都不符 → 403 PERMISSION_DENIED）
- 審計 actor 從 X-Operator header 取（用 str.strip()），缺席或 strip 後為空記作 "unknown"

#### 常數與佔位符

- `MOCK_RESTORE_DROPPED_TABLE`：環境變數名，=true 時使用 mock 模式（真實模式缺→boot fail-hard）
- `RECYCLEBIN_API_KEY`：API key 環境變數（驗證用）

#### 型別與行為約定

- **時間欄位**（restore_time）：Oracle 回的時間視為 UTC，去除微秒（截斷不四捨五入），不做時區轉換。秒精度 naive UTC，無微秒、無時區後綴。例：`2024-08-08T12:34:56`
- **dry_run 預測範圍**：restored_table_name 和 recyclebin_object_name 預測；restore_time 試算時不給（真執行才有）
- **回退資訊**：dry_run response 含 restored_table_name 和 recyclebin_object_name，DBA 可據此判斷救回後的表名；無回退指令（因為可逆操作就是再 DROP 一次）
- **大小寫規則**：
  - 輸入：schema、table_name、new_table_name 所有輸入 → UPPER() 後與 Oracle 比對
  - 輸出：restored_table_name、original_table_name 等所有回傳欄位照 Oracle 實際儲存值（大寫）
  - new_table_name 衝突比對也 UPPER 後進行
- **最新那筆平手規則**：
  - drop_time 最大者
  - drop_time 相同 → 取 recyclebin_object_name 字典序最大者
- **冪等**：同 (schema, table_name, new_table_name, dry_run) 的請求打兩次，第一次成功後，第二次因「表已不在回收筒」被擋（409）；非冪等性，屬 SOP 設計
- **操作耗時**：Oracle FLASHBACK 指令通常秒級，但長表可能分鐘級；API 採同步模型（sync）；無逾時重試（DBA 手動重試）
- **並發**：兩請求同時救同一張表，無互斥；先執行的成功，後執行的因「表已不在回收筒」被擋（409）。執行 FLASHBACK 時表已被別的請求救走 → Oracle 回 ORA-38305（object not in recycle bin）→ 映射為 409 TABLE_NOT_IN_RECYCLEBIN（與 PC-5 同碼），audit 記 rejected:TABLE_NOT_IN_RECYCLEBIN
- **輔助性 mutation**：無（本 API 無前置條件自動修復）

### §1 Domain Model

| 欄位名 | 型態 | 說明 |
|-------|------|------|
| schema | string | Oracle schema 名；必填；大小寫不敏感 |
| table_name | string | 原表名；必填；大小寫不敏感 |
| new_table_name | string | 改名救回時的新表名；選填；原名被佔走時必填 |
| restored_table_name | string | 實際救回用的表名（原名或新名） |
| recyclebin_object_name | string | 原本在回收筒的物件名（BIN$ 開頭） |
| restore_time | string | 救回時間（ISO8601）；真執行時出現 |
| dry_run | bool | true 時試算，false 時真執行；預設 true |

### §2 Endpoints 總表

| Method | Path | 風險 | AC 前綴 | SOP 章節 |
|--------|------|------|--------|---------|
| POST | /recyclebin/restore | 🟡 可逆 | RD | 步驟 1–5 |

無狀態轉移；所有操作都是「救回一張表」的單態操作。

### §3 各端點驗收準則

#### AC-RD-1：原名沒被佔走，dry_run 試算成功

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, new_table_name 未給, dry_run=true），表在回收筒、原名沒被佔走、能救  
**THE SYSTEM SHALL** 回傳 HTTP 200，body 含 dry_run=真、restored_table_name=emp、recyclebin_object_name、無 restore_time

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "dry_run": true
}
```

**Response**：
```json
{
  "dry_run": true,
  "restored_table_name": "emp",
  "recyclebin_object_name": "BIN$abc123==0"
}
```

**逼問清單檢查**：
- dry_run response 欄位：含 restored_table_name、recyclebin_object_name、無 restore_time ✓
- optional new_table_name：未給時預設 None ✓
- 試算不執行 ✓

---

#### AC-RD-2：原名沒被佔走，真執行成功

**WHEN** 先呼叫 AC-RD-1 的 dry_run，再呼叫 POST /recyclebin/restore（同上參數，dry_run=false）  
**THE SYSTEM SHALL** 回傳 HTTP 200，body 含 restored_table_name=emp、recyclebin_object_name、restore_time，無 dry_run 欄位

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "dry_run": false
}
```

**Response**：
```json
{
  "restored_table_name": "emp",
  "recyclebin_object_name": "BIN$abc123==0",
  "restore_time": "2024-08-08T12:34:56"
}
```

**逼問清單檢查**：
- dry_run=false 時 response 無 dry_run 欄位 ✓
- 含 restore_time ✓
- 執行後審計留紀錄 ✓

---

#### AC-RD-3：原名被佔走，改名救回

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, new_table_name=emp_restored, dry_run=false），原名被新表佔走、新名不衝突、表在回收筒  
**THE SYSTEM SHALL** 回傳 HTTP 200，restored_table_name=emp_restored

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "new_table_name": "emp_restored",
  "dry_run": false
}
```

**Response**：
```json
{
  "restored_table_name": "emp_restored",
  "recyclebin_object_name": "BIN$abc123==0",
  "restore_time": "2024-08-08T12:34:56"
}
```

**逼問清單檢查**：
- new_table_name 邏輯：原名被佔走時可用新名 ✓
- 改名救回語意明確 ✓

---

#### AC-RD-4：大小寫不敏感

**WHEN** 分別呼叫 POST /recyclebin/restore（schema=scott, table_name=EMP）及（schema=scott, table_name=emp）  
**THE SYSTEM SHALL** 兩請求查到同一張表，回傳相同結果

（註：第二次呼叫時表已被第一次救出回收筒，會被 AC-RD-9 擋；故此測試用 fixture 重置 mock 狀態或查詢不同的表實例）

**逼問清單檢查**：
- 大小寫轉換 ✓

---

#### AC-RD-5：救過一次的表，重打同樣請求被擋

**WHEN** 第一次呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, dry_run=false）成功，DBA 隨後重打同樣請求  
**THE SYSTEM SHALL** 第二次回傳 HTTP 409，error.status=TABLE_NOT_IN_RECYCLEBIN（表已不在回收筒）

**Request**（第二次）：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "dry_run": false
}
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "Table not found in recyclebin",
    "status": "TABLE_NOT_IN_RECYCLEBIN",
    "details": [
      {
        "reason": "table_lookup",
        "metadata": {
          "schema": "scott",
          "table_name": "emp"
        }
      }
    ]
  }
}
```

**逼問清單檢查**：
- 冪等性：非冪等（SOP 設計如此，重打被擋） ✓

---

#### AC-RD-6（失敗）：表不在回收筒

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=nonexistent, dry_run=true），表根本不在回收筒  
**THE SYSTEM SHALL** dry_run 回傳 HTTP 409，error.status=TABLE_NOT_IN_RECYCLEBIN

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "nonexistent",
  "dry_run": true
}
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "Table not found in recyclebin",
    "status": "TABLE_NOT_IN_RECYCLEBIN",
    "details": []
  }
}
```

**逼問清單檢查**：
- dry_run 也會被擋 ✓

---

#### AC-RD-7（失敗）：表不能救（空間已被回收）

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp_bad, dry_run=true），表在回收筒但空間已被資料庫回收  
**THE SYSTEM SHALL** dry_run 回傳 HTTP 409，error.status=TABLE_NOT_RESTORABLE，reason 欄說明不能救的具體原因

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp_bad",
  "dry_run": true
}
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "Table cannot be restored",
    "status": "TABLE_NOT_RESTORABLE",
    "details": [
      {
        "reason": "space_reclaimed",
        "metadata": {
          "reason_detail": "空間已被資料庫回收掉"
        }
      }
    ]
  }
}
```

**逼問清單檢查**：
- 前置條件 PC-6 失敗 ✓

---

#### AC-RD-8（失敗）：schema 不存在

**WHEN** 呼叫 POST /recyclebin/restore（schema=nonexistent_schema, table_name=emp, dry_run=true）  
**THE SYSTEM SHALL** 回傳 HTTP 409，error.status=SCHEMA_NOT_FOUND

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "nonexistent_schema",
  "table_name": "emp",
  "dry_run": true
}
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

#### AC-RD-9（失敗）：原名被佔走，沒給 new_table_name

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, new_table_name 未給, dry_run=true），原名被新表佔走  
**THE SYSTEM SHALL** dry_run 回傳 HTTP 409，error.status=ORIGINAL_NAME_REQUIRED_NEW_NAME

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "dry_run": true
}
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "Original table name is taken, new_table_name required",
    "status": "ORIGINAL_NAME_REQUIRED_NEW_NAME",
    "details": [
      {
        "reason": "name_conflict",
        "metadata": {
          "message": "原名被佔走，請提供新表名"
        }
      }
    ]
  }
}
```

**逼問清單檢查**：
- 前置條件 PC-7 失敗 ✓

---

#### AC-RD-10（失敗）：new_table_name 跟現有表同名

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, new_table_name=existing_table, dry_run=true），existing_table 已存在於該 schema  
**THE SYSTEM SHALL** dry_run 回傳 HTTP 409，error.status=NEW_TABLE_NAME_EXISTS

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "new_table_name": "existing_table",
  "dry_run": true
}
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "New table name already exists",
    "status": "NEW_TABLE_NAME_EXISTS",
    "details": [
      {
        "reason": "name_conflict",
        "metadata": {
          "message": "新表名已存在，請提供其他名字"
        }
      }
    ]
  }
}
```

**逼問清單檢查**：
- 前置條件 PC-8 失敗 ✓

---

#### AC-RD-10b（邊界）：new_table_name 等於原名，被擋

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, new_table_name=emp, dry_run=true），new_table_name 與原表名相同  
**THE SYSTEM SHALL** dry_run 回傳 HTTP 409，error.status=NEW_TABLE_NAME_EXISTS

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "new_table_name": "emp",
  "dry_run": true
}
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "New table name already exists",
    "status": "NEW_TABLE_NAME_EXISTS",
    "details": []
  }
}
```

**逼問清單檢查**：
- new_table_name 等於原名時走 PC-8 被擋 ✓

---

#### AC-RD-11（失敗）：schema 空白

**WHEN** 呼叫 POST /recyclebin/restore（schema=（空或無）, table_name=emp）  
**THE SYSTEM SHALL** 回傳 HTTP 422，error.status=INVALID_ARGUMENT

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "",
  "table_name": "emp",
  "dry_run": true
}
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

---

#### AC-RD-12（失敗）：table_name 空白

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=（空））  
**THE SYSTEM SHALL** 回傳 HTTP 422，error.status=INVALID_ARGUMENT

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "",
  "dry_run": true
}
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
            "description": "cannot be empty"
          }
        ]
      }
    ]
  }
}
```

---

#### AC-RD-13（邊界）：同一表被 DROP 多次，救最新紀錄

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp）， 該表在回收筒有多筆紀錄（被 DROP 多次）  
**THE SYSTEM SHALL** 救最新那筆紀錄

（使用 fixture：mock 同一表有多筆紀錄，驗證救出的是最新一筆）

**逼問清單檢查**：
- 多筆時挑最新 ✓

---

#### AC-RD-14（失敗）：new_table_name 等於原名

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, new_table_name=emp, dry_run=true），原名被現有表佔走、new_table_name 等於原名  
**THE SYSTEM SHALL** dry_run 回傳 HTTP 409，error.status=NEW_TABLE_NAME_EXISTS（因等於被佔走的原名，必然衝突）

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "new_table_name": "emp",
  "dry_run": true
}
```

**Response**：
```json
{
  "error": {
    "code": 409,
    "message": "New table name already exists",
    "status": "NEW_TABLE_NAME_EXISTS",
    "details": [
      {
        "reason": "name_conflict",
        "metadata": {
          "message": "新表名已存在，請提供其他名字"
        }
      }
    ]
  }
}
```

**逼問清單檢查**：
- new_table_name 等於原名時走 PC-8 ✓

---

#### AC-RD-15（失敗）：未授權（非 DBA 角色）

**WHEN** 呼叫 POST /recyclebin/restore（schema=scott, table_name=emp, dry_run=false），header 提供 X-Operator-Role=ANALYST（非 "DBA"）  
**THE SYSTEM SHALL** 回傳 HTTP 403，error.status=PERMISSION_DENIED

**Request**：
```json
POST /recyclebin/restore

{
  "schema": "scott",
  "table_name": "emp",
  "dry_run": false
}

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
restore-dropped-table-api/
├── main.py
├── models/
│   └── schemas.py
├── api/
│   └── endpoints.py
├── service/
│   └── restore_service.py
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
    """Oracle 操作層。永不擲業務錯誤。"""
    
    def query_recyclebin_table(
        self,
        schema: str,
        table_name: str
    ) -> Optional[Dict]:
        """
        查回收筒裡該表的最新紀錄。
        
        Original SQL:
            SELECT OBJECT_NAME, ORIGINAL_NAME, DROPTIME, CAN_UNDROP
            FROM DBA_RECYCLEBIN
            WHERE OWNER = UPPER(:schema) AND ORIGINAL_NAME = UPPER(:table_name) AND TYPE='TABLE'
            ORDER BY DROPTIME DESC
            FETCH FIRST 1 ROWS ONLY
        
        能不能救 ← CAN_UNDROP='YES'
        
        回傳：None（查無）或 {"recyclebin_object_name": str, "drop_time": str, "can_restore": bool}
        """
        pass
    
    def table_name_exists(
        self,
        schema: str,
        table_name: str
    ) -> bool:
        """
        檢查 schema 裡是否有該表名。
        
        Original SQL:
            SELECT COUNT(*) FROM DBA_TABLES
            WHERE OWNER = UPPER(:schema) AND TABLE_NAME = UPPER(:table_name)
        
        回傳：True（表存在）；False（查無 = 表不存在）
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
    
    def restore_table(
        self,
        schema: str,
        recyclebin_object_name: str,
        target_table_name: str
    ) -> str:
        """
        執行 FLASHBACK 救回表。
        
        Original SQL：
            FLASHBACK TABLE {schema}."{recyclebin_object_name}" TO BEFORE DROP RENAME TO {target_table_name}
        
        注意：BIN$ 物件名須加雙引號；RENAME TO 目標名用 UPPER() 後的 new_table_name，不帶 schema 前綴
        
        回傳：restored_table_name（成功時的表名）
        """
        pass
```

**Service 層**：

- `restore_service.restore_table(schema, table_name, new_table_name, dry_run)` → 逐 PC 檢查，dry_run=true 回傳試算結果，dry_run=false 呼叫 repository 執行；catch InfraError 映射 503/504。can_restore=false 時由 service 層填 reason=SPACE_RECLAIMED（目前值域唯一值）；repository 只回 CAN_UNDROP 原始值
- 邏輯：
  1. PC-1–3：schema/table_name/new_table_name 驗證
  2. PC-4：schema_exists()
  3. PC-5：query_recyclebin_table() 查到
  4. PC-6：can_restore 檢查
  5. PC-7：原名被佔走時必須提供 new_table_name
  6. dry_run=true 回傳試算；dry_run=false 執行 restore_table()

**API 層**（FastAPI）：

- `POST /recyclebin/restore` endpoint：
  - Request body：schema、table_name、new_table_name（選填）、dry_run（預設 true）
  - 呼叫 service，catch InfraError 映射 503/504
  - 每個 request 留審計紀錄（見 §7）

**Mock 定義**：

初始狀態（`MOCK_RESTORE_DROPPED_TABLE=true` 時）：

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
            },
        ],
    },
}

MOCK_EXISTING_TABLES = {
    "scott": {"existing_table", "emp"}  # emp 為新建表，佔走了原名
}

def restore_table_mock(schema: str, recyclebin_object_name: str, target_table_name: str) -> str:
    """試算時回傳要救的表名；真執行時刪掉回收筒紀錄"""
    # 試算：直接回傳 target_table_name
    # 真執行：從 MOCK_RECYCLEBIN_DATA 刪掉該紀錄，加 target_table_name 到 MOCK_EXISTING_TABLES
    pass
```

### §5 設定

| 變數名 | 預設值 | 合法範圍 | 讀取時機 | 說明 |
|-------|--------|--------|--------|------|
| MOCK_RESTORE_DROPPED_TABLE | false | true/false | 程式啟動時快取 | true 時使用 mock 模式（真實模式缺→boot fail-hard） |
| RECYCLEBIN_API_KEY | （無預設） | 任意字串 | 每 request 讀 | API 驗證金鑰；未設時視為 dev 模式（PC-0 免檢） |
| ORACLE_DSN | （無預設） | 有效連線字串 | 程式啟動時快取 | Oracle 連線 DSN；真實模式缺→boot fail-hard |
| ORACLE_USER | （無預設） | 有效使用者 | 程式啟動時快取 | Oracle 使用者；真實模式缺→boot fail-hard |
| ORACLE_PASSWORD | （無預設） | 密碼 | 程式啟動時快取 | Oracle 密碼；真實模式缺→boot fail-hard |
| ORACLE_PORT | 1521 | 1–65535 | 程式啟動時快取 | Oracle 連線埠；真實模式缺→boot fail-hard |
| ORACLE_TIMEOUT_SEC | 30 | 1–300 | 程式啟動時快取 | 連 Oracle 逾時秒數 |

### §6 錯誤模型

| error_code | 條件 | HTTP | 處置建議 |
|------------|------|------|--------|
| UNAUTHENTICATED | X-API-Key 不一致或缺席 | 401 | 檢查 API key，重新提交 |
| PERMISSION_DENIED | X-Operator-Role 不是 "DBA" 或缺席 | 403 | 確認操作者為 DBA 角色 |
| INVALID_ARGUMENT | schema/table_name/new_table_name 為空 | 422 | 檢查輸入，重新提交 |
| TABLE_NOT_IN_RECYCLEBIN | 表不在回收筒 | 409 | 確認表名拼寫；或表已被救回，無法重複救 |
| TABLE_NOT_RESTORABLE | 表在回收筒但空間已被回收 | 409 | 通知 DBA，表無法救回 |
| SCHEMA_NOT_FOUND | schema 不存在 | 409 | 檢查 schema 名拼寫，確認授權 |
| ORIGINAL_NAME_REQUIRED_NEW_NAME | 原名被佔走，沒給 new_table_name | 409 | 指定 new_table_name 後重試 |
| NEW_TABLE_NAME_EXISTS | new_table_name 已被該 schema 現有表使用 | 409 | 改用其他新表名 |
| ORACLE_CONNECTION_ERROR | 無法連上 Oracle | 503 | 確認資料庫服務狀態，DBA 重試 |
| ORACLE_TIMEOUT | 查詢/操作 Oracle 逾時 | 504 | 系統繁忙，DBA 稍後重試 |
| ORACLE_UNAVAILABLE | 未列舉的基礎設施錯誤 | 503 | 確認資料庫服務狀態，DBA 重試 |

### §7 審計

**Schema**：

```python
class AuditLog:
    operation_id: str  # UUID
    timestamp: str  # ISO8601，秒精度
    operator: str  # X-Operator header，缺席或空 → "unknown"
    resource_type: str  # "restore_dropped_table"
    resource_id: str  # schema:table_name:new_table_name
    action: str  # "restore_table"
    http_method: str  # "POST"
    http_path: str  # "/recyclebin/restore"
    result: str  # "success" / "dry_run" / "rejected:<error.status>" / "error:<原因>"
    response_code: int  # HTTP 狀態碼
```

**寫入時機**（照抄）：

每個 request **恰好一筆**（401 與 422 除外，但本 API POST 操作應驗權限，422 也要留）：
- `200` + `dry_run=true` → result="dry_run"
- `200` + `dry_run=false` → result="success"
- `403` → result="rejected:PERMISSION_DENIED"
- `409` → result="rejected:<error.status>"（ORIGINAL_NAME_REQUIRED_NEW_NAME、TABLE_NOT_IN_RECYCLEBIN、SCHEMA_NOT_FOUND 等）
- `422` → result="rejected:INVALID_ARGUMENT"
- `503`/`504` → result="error:<InfraError.reason>"

**審計固定文案**（集中 `models/schemas.py`）：

```python
AUDIT_RESOURCE_TYPE = "restore_dropped_table"
AUDIT_ACTION = "restore_table"
```

**儲存機制**：

- Mock 模式：repository 內記憶體 list
- 真實後端：未決項

### §8 測試計畫

**測試範圍**：

- 每條 AC ≥1 測試
- AC-RD-1 到 AC-RD-13 全覆蓋
- mock 狀態操縱（fixture 注入初始表狀態）
- audit 各類 result：dry_run、success、rejected、error

**Conftest**：

```python
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))

os.environ.setdefault("MOCK_RESTORE_DROPPED_TABLE", "true")
os.environ.setdefault("ORACLE_TIMEOUT_SEC", "30")

@pytest.fixture(autouse=True)
def reset_singletons():
    from repository.oracle_repository import reset_mock_state
    yield
    reset_mock_state()
```

**Hermetic 測試**：

- 裸跑 `pytest` 無需先 export
- conftest 用 setdefault 確保 mock 模式
- mock repository 初始狀態固定

**測試案例**：

1. AC-RD-1：dry_run 試算，原名沒被佔走
2. AC-RD-2：真執行，原名沒被佔走
3. AC-RD-3：改名救回
4. AC-RD-4：大小寫不敏感
5. AC-RD-5：重複救被擋（非冪等）
6. AC-RD-6：表不在回收筒（409 TABLE_NOT_IN_RECYCLEBIN）
7. AC-RD-7：表不能救（409 TABLE_NOT_RESTORABLE）
8. AC-RD-8：schema 不存在（409 SCHEMA_NOT_FOUND）
9. AC-RD-9：原名被佔走沒給 new_table_name（409 ORIGINAL_NAME_REQUIRED_NEW_NAME）
10. AC-RD-10：new_table_name 衝突（409 NEW_TABLE_NAME_EXISTS）
11. AC-RD-10b：new_table_name 等於原名被擋（409 NEW_TABLE_NAME_EXISTS）
12. AC-RD-11：schema 空白（422 INVALID_ARGUMENT）
13. AC-RD-12：table_name 空白（422 INVALID_ARGUMENT）
14. AC-RD-13：同一表 DROP 多次（救最新）
15. **授權檢查**：
    - X-Operator-Role 不是 "DBA" 時回傳 403 PERMISSION_DENIED
    - X-Operator-Role 缺席時回傳 403 PERMISSION_DENIED
16. **時間格式斷言**：restore_time 秒精度 ISO8601
17. **dry_run response 形狀**：含 dry_run=true、restored_table_name、recyclebin_object_name、無 restore_time
18. **真執行 response 形狀**：無 dry_run 欄、含 restore_time
19. **審計 result 各類**：dry_run、success、rejected:PERMISSION_DENIED、rejected:TABLE_NOT_IN_RECYCLEBIN 等

**InfraError 模擬**：

```python
def test_oracle_timeout(monkeypatch):
    from repository.oracle_repository import InfraError
    
    def mock_restore_error(*args, **kwargs):
        raise InfraError("timeout")
    
    monkeypatch.setattr(
        "service.restore_service.repository.restore_table",
        mock_restore_error
    )
    
    response = client.post("/recyclebin/restore", json={
        "schema": "scott",
        "table_name": "emp",
        "dry_run": false
    }, headers={"X-API-Key": "valid_key", "X-Operator-Role": "DBA"})
    assert response.status_code == 504
    assert response.json()["error"]["status"] == "ORACLE_TIMEOUT"
```

**InfraError 兜底**：

未列舉的基礎設施錯誤（非 connection 或 timeout）應映射為 503、error.status=ORACLE_UNAVAILABLE。

**並發 race 條件測試**：

執行 FLASHBACK 時表已被別的請求救走（race 條件）應映射為 409 TABLE_NOT_IN_RECYCLEBIN；audit 記 rejected:TABLE_NOT_IN_RECYCLEBIN。

### §9 Out of Scope

| SOP 步驟 | 不自動化的原因 | API 替代支援 |
|----------|---------------|------------|
| DBA 決定救回策略（改不改名） | 需人工判斷 | API 詳細報告名字衝突，DBA 決策後重新呼叫 |
| 救回後整理 index/trigger 亂碼名 | 回收筒物件名由 Oracle 管理，改名屬後續運維 | API 回傳 recyclebin_object_name，DBA 手動改名 |
| 連 Oracle、部署環境 | 超出 API 範圍 | API 失敗時回傳詳細 503/504 錯誤，DBA 排查 |
| 自動重試邏輯 | SOP 未要求；DBA 手動重試 | API 回傳詳細錯誤便於診斷 |

### §10 實作交付要求

照本 spec 蓋三層式 FastAPI（api / service / repository ＋ mock，`MOCK_RESTORE_DROPPED_TABLE=true` 可跑全部測試），服務放 repo 根下 `restore-dropped-table-api/` 目錄。

**必附 `README.md`**：
- 快速啟動：mock 模式一行起服務
- 端點一覽表
- 3–4 個 curl 實走情境：
  1. dry_run 試算，原名沒被佔走
  2. 真執行，原名沒被佔走（含 dry_run 檢查 → 真執行的完整流程）
  3. 改名救回
  4. 被擋的情境（表不在回收筒）
- 環境變數表、怎麼跑測試

**實作中發現本 spec 未定義的行為** → 停下回報該處，修 spec 後再繼續；不得自行發明。

**reason 值域與 details 格式一致性**：
- 422 → fieldViolations 形
- 其餘 4xx/5xx → reason/metadata 形或 []
- PC-7/8 的 409 應用 reason/metadata 形

---

## 未決事項

無。本 spec 覆蓋 SOP 全部需求。

（註：後續若全服務統一加 API key 驗證或 LDAP 角色檢查，可補充 §0 auth 閘門。）
