# 盲審記錄

## query-recyclebin-api.spec.md 與 restore-dropped-table-api.spec.md — 盲審第 1 輪（2026-08-08）

| # | 嚴重度 | 發現（引原文） | 判定 | 處置 |
|---|--------|---------------|------|------|
| 1 | HIGH | 名稱大小寫全文統一：回傳的表名一律是 Oracle 實際儲存值（大寫）。restore response 例、query original_table_name 例、mock 初始資料、測試案例預期值 | 成立 | 已修改 response 例為 "EMP"、"EMP_RESTORED"；query 例、mock 初始資料、測試案例改為大寫 (EMP、DEPT) |
| 2 | MED | SQL 欄位名修正：DBA_RECYCLEBIN 的欄位是 DROPTIME（無底線）。SQL 寫 DROPTIME；repository dict key 維持 drop_time，並註明由 repository 轉換命名 | 成立 | SQL 改為 DROPTIME；repository dict key 保留 drop_time；各處均已補註說明轉換關係 |
| 3 | MED | audit 的 error_status 明定：填純錯誤代碼（例 TABLE_NOT_IN_RECYCLEBIN、DATABASE_TIMEOUT），不含 rejected:/error: 前綴；前綴只出現在 result 欄位 | 成立 | audit 表改為 error_status 純代碼；result 欄位格式為 `success` / `rejected:<error.status>` / `error:<error.status>` |
| 4 | MED | 「去除空白」明定為 str.strip()（含 tab、換行等空白字元）；JSON null 與未提供欄位同義；提供空字串回 422；X-Operator 空字串視同缺席 | 成立 | 處理流程改為「經 str.strip() 後」；補充 JSON null 或未提供視同缺席；空字串回 422 的說明；operator 欄位改為指明 mock 模式讀 X-Operator、缺席或空串記為 unknown |
| 5 | MED | (restore) 並發補一句：執行 FLASHBACK 時該筆紀錄已被另一請求救走 → Oracle 回錯誤，映射為 404 TABLE_NOT_IN_RECYCLEBIN，audit 記 rejected:TABLE_NOT_IN_RECYCLEBIN | 成立 | 並發欄補充：「若執行 FLASHBACK 時該筆紀錄已被另一請求救走，Oracle 回錯誤，映射為 404 TABLE_NOT_IN_RECYCLEBIN，audit 記 rejected:TABLE_NOT_IN_RECYCLEBIN」 |
| 6 | MED | (restore) RENAME TO 的新表名明定：轉大寫後的標準識別字、不加引號；本 API 不支援需引號的特殊字元表名（輸入含此類字元由 Oracle 執行時報錯） | 成立 | restore_table docstring 補充：「RENAME TO 目標不帶 schema 前綴、用轉大寫後的識別字、不加引號；本 API 不支援需引號的特殊字元表名」 |
| 7 | MED | (兩份) 時間補兩句：「截斷＝捨去小數，不進位」「Oracle 回的時間視為 UTC，不做時區轉換」。(restore) restore_time 的時點＝FLASHBACK 執行成功、完成驗證時的系統時間 | 成立 | 行為細節補「時間處理：截斷表示捨去小數部分，不進位；Oracle 回傳的時間視為 UTC，不做時區轉換」；restore_time 欄位改為「FLASHBACK 執行成功、完成驗證時的系統時間」 |
| 8 | MED | (兩份) X-Operator 與 OAuth 的關係明定：正式環境一律取 OAuth 身分、忽略 X-Operator；僅 mock 模式讀 X-Operator。(restore 同句) | 成立 | operator 欄位說明改為：「正式環境取自 OAuth 認證，忽略 X-Operator；僅 mock 模式讀 X-Operator header，缺席或去除空白後為空時記為 unknown」 |
| 9 | MED | (query) mock 初始資料列完整：把測試案例 6 需要的兩筆（EMP、DEPT，含 drop_time 與 can_undrop）都列出 | 成立 | list_tables_in_recyclebin mock 改為完整列出 EMP 與 DEPT 兩筆初始資料（含 drop_time 與 can_undrop） |
| 10 | LOW | (query) 「由大到小」補「（字典序）」。(restore) 處理流程的「最新」補明「以 DROPTIME 由新到舊，相同時以 recyclebin_object_name 字典序由大到小」 | 成立 | query 排序說明補「字典序」；restore 處理流程改為「以 DROPTIME 由新到舊，相同時以 recyclebin_object_name 字典序由大到小」 |
| 11 | LOW | (兩份) details 補半句：fieldViolations 每個違規欄位一項 | 成立 | 錯誤格式說明補「每個違規欄位一項」 |
| 12 | LOW | (兩份) audit 補一句：audit 不儲存 details 內容 | 成立 | audit 欄位說明與結果值域說明都補「Audit 不儲存 details 內容」 |
| 13 | LOW | (query) audit timestamp 明定為 request 處理完成時間 | 成立 | timestamp 欄位改為「request 處理完成時間」 |
| — | — | **駁回項** | — | — |
| 駁回-1 | — | 大小寫轉換在哪一層、exception handler 由誰實作、mock 內部時間表示、系統 schema 過濾：實作自由度 | 駁回，記入 | 合理：規格已定義對外行為，實作層級選擇不影響 spec 邊界 |
| 駁回-2 | — | 應用層加鎖 | 駁回，記入 | 合理：規格已明文無並發防護+原因，並發 race 結果由成立項 5 補完 |
| 駁回-3 | — | 第 1–3 節要寫救回流程全貌、保留時間窗口、業務影響、index 暫時名 | 駁回，記入 | 合理：查詢 API 本為低風險；救回流程屬另一份規格；保留窗口與業務影響 SOP 未定義，不編造；index 名稱限制已在範圍外一節 |

結果：HIGH 0 / MED 8 / LOW 5 → 成立項全數修改，進入實作

**備註**：
- 成立的 MED 與 LOW 項共 13 條，均已在 spec 內修改。
- 駁回項 3 條已記入，作為設計邊界說明。
- 規格通過第 1 輪盲審，準備進入 Step 6 實作階段。

---

## restore-dropped-table-api.spec.md — 盲審第 2 輪（2026-08-08）

| # | 嚴重度 | 發現（引原文） | 判定 | 處置 |
|---|--------|---------------|------|------|
| 1 | HIGH | 步驟 7「否則記錄詳細錯誤」沒定義對外行為。改為明文定義驗證失敗（FLASHBACK 未回報錯誤但表查不到或回收筒紀錄仍在）回 500 RESTORE_VERIFICATION_FAILED | 成立 | 步驟 7 改為明確的對外行為定義；錯誤代碼表加 RESTORE_VERIFICATION_FAILED（500）；audit result 值域加 `error:RESTORE_VERIFICATION_FAILED`；測試案例加第 18 列（驗證失敗情境） |

結果：HIGH 0 → 通過（該 HIGH 已修改）

**備註**：
- 第 2 輪針對 restore 的驗證步驟，HIGH 項已全部解決。
- 規格現已完全清晰，進入實作階段。
