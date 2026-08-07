---
name: sop-author
description: Interview a PM to produce a template-conforming SOP — from a rough feature request or a non-conforming document. Asks plain-language questions section by section, never invents business rules (unanswered = marked 假設 pending confirmation), outputs docs/sops/<group>/<api>.md ready for sop-to-spec. Triggers - "寫 SOP", "SOP 訪談", "把需求整理成 SOP", "/sop-author <描述或檔案>", or when sop-to-spec rejects the input as not a valid SOP.
---

# SOP Author — 訪談產出合規 SOP

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] Step 1 素材判定＋讀規範
- [ ] Step 2 吸收既有素材（只搬不編）
- [ ] Step 3 訪談補洞（逐節、白話、一次一小組）
- [ ] Step 4 產出 SOP 檔（一檔一 API）
- [ ] Step 5 合格自檢
- [ ] Step 6 PM 過目確認 → 交付
```

把「粗略的需求描述」或「不合規的文件」變成合規 SOP。**你是訪談者＋記錄員，
不是需求的作者**——鐵律一條：

> **業務判斷只能出自使用者之口。** 他沒說的，你不准編；問了沒答的，照範本標
> 「（假設，待確認）」。你隨手編的一條規則，下游會全部當真做出來。

## 規範來源（先讀）

- 撰寫指南：[../sop-to-spec/references/sop-authoring-guide.md](../sop-to-spec/references/sop-authoring-guide.md)
- 空白骨架：[../sop-to-spec/references/sop-template.md](../sop-to-spec/references/sop-template.md)

（本 skill 與 `sop-to-spec` 共用同一份規範，單一來源。路徑不存在＝sop-to-spec
未安裝 → 停下請使用者先裝，不要憑記憶重建範本。）

## 流程

| Step | 做什麼 |
|------|--------|
| 1 素材判定 | 讀指南＋骨架。看使用者給的是什麼：(a) 幾句粗略描述 (b) 不合規文件 (c) 已合規 SOP → (c) 直接告知「已合格，用 sop-to-spec 轉 spec 即可」結束本 skill |
| 2 吸收素材 | 把使用者已給的資訊**原樣**對號入座填進骨架（措辭可整理，語意不可加料）。描述裡混了**多個功能** → 按「一檔一 API、同組同資料夾」拆成多份草稿，拆法先跟使用者確認一次 |
| 3 訪談補洞 | 對每份草稿，照骨架節順序把**還空著的節**逐一問完：白話提問（照指南的問法與例子）、一次一小組（同一節的問題一起問，不要一次倒全部）、追問到可執行（「出錯怎麼辦」答「再看看」→ 追問「擋下？照做？找誰？」）。**選填節不是跳過，是問過「有沒有」才能刪**——尤其「範圍外／已知的怪現象」必問一次（問法：「做完之後會不會出現看起來怪怪但其實正常的現象？有沒有相關但這次不做的事？」——實測連兩輪都漏這節，全靠 PM 最終過目才補回）。問了沒答 → 該格標「（假設，待確認：<你的暫行假設>）」，假設取更嚴方向 |
| 4 產出 | 寫到 `docs/sops/<組名>/<功能>.md`（組名跟使用者確認；資料夾不存在就建）。刪光範本的 `> 提示：` 行 |
| 5 自檢 | 逐份檢查：必要節齊（做什麼、誰可以用、輸入或明寫「無」、輸出、步驟每步有「怎麼做」、可能出什麼錯、測試例子）＋測試例子覆蓋規則（成功≥1；開始前確認、出錯、每步出錯欄各條有對應例子）。缺 → 回 Step 3 補問 |
| 6 確認交付 | 請使用者過目：「照你說的整理的，**特別看標『假設，待確認』的地方**」。他改就改；他**拍板定案的每一項**，改完後全文 grep 對應的「（假設，待確認）」標記**確認清到零**（拍板 N 項就要少 N 個標記——漏清的標記會讓下游把定案當未定）。**明確說 OK 才算交付**。要繼續轉 spec → 指路 `sop-to-spec`（不要在本 skill 裡直接轉——轉 spec 有自己的檢查與盲審流程） |

## 報告模板（Step 6 交付時照抄填空）

```
SOP READY: <路徑清單，一檔一行>
COVERED: <訪談問到答案的節數> / ASSUMED: <標假設的格數，0 最好>
NEXT: 確認無誤後用 sop-to-spec 轉 spec
```

## 本 skill 的邊界

- 只產 SOP，不產 spec、不寫 code。
- 不做技術審查——SOP 合不合理是業務的事，訪談時發現明顯矛盾（例：說能反悔又說刪了救不回）
  要**當場指出請使用者選一邊**，但選擇權在他。
- 系統機械面（登入、並發、冪等、log）照指南分工：不問 PM、不寫進 SOP。
