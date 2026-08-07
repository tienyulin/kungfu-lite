# 救回誤刪的表

## 這個功能做什麼

把回收筒裡被誤刪的表救回來。原本的表名若已被新建的表佔用，需指定新表名以改名方式
救回；未被佔用則以原名救回。執行前系統會先檢查：表是否在回收筒、能不能救、
表名有無衝突。救回的表就是 DROP 當下的內容；index 會一併回來，但名稱是 Oracle
自動命名的暫時名，由 DBA 事後自行整理，不在本功能範圍。

## 誰可以用這個功能

只有 DBA 能用，系統要強制擋下其他人。

## 特別名詞與分類

| 名詞 | 是什麼意思／系統怎麼分辨 |
|---|---|
| 回收筒 | Oracle 的 RECYCLEBIN：被 DROP 的表在空間被回收前的暫存區，期間可救回 |
| 能不能救 | 回收筒紀錄還沒被資料庫空間回收，就能救；被回收了就救不回來 |

## 輸入

| 參數名稱 | 型態 | 必填？ | 預設值 | 輸入限制／要先檢查什麼 | 說明 |
|---|---|---|---|---|---|
| schema | 文字 | 必填 | — | 不能空白；大小寫不敏感 | 表所屬的 schema |
| table_name | 文字 | 必填 | — | 不能空白；大小寫不敏感 | 原始表名 |
| new_table_name | 文字 | 選填 | — | 原名被佔用時必填；不能空白；不能與該 schema 現有的表同名；長度限制同 Oracle 表名（細節由開發定） | 改名救回時的新表名；原名未被佔用可不提供 |

## 輸出

| 欄位名稱 | 型態 | 說明 |
|---|---|---|
| restored_table_name | 文字 | 實際救回使用的表名（原名或新名） |
| recyclebin_object_name | 文字 | 原本在回收筒內的物件名 |
| restore_time | 日期時間 | 救回時間 |

## 開始前先確認

- schema 與 table_name 不能空白
- 表在回收筒內
- 能救回（空間尚未被資料庫回收）
- 表名衝突檢查：原名被佔用時必須提供 new_table_name，否則擋下並提示
  「原名已被佔用，請提供新表名」；有提供 new_table_name 時，若與該 schema 現有的表
  同名，擋下並提示「新表名已存在，請改用其他名稱」

## 步驟

1. 定位回收筒紀錄
   - 做之前先確認：schema 與 table_name 不能空白
   - 怎麼做：依 schema 與 table_name 在回收筒內定位；查到多筆同名紀錄
     （同一張表被 DROP 過多次）時，取最新掉進回收筒的那一筆
2. 判斷能不能救
   - 怎麼做：檢查該筆紀錄的空間是否還在
   - 這步出錯了怎麼辦：不能救 → 回報「表無法救回，原因：<具體原因>」
3. 表名衝突檢查
   - 怎麼做：檢查原表名是否已被現有的表佔用；被佔用時確認是否有提供
     new_table_name，有提供則再確認 new_table_name 未與現有的表同名
   - 這步出錯了怎麼辦：
     - 原名被佔用、未提供 new_table_name → 擋下，回報「原名已被佔用，請提供新表名」
     - new_table_name 與現有的表同名 → 擋下，回報「新表名已存在，請改用其他名稱」
4. 執行救回
   - 怎麼做：執行 Oracle 指令 FLASHBACK TABLE ... TO BEFORE DROP（需改名時
     加 RENAME TO，以一條指令直接用新名救回，不是先救回再改名）
5. 驗證
   - 怎麼做：確認該表在 schema 內查得到、回收筒內那筆紀錄已消失

## 怎麼算成功

表在 schema 內查得到、回收筒紀錄消失。表的內容即 DROP 當下的狀態，不需另行比對。

## 做了之後能復原嗎

能。救回的表再 DROP 一次就回到回收筒。因此不需要主管簽核，也不需要事前備份。

## 同一個對象能重複做嗎

救回後該筆回收筒紀錄已消失，再以相同參數執行會被擋下並回報「表不在回收筒」；
若該表之後又被 DROP，則是救新的那筆紀錄，屬正常流程。

救回執行到一半連線中斷：這條 Oracle 指令要嘛完成、要嘛未執行，不會停在中間狀態。
DBA 重新執行即可；重新執行時系統會再次檢查表是否在回收筒。

## 可能出什麼錯、出錯了怎麼辦

- 表在回收筒內查不到 → 回報「表不在回收筒」
- 表無法救回（空間已被回收等原因）→ 回報「表無法救回，原因：<具體原因>」
- schema 不存在 → 回報「schema 不存在」
- 原名被佔用、未提供 new_table_name → 回報「原名已被佔用，請提供新表名」
- new_table_name 與現有的表同名 → 回報「新表名已存在，請改用其他名稱」
- 連不上 Oracle 或逾時 → 回報系統錯誤，由 DBA 自行重試，系統不自動重試

## 範圍外

- 救回後 index、trigger 的名稱仍是回收筒內的暫時名（BIN$ 開頭），功能正常，
  由 DBA 事後自行改名，不在本功能範圍
- 「以時間點回溯表內容」的 FLASHBACK 功能是另一回事，本功能只做回收筒救回

## 測試例子

1. schema=scott, table_name=emp，不給 new_table_name，表在回收筒且原名未被佔用 → 成功，restored_table_name=emp
2. schema=scott, table_name=emp, new_table_name=emp_restored，原名被佔用 → 成功，restored_table_name=emp_restored
3. schema=scott, table_name=nonexistent，表不在回收筒 → 被擋，回報「表不在回收筒」
4. schema=scott, table_name=emp（已救回過、回收筒紀錄已消失）→ 被擋，回報「表不在回收筒」
5. schema=scott, table_name=emp，不給 new_table_name，原名被佔用 → 被擋，回報「原名已被佔用，請提供新表名」
6. schema=scott, table_name=emp, new_table_name=existing_table（與現有的表同名）→ 被擋，回報「新表名已存在，請改用其他名稱」
7. schema=scott, table_name=emp，被 DROP 多次、回收筒有多筆 → 救最新那一筆，成功
8. schema=scott, table_name=emp，表在回收筒但空間已被回收 → 被擋，回報「表無法救回，原因：空間已被資料庫回收」
9. schema=nonexistent, table_name=emp → 被擋，回報「schema 不存在」
10. schema=scott, table_name=EMP（大寫）→ 大小寫不敏感，照常定位並救回
11. schema=（空白）→ 被擋，回報輸入錯誤
12. schema=scott, table_name=（空白）→ 被擋，回報輸入錯誤
13. 救回成功後以相同參數再執行一次 → 被擋，回報「表不在回收筒」
