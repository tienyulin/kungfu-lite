---
name: sop-to-spec
description: 把人工操作的 SOP 轉成正式的 API 規格書（spec），含風險判定、自檢與盲審；不懂技術的人讀前三節能了解用途與風險，工程師或 AI 讀全文能直接實作三層式 FastAPI 服務。使用者要把 SOP 轉 spec、把程序文件轉成 API 規格時使用，任何領域的 SOP 都適用。
---

# SOP 轉 Spec

把人工操作的 SOP 轉成一份 API 規格書。開工前把進度清單抄進回覆，完成一步勾一步；
遇到本 skill 與 references 都沒定義的情況，停下來問使用者。

```
進度：
- [ ] Step 0 SOP 合格檢查
- [ ] Step 1 整理工作清單
- [ ] Step 2 風險判定
- [ ] Step 3 寫 spec
- [ ] Step 4 自檢
- [ ] Step 5 盲審（HIGH 清零才算完成）
- [ ] （實作發生後）Step 6 歸因
```

寫出來的 spec 是一份正式文件：主管讀前三節能決定簽不簽，工程師或 AI 讀全文能
直接實作，不需要回頭讀 SOP。三個原則：

1. spec 是唯一交接物——實作者只讀 spec，SOP 裡實作需要的資訊全部寫進 spec。
2. 自足——不引用 SOP 與 spec 以外的檔案或慣例（「比照某服務」不行），
   全新 repo 也能照著開工。
3. 未定義的行為是 spec 的缺陷——實作中發現就回頭修 spec，不是讓實作自行決定。

## 輸入、輸出、語言

- 輸入：SOP 檔案路徑，或 `docs/sops/<組名>/` 資料夾（逐檔各產一份 spec）。
  路徑不存在就停下來問。只收合格 SOP（Step 0）；使用者手上只有粗略需求或
  不合規文件時，先用 `sop-author` 訪談產出合規 SOP。
- 輸出：`docs/specs/<組名>/<sop-slug>-api.spec.md`（SOP 不在此佈局下退回
  `specs/`）。一份 SOP 對應一份 spec；拆分或合併是 SOP 作者的事，本 skill 不代勞。
- 語言：spec 與 SOP 同語言，技術名詞用英文；模板裡標「照抄」的段落可整段翻譯成
  spec 的語言，但不增刪內容。

產 spec 途中發現 SOP 缺資訊時，先分辨性質：業務判斷（風險、失敗處理、成功條件）
只有 SOP 作者知道，回頭請他補（對應欄位見
[references/sop-authoring-guide.md](references/sop-authoring-guide.md)）；
系統面的機制（登入、格式驗證、冪等、並發）照模板的共通規範處理，不必回問。
問不到人就在概述之後加「未決事項」一節，假設取較嚴格的方向；不可逆操作的關鍵參數
不得自行假設。

## 流程

| Step | 內容 | 參考 |
|------|------|------|
| 0 合格檢查 | 逐份確認必要節齊全且非空：做什麼、誰可以用、輸入（或明寫「無」）、輸出、步驟（每步有「怎麼做」）、做了之後能復原嗎、同一個對象能重複做嗎、可能出什麼錯、測試例子。缺節就停下回報，請使用者用 `sop-author` 補完；使用者堅持照轉，缺的部分全部進未決事項 | — |
| 1 整理 | 讀 SOP 列出查詢類與變更類操作、前置條件、錯誤情況。這是工作草稿，不進 spec。順手檢查 SOP 前後矛盾，有就回報請作者修 | — |
| 2 風險判定 | 依 SOP「做了之後能復原嗎」判定查詢／可逆／不可逆，照原文結論，不自行升級 | [references/spec-template.md](references/spec-template.md) |
| 3 寫 spec | 照模板的文件結構依序寫；寫各 endpoint 規格時，每個 endpoint 過一遍追問清單 | [references/spec-template.md](references/spec-template.md)、[references/checklists.md](references/checklists.md) |
| 4 自檢 | 跑完自檢清單，含幾項 grep 檢查 | [references/checklists.md](references/checklists.md) |
| 5 盲審 | spawn 乾淨 context 的 subagent 盲審 spec；成立的 HIGH 清零前不開工；過程記入同資料夾的 `REVIEWS.md` | [references/checklists.md](references/checklists.md) |
| 6 歸因 | 實作階段發現缺陷時，歸因到 SOP、skill、spec 或 code，修對應層 | [references/checklists.md](references/checklists.md) |

## 邊界

本次呼叫交付到「spec 通過盲審」為止。實作是另一件事：本 agent 已讀過 SOP，
自己實作會破壞「spec 是唯一交接物」的原則。使用者要實作時，spawn 一個新 agent，
prompt 如下（換掉路徑）：

> 你是實作 agent。唯一的規格來源是 `<spec 路徑>`，先完整讀它。不要讀 SOP、
> 其他 spec 或任何「既有做法」——spec 沒寫的就是沒定義。照 spec 的
> 「架構與實作要求」一節交付；實作中發現 spec 未定義的行為，停下來回報，
> 不要自行決定。
