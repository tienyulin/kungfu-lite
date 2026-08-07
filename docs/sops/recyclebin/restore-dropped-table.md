# 救回誤刪的表

## 這個功能做什麼

把回收筒裡那張表救回來。如果原本的名字已經被新建的表佔走，就要指定一個新名字救回（改名救回）；沒被佔走就可以用原名救回。API 自己會先檢查：表在不在回收筒、能不能救、名字有沒有衝突。救回來的表就是 DROP 當下的樣子，index 會一起回來但名字是系統亂碼名，DBA 之後自己整理，這不在 API 範圍內。

## 誰可以用這個功能

只有 DBA 能用。系統要強制擋其他人。

## 特別名詞與分類

| 名詞 | 是什麼意思／系統怎麼分辨 |
|---|---|
| 回收筒 | Oracle 的 RECYCLEBIN，使用者誤刪表後，表先掉進回收筒，可以在一定時間內救回 |
| 能不能救 | 回收筒紀錄還沒被資料庫空間回收；如果空間已被回收掉，就救不了那張表 |

## 輸入

| 參數名稱 | 型態 | 必填？ | 預設值 | 輸入限制／要先檢查什麼 | 說明 |
|---|---|---|---|---|---|
| schema | 文字 | 必填 | — | 不能空白；大小寫不敏感（系統自己對應） | 表所屬的 schema |
| table_name | 文字 | 必填 | — | 不能空白；大小寫不敏感（系統自己對應） | 原始表名 |
| new_table_name | 文字 | 選填 | — | 原名被佔走時必填；不能空白；不能跟該 schema 現有的表同名；長度跟 Oracle 表名限制一樣 | 改名救回時的新表名；原名沒被佔走可不提供 |

## 輸出

| 欄位名稱 | 型態 | 說明 |
|---|---|---|
| restored_table_name | 文字 | 實際救回用的表名（原名或新名） |
| recyclebin_object_name | 文字 | 原本在回收筒的物件名 |
| restore_time | 日期時間 | 救回時間 |

## 開始前先確認

- schema 名不能空白
- table_name 不能空白
- 表在不在回收筒
- 能不能救（例如空間已被資料庫回收掉）
- 名字衝突檢查：原名被佔走時，必須給 new_table_name，否則擋下並提示「原名被佔走，請提供新表名」；如果給了 new_table_name，檢查它是否跟該 schema 現有的表同名，同名則擋下並提示「新表名已存在，請提供其他名字」

## 步驟

1. 查回收筒定位
   - 做之前先確認：schema 和 table_name 不能空白
   - 怎麼做：根據輸入的 schema 和 table_name 在回收筒裡定位。若查到多筆同名資料（同一張表被 DROP 好幾次），挑最新那筆

2. 判斷能不能救
   - 怎麼做：檢查表的狀態能不能救回（例如空間還在不在）
   - 這步出錯了怎麼辦：表不能救 → 回報「表不能救，原因：<具體原因>」

3. 名字衝突檢查
   - 怎麼做：檢查原表名是否被現有表佔走。若被佔走，檢查是否有給 new_table_name；若有，再檢查 new_table_name 是否跟現有表衝突
   - 這步出錯了怎麼辦：
     - 原名被佔走、沒給 new_table_name → 擋下回報「原名被佔走，請提供新表名」
     - new_table_name 跟現有表同名 → 擋下回報「新表名已存在，請提供其他名字」

4. 執行救回
   - 怎麼做：執行 Oracle 指令 FLASHBACK TABLE ... TO BEFORE DROP（若要改名則加 RENAME TO，直接用新名救）

5. 驗證
   - 怎麼做：檢查表在 schema 裡查得到、回收筒裡那筆消失了

## 怎麼算成功

表在 schema 裡查得到、回收筒紀錄消失。

## 做了之後能復原嗎

能。救回來的表再 DROP 一次就又回到回收筒了。不需要主管簽核或預先備份。

## 同一個對象能重複做嗎

救回過的表，那筆回收筒紀錄已經沒了。再打一次同樣的請求會被擋「表不在回收筒」。

例外：若該表事後又被 DROP 了一次，就是救新的那筆紀錄，正常流程。

救到一半連線斷掉：Oracle 指令要嘛成功要嘛沒做，不會半套。DBA 重打一次就好；重打前 API 反正會再檢查一次在不在回收筒。

## 可能出什麼錯、出錯了怎麼辦

- 表在回收筒查不到 → 回報「表不在回收筒」
- 表不能救（空間已被回收掉等理由） → 回報「表不能救，原因：<具體原因>」
- schema 不存在 → 回報「schema 不存在」
- 原名被佔走、沒給 new_table_name → 回報「原名被佔走，請提供新表名」
- new_table_name 跟現有表同名 → 回報「新表名已存在，請提供其他名字」
- 連不上 Oracle 或超時 → 回報系統錯誤，DBA 自己重試（不用自動重試）

## 範圍外／已知的怪現象

- 救回來的表，它的 index、trigger 名字都還是回收筒裡的亂碼名（BIN$ 開頭），看起來很怪但功能正常，屬正常現象。DBA 事後自己改名，不在本 API 範圍。
- 「用時間點回溯表內容」那種 FLASHBACK QUERY 功能是另一回事，不在本次範圍；本 API 只做回收筒救回。

## 測試例子

1. schema=scott, table_name=emp, new_table_name=（無）, 表在回收筒且原名沒被占 → 成功救回，restored_table_name=emp

2. schema=scott, table_name=emp, new_table_name=emp_restored, 表在回收筒且原名被占 → 成功救回，restored_table_name=emp_restored

3. schema=scott, table_name=nonexistent → 表根本不在回收筒 → 擋下回報「表不在回收筒」

4. schema=scott, table_name=emp（已救回過一次），回收筒紀錄已消失 → 擋下回報「表不在回收筒」

5. schema=scott, table_name=emp, new_table_name=（無），原名被佔走 → 擋下回報「原名被佔走，請提供新表名」

6. schema=scott, table_name=emp, new_table_name=existing_table（與現有表同名） → 擋下回報「新表名已存在，請提供其他名字」

7. schema=scott, table_name=emp（被DROP好幾次，回收筒有多筆） → 救最新的那一筆 → 成功

8. schema=scott, table_name=emp, 表在回收筒但不能救（空間已被回收） → 擋下回報「表不能救，原因：空間已被資料庫回收掉」

9. schema=nonexistent, table_name=emp → 擋下回報「schema 不存在」

10. schema=scott, table_name=EMP（大寫）→ 系統自己對應，應該查到並救回（大小寫不敏感測試）

11. schema=（空白）→ 因「schema 不能空白」被擋，回報輸入錯誤

12. schema=scott, table_name=（空白）→ 因「table_name 不能空白」被擋，回報輸入錯誤

13. schema=scott, table_name=emp, 救回後 DBA 重新執行同樣請求 → 擋下回報「表不在回收筒」（驗證重複做規則）
