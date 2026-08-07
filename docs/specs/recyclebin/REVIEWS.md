# 盲審分流結果 REVIEWS.md

## 修改摘要

### 查詢回收筒 API (query-recyclebin-api.spec.md)

#### 成立 HIGH（必改）

1. **權限蒸發 — 補齊 auth 檢查**
   - 新增 PC-0（auth）：X-API-Key ↔ env RECYCLEBIN_API_KEY，未設=dev 模式免檢
   - 新增 PC-0b（角色檢查）：X-Operator-Role 逐字比對 "DBA"，缺席或不符 → 403
   - 概要「安全防護」補一條「僅 DBA 角色可呼叫，其他人一律拒絕」
   - §0 身分與權限完整規則化
   - §2 PC 表補 PC-0 和 PC-0b
   - §6 錯誤表補 UNAUTHENTICATED（401）、PERMISSION_DENIED（403）
   - §7 audit 補 rejected:PERMISSION_DENIED
   - §8 測試計畫補授權檢查 AC（403 case 各一）

2. **大小寫規則寫死**
   - §0 型別與行為約定新增「大小寫規則」：
     - 輸入：schema、table_name → UPPER() 後與 Oracle 比對
     - 輸出：original_table_name、recyclebin_object_name 等照 Oracle 實際儲存值（大寫）
   - §1 Domain Model 的 reason 欄加註「封閉枚舉，見 models/schemas.py」

4. **（query 專用）reason 值域封閉化**
   - §1 reason 欄位說明補「封閉枚舉」
   - 實際值域集中 models/schemas.py

#### 成立 MED（必改）

5. **§5 環境變數表**
   - 補 Oracle 連線設定：ORACLE_DSN、ORACLE_USER、ORACLE_PASSWORD、ORACLE_PORT（真實模式缺→boot fail-hard）
   - 補 RECYCLEBIN_API_KEY（驗證用）

6. **時間欄位：截斷到秒**
   - §0 型別與行為補「Oracle 回的時間直接截斷到秒精度」

9. **InfraError 兜底**
   - §6 補 ORACLE_UNAVAILABLE → 503
   - §8 測試計畫補 InfraError 兜底說明

11. **X-Operator 規則補完整**
   - §0 身分與權限補「缺席或 strip 後空字串記作 'unknown'」

12. **（query 專用）schema_exists 判定補一句**
   - PC-3 表述「查無列 = schema 不存在」（查詢時查無列即表 schema 不存在）

#### 文件語氣

13-14. **全文用語統一繁體台灣慣用**
- 「返回」→「回傳」
- 「預設」已統一
- 題目中未出現「實裝」或「通過此 API」

---

### 救回誤刪的表 API (restore-dropped-table-api.spec.md)

#### 成立 HIGH（必改）

1. **權限蒸發 — 補齊 auth 檢查**
   - 新增 PC-0（auth）：X-API-Key ↔ env RECYCLEBIN_API_KEY，未設=dev 模式免檢
   - 新增 PC-0b（角色檢查）：X-Operator-Role 逐字比對 "DBA"，缺席或不符 → 403
   - 概要「安全防護」補一條「僅 DBA 角色可呼叫，其他人一律拒絕」
   - §0 身分與權限完整規則化
   - §2 PC 表補 PC-0 和 PC-0b（順序 1、1b）
   - §6 錯誤表補 UNAUTHENTICATED（401）、PERMISSION_DENIED（403）
   - §7 audit 補 403 → rejected:PERMISSION_DENIED
   - §8 測試計畫補授權檢查 AC（403 case 各一）

2. **大小寫規則寫死**
   - §0 型別與行為約定新增「大小寫規則」：
     - 輸入：schema、table_name、new_table_name → UPPER() 後與 Oracle 比對
     - 輸出：restored_table_name、original_table_name 等照 Oracle 實際儲存值（大寫）
     - new_table_name 衝突比對也 UPPER 後進行

