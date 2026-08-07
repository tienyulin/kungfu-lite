# Recyclebin Specs 盲審與回饋記錄

此檔案記錄 recyclebin 系列 spec 的盲審、修改與實作回饋。

---

## query-recyclebin-api.spec.md — 盲審第 1 輪（2026-08-08）

| # | 嚴重度 | 發現（引 spec 原文） | 判定 | 處置 |
|---|--------|------|------|------|
| 1 | HIGH | repository SQL 無 OWNER 欄、不存在 space_reclaimed；應改用 DBA_RECYCLEBIN 含 CAN_UNDROP；can_restore 推導 = CAN_UNDROP = 'YES'；schema 存在性獨立判定（不共用 None 訊號） | 成立 | spec §4 改 SQL 為 DBA_RECYCLEBIN，加 schema_exists() 方法，明寫 can_restore 推導規則 |
| 2 | HIGH | reason 欄位值為中文，應改封閉枚舉；AC、mock、§6 對齊 | 成立 | §1 改 reason 為「SPACE_RECLAIMED」機器碼；AC-QRT-2 對齊；mock 改邏輯；§6 列舉 |
| 3 | HIGH | schema 存在性檢查與「回收筒查無」共用 None 訊號，概念混亂；應分離 | 成立 | repository 加 schema_exists() 獨立判定；明寫 PC-3 順序；刪除「schema 不存在 → 回空值」這句 |
| 4 | MED | repository 回傳型態規範不明確：查無時究竟 None 或空 list | 成立 | §4 明寫：查單一表查無 → None；列全部查無 → 空 list []；統一說法 |
| 5 | MED | §7 operation 值「QUERY_RECYCLEBIN 或 LIST_RECYCLEBIN」未寫選取規則 | 成立 | §7 補：table_name 有給 → QUERY_RECYCLEBIN；無 → LIST_RECYCLEBIN |
| 6 | MED | §7 result_status `error:<msg>` 未定義 <msg> 性質 | 成立 | 補句：<msg> 為異常摘要字串（非封閉值域）；rejected: 之值域仍封閉表 |
| 7 | MED | mock 表名小寫（"emp"）與 §0「Oracle 大寫儲存」自相矛盾 | 成立 | MOCK_RECYCLEBIN_DATA 鍵改大寫（EMP、DEPT…）；AC 範例對齊 |
| 8 | MED | audit 真實後端未決 | 駁回 | 模板允許的未決事項；§7 已列入未決欄 |
| 9 | LOW | OAuth claim 選哪個、timeout 實作層、message 措辭 | 駁回 | 部署／實作層自由度；對外行為已定義 |
| 10 | LOW | 概要未寫「最壞情況」「防篡改」「機密性」 | 駁回 | SOP 未定義，不編造 |

結果：HIGH 0（3 項全修完） / MED 4（全修） / LOW 2 → **通過**

---

## restore-dropped-table-api.spec.md — 盲審第 1 輪（2026-08-08）

| # | 嚴重度 | 發現（引 spec 原文） | 判定 | 處置 |
|---|--------|------|------|------|
| 1 | HIGH | 同 query-recyclebin HIGH#1：SQL 缺 OWNER、space_reclaimed、DBA_RECYCLEBIN、CAN_UNDROP | 成立 | 同 query；§4 四個方法的 SQL 全改 DBA_RECYCLEBIN；明寫 can_restore 推導 |
| 2 | MED | mock 表名小寫、can_restore 邏輯不明 | 成立 | MOCK_RECYCLEBIN_DATA 鍵改大寫（EMP…）；can_undrop = "YES"/"NO"；mock 邏輯改為 CAN_UNDROP 判定 |
| 3 | MED | §7 audit 的 request_schema 等未寫是否轉大寫 | 成立 | 補註：request_xxx 欄位記「使用者原始輸入，不轉大寫」 |
| 4 | MED | §8 reset_singletons 僅寫「重設」，未明寫深拷貝 + 清空 audit | 成立 | 補句：「以深拷貝初始狀態重建 MOCK_RECYCLEBIN_DATA 與 MOCK_EXISTING_TABLES，清空 audit list」 |
| 5 | MED | 概要未寫「救回可撤銷」 | 成立 | 概述補：「救回操作可撤銷（把救回的表再 DROP 一次即可回到回收筒）」 |
| 6 | MED | 安全防護 dry_run 描述不明確（預設「試算」但怎麼試、檢查啥） | 成立 | 改為：「預設僅試算；執行時先執行全部檢查並回報結果，不做實際變更」 |
| 7 | MED | audit 真實後端未決 | 駁回 | 模板允許的未決事項 |
| 8 | LOW | 概要情境三寫「回傳 409 或 404」，後設說明不宜 | 駁回 | 已改為「請求被擋下並回報原因」 |
| 9 | LOW | timeout 責任邊界、approval 流程 | 駁回 | 部署層定義 |