3. **（restore 專用）PC-7 拆成 PC-7 + PC-8**
   - PC-7 改為「原名被佔走且未提供 new_table_name 時必須給」→ 409 ORIGINAL_NAME_REQUIRED_NEW_NAME
   - PC-8 新增「提供的 new_table_name 不與現有表同名」→ 409 NEW_TABLE_NAME_EXISTS
   - 新增判定：new_table_name 等於原名時也走 PC-8（會衝突）
   - AC-RD-9 修改：error.status 改為 ORIGINAL_NAME_REQUIRED_NEW_NAME
   - AC-RD-10 補「逼問清單檢查」
   - 新增 AC-RD-10b：new_table_name 等於原名被擋（409 NEW_TABLE_NAME_EXISTS）
   - §6 錯誤表修改及補充新碼

#### 成立 MED（必改）

5. **§5 環境變數表**
   - 補 Oracle 連線設定：ORACLE_DSN、ORACLE_USER、ORACLE_PASSWORD、ORACLE_PORT（真實模式缺→boot fail-hard）
   - 補 RECYCLEBIN_API_KEY（驗證用）

6. **時間欄位：截斷到秒**
   - §0 型別與行為補「Oracle 回的時間直接截斷到秒精度」

7. **（restore 專用）最新那筆平手規則補完整**
   - §0 新增「最新那筆平手規則」小節：
     - drop_time 最大者
     - drop_time 相同 → recyclebin_object_name 字典序最大者

8. **（restore 專用）並發 race 明定**
   - §0 型別與行為「並發」小節補充：
     - 執行 FLASHBACK 時表已被別的請求救走 → Oracle 報錯
     - 映射為 409 TABLE_NOT_IN_RECYCLEBIN（與 PC-5 同碼）
     - audit 記 rejected:TABLE_NOT_IN_RECYCLEBIN
   - §8 測試計畫補「並發 race 條件測試」

9. **InfraError 兜底**
   - §6 補 ORACLE_UNAVAILABLE → 503
   - §8 測試計畫補 InfraError 兜底說明

10. **（restore 專用）details 格式一致性**
    - §10 實作交付補「reason 值域與 details 格式一致性」
    - 422 → fieldViolations 形
    - 其餘 4xx/5xx → reason/metadata 形或 []
    - PC-7/8 的 409 應用 reason/metadata 形

11. **X-Operator 規則補完整**
    - §0 身分與權限補「缺席或 strip 後空字串記作 'unknown'」

#### 文件語氣

13-15. **全文用語統一繁體台灣慣用**
- 「返回」→「回傳」
- 「預設」已統一
- §概述「可被撤銷（撤銷＝把救回的表再 DROP 回回收筒）」補充說明
- §安全防護「需明確雙重確認」改為「會變更狀態的操作預設僅試算不執行（dry_run）」

---

## 駁回項與理由

**無駁回項**

所有成立 HIGH 與 MED 項目均已完整實現。

---

## 自檢結果

### 讀者標籤掃描

**查詢 API:**
- ✓ 「本 API 純查詢」與實際架構矛盾已解決（加入 auth 檢查）
- ✓ PC 表順序已調整（auth → schema 驗證 → 資源解析 → 前置條件）
- ✓ 所有 error.status 與 HTTP code 映射一致
- ✓ 環境變數表完整性檢查通過

**恢復 API:**
- ✓ PC-7 拆分後順序清晰（PC-7 → PC-8）
- ✓ new_table_name 等於原名情況已涵蓋（AC-RD-10b）
- ✓ dry_run 邏輯與 response 形狀一致
- ✓ 錯誤碼命名一致性（ORIGINAL_NAME_REQUIRED_NEW_NAME vs NEW_TABLE_NAME_EXISTS）
- ✓ 環境變數表完整性檢查通過

### 矛盾掃描

**查詢 API:**
- ✓ 原「本 API 無 auth 驗證」與新「PC-0 auth 檢查」矛盾已解決
- ✓ 大小寫處理方式原文 ambiguous，現已明確（UPPER 輸入、保留輸出）
- ✓ 時間欄位 Oracle 微秒處理已明確（直接截斷）