結果：HIGH 0（1 項全修） / MED 6（全修） / LOW 2 → **通過**

---

## 汇总修改（第 1 輪盲審）

| 項目 | 修改數 | 涉及檔案 |
|------|--------|--------|
| §0–§1 Domain Model | 3 | 兩份都修（can_restore 推導、reason 封閉枚舉、boolean 欄位規範） |
| §4 Repository | 5 | 兩份都修（SQL 改 DBA_*；query 加 schema_exists()；返型態統一；mock 表名大寫、邏輯改 CAN_UNDROP） |
| §7 Audit | 3 | query 補 operation 規則、error:<msg> 定義；restore 補 request_xxx 原始輸入註記 |
| §8 Tests | 1 | restore 補 reset_singletons 深拷貝說明 |
| 概要 | 2 | restore 補「可撤銷」+「dry_run 試算說明」|
| 共計 | 14 | query-recyclebin 8 項 / restore 6 項 |

---

## query-recyclebin-api.spec.md — 盲審第 2 輪（2026-08-08）

| # | 嚴重度 | 發現 | 改判 | 處置 |
|---|--------|------|------|------|
| 1 | HIGH | 列全部排序未明定平手情況：drop_time 相同時順序不確定 | MED | drop_time 相同時按 recyclebin_object_name 字典序由大到小；§0 補、AC-QRT-5 補、SQL 改 ORDER BY DROPTIME DESC, OBJECT_NAME DESC |
| 2 | HIGH | 回收筒查詢表名不區分大小寫但未用 UPPER()，混合大小寫表名易失匹配 | MED | SQL 改 UPPER(ORIGINAL_NAME) = UPPER(:table_name)（防禦性） |

改判理由：平手情況罕見且僅影響排序穩定性；混合大小寫表名於本環境不存在，作為防禦性修正。

結果：HIGH 0 / MED 2（全修） → **通過**

---

## restore-dropped-table-api.spec.md — 盲審第 2 輪（2026-08-08）

| # | 嚴重度 | 發現 | 判定 | 處置 |
|---|--------|------|------|------|
| — | — | （無新發現） | — | — |

結果：HIGH 0 → **通過**

---

## 汇总修改（第 2 輪盲審）

| 項目 | 修改數 | 涉及檔案 |
|------|--------|--------|
| §0 排序規則 | 1 | query 補平手規則（drop_time 相同按 OBJECT_NAME DESC） |
| §3 AC 說明 | 1 | query AC-QRT-5 補排序說明 |
| §4 SQL | 2 | 兩份都改 UPPER(ORIGINAL_NAME) = UPPER(:table_name)；query 加 OBJECT_NAME DESC |
| 共計 | 4 | query-recyclebin 4 項 / restore 0 項 |

**最終狀態：Step 5 盲審全部通過（HIGH 0），準備進 Step 6 實作。**

---

## 實作回饋歸因表（Step 6）

實作完成後記錄此處。

| 檔案 | 發現 | 歸因 | 修正 |
|------|------|------|------|
| — | — | — | — |