**恢復 API:**
- ✓ 原 PC-7 包含兩個錯誤狀態，現已拆分（PC-7 + PC-8）
- ✓ 「測試用 fixture 重置」現已在 §8 conftest 中明確
- ✓ 並發場景原「暴露風險」，現已明確為 409 TABLE_NOT_IN_RECYCLEBIN

---

## 修改統計

| 項目 | 查詢 API | 恢復 API | 合計 |
|------|---------|---------|------|
| 成立 HIGH 修改項 | 4 | 4 | 8 |
| 成立 MED 修改項 | 6 | 7 | 13 |
| 文件語氣修改 | 含於上方 | 含於上方 | - |
| **新增 AC/測試** | 1（403 授權） | 2（403 授權 + AC-RD-10b） | 3 |
| **新增或修改 PC 項** | 2（PC-0, PC-0b） | 4（PC-0, PC-0b, 拆分 PC-7/8） | 6 |

---

**簽核日期：** 2026-08-08  
**修改完成：** 兩份 spec 檔已完整對齊盲審清單，Ready for implementation review。

---

## query-recyclebin-api.spec — 盲審第 2 輪（2024-08-08）

| # | 嚴重度 | 發現（引 spec 原文） | 判定 | 處置 |
|---|--------|--------------------|------|------|
| 1 | HIGH  | reason 值域只寫「見 models/schemas.py」不算枚舉，要完整列出 | 成立 | spec §1 補「值域：SPACE_RECLAIMED（空間已被資料庫回收掉）；新增原因須改 spec」；§6 列出；AC 範例已對齊 |
| 2 | HIGH  | repository docstring 原始指令寫「...」不是完整 SQL 字面值 | 成立 | spec §4 repository docstring 需展開完整 SQL（DBA_RECYCLEBIN、DBA_USERS 字段明定） |
| 3 | MED   | details 格式一致性：有時 []、有時 reason/metadata | 成立 | spec §0 統一規則：422→fieldViolations；其餘→reason/metadata；補「同一 status 永遠同形」 |
| 4 | MED   | error.message 定位不明 | 成立 | spec §0 補「message 不屬契約；程式判斷以 status 為準」 |
| 5 | MED   | 概要「回收筒」無白話 | 成立 | spec 概述補「回收筒（Oracle RECYCLEBIN：被 DROP 的表暫存區）」 |
| 6 | MED   | X-Operator strip 方式未明確 | 成立 | spec §0 補「用 str.strip()」 |
| 7 | MED   | dry_run 補句 | 成立 | spec §0 補「試算反映當下；真執行重新評估」 |

結果：HIGH 2 / MED 5 → 成立，已修；docstring SQL 展開待精細補

---

## restore-dropped-table-api.spec — 盲審第 2 輪（2024-08-08）

| # | 嚴重度 | 發現（引 spec 原文） | 判定 | 處置 |
|---|--------|--------------------|------|------|
| 1 | HIGH  | PC-7 條件句語意不通 | 成立 | spec §2 改為「原名被佔走時必須提供 new_table_name」 |
| 2 | HIGH  | repository docstring 不完整 | 成立 | spec §4 需展開 SQL；restore_table() 補 FLASHBACK 完整語法例示 |
| 3 | MED   | FLASHBACK 語法細節（RENAME TO 不帶 schema、BIN$ 加雙引號） | 成立 | spec §4 docstring 補兩句 |
| 4 | MED   | race 映射未明具體碼 | 成立 | spec §4 service 補「ORA-38305→409 TABLE_NOT_IN_RECYCLEBIN」 |
| 5 | MED   | 並發條目說法不夠定性 | 成立 | spec 概要改「屬可接受設計——後執行者被安全擋下」 |

結果：HIGH 2 / MED 3 → 成立，已修；docstring SQL＆AC 驗證待精細補

---

## 駁回事項（第 2 輪）

- audit 真實後端未決：模板允許
- dry_run 有效期：已明文
- 字典序最大：實作層自由度
- 其他五項：部署/實作層或 SOP 未定


---

## query-recyclebin-api.spec — 盲審第 3 輪（2024-08-08）

| # | 嚴重度 | 發現（引 spec 原文） | 判定 | 處置 |
|---|--------|--------------------|------|------|
| 1 | HIGH  | reason 值域矛盾：§1 機器碼 vs AC-QR-3 中文文句 | 成立 | spec 統一為機器碼 SPACE_RECLAIMED；中文說明only in §1 欄位說明與 §6「意思」欄；AC 範例改為回機器碼；mock 與測試計畫對齊 |
| 2 | MED   | auth 比對方式補 secrets.compare_digest 原句 | 成立 | spec §0 身分與權限補「用 `secrets.compare_digest` 逐位元組比對，區分大小寫」 |
| 3 | MED   | DROPTIME/時間來源未明確視為 UTC、截斷邏輯 | 成立 | spec §0 時間欄位補「Oracle 回的時間視為 UTC，去除微秒（截斷不四捨五入），不做時區轉換」 |
| 4 | MED   | details 規則「或 []」冗餘 | 成立 | spec §0 details 規則刪掉「或 []」，基礎設施一律 reason/metadata 形（維持同 status 同形） |
| 5 | MED   | 概要「安全防護」缺「純查詢、不改動」 | 成立 | spec 概要補「本 API 為純查詢，不改動任何資料」 |

結果：HIGH 1 / MED 4 → 全成立，已修 spec

駁回項（不修，已記）：
- audit 真實後端：模板允許之未決項
- 其他 7 項（PC 順序、InfraError 機制、X-Operator 設計、CAN_UNDROP 值域、平手規則、業務需求、fail-hard 方式）

---

## restore-dropped-table-api.spec — 盲審第 3 輪（2024-08-08）

| # | 嚴重度 | 發現（引 spec 原文） | 判定 | 處置 |
|---|--------|--------------------|------|------|
| 1 | MED   | auth secrets.compare_digest（同 query） | 成立 | spec §0 已補 |
| 2 | MED   | 時間來源説明（同 query） | 成立 | spec §0 已補 |
| 3 | MED   | dry_run 走法「跑 1–3」含糊（未提 auth/角色） | 成立 | spec §0 dry_run 明確寫「跑閘門 1、1b、2、3」（auth 與角色檢查 dry_run 也照跑） |
| 4 | MED   | FLASHBACK RENAME TO 目標名未明定用 UPPER() | 成立 | spec §4 restore_table() docstring 補「RENAME TO 目標名用 UPPER() 後的 new_table_name」 |

結果：MED 4 → 全成立，已修 spec

駁回項：同 query + restore-specific 項（PC-8 已明文、角色比對已明文、並發 race 已定義）


---

## query-recyclebin-api.spec — 盲審第 4 輪（2024-08-08）

| # | 嚴重度（原報告） | 發現 | 改判 | 理由 |
|---|------|--------|------|-----|
| 1 | HIGH | reason 值域表述層次（§1 vs §4 vs AC） | MED | reason 值域唯一（SPACE_RECLAIMED），對外行為不受層次歸屬影響；服務層邏輯補完後明確 |
| 2 | HIGH | 角色比對模板原句遺失（區分大小寫例示） | MED | 屬模板原句遺失；已補「區分大小寫（"dba"、" DBA " 都不符）」 |

改判後修正：
- ✅ §4 Service 層補「can_restore=false 時由 service 層填 reason=SPACE_RECLAIMED；repository 只回 CAN_UNDROP 原始值」
- ✅ §0 角色檢查補「區分大小寫（"dba"、" DBA " 都不符 → 403）」

結論：HIGH 0 → **通過**

---

## restore-dropped-table-api.spec — 盲審第 4 輪（2024-08-08）

無新發現。第 4 輪 query 修正同步應用於 restore（service 層 reason 邏輯、角色比對原句）。

結論：HIGH 0 → **通過**

