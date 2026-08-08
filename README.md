# kungfu-lite

輕量版 agent skills：純 markdown（`SKILL.md`＋必要的 `references/*.md`），
**無 script、無 hook、無 plugin 架構**。完整版（含機器 lint、pre-commit、marketplace）
在 [kungfu](https://github.com/tienyulin/kungfu)。

## 安裝

```bash
npx skills add tienyulin/kungfu-lite
```

只裝其中幾個：

```bash
npx skills add tienyulin/kungfu-lite --skill doc-author
```

## Skills

| Skill | 做什麼 |
|---|---|
| [sop-author](skills/sop-author/SKILL.md) | 訪談 PM，把粗略需求整理成合規 SOP；業務判斷只來自使用者，沒答的標「假設，待確認」 |
| [sop-to-spec](skills/sop-to-spec/SKILL.md) | 把 SOP 轉成正式的 API 規格書：主管讀前三節能看懂，工程師或 AI 讀全文能直接實作；含風險判定與盲審 |
| [doc-author](skills/doc-author/SKILL.md) | 幫 repo 寫 README.md（對外使用文件，單檔自足）與 `docs/ARCHITECTURE.md`（給維護者與 AI 的架構文件），API repo 另附 openapi.json |

`sop-author` 會讀 `../sop-to-spec/references/` 的共用規範（同一份範本只放一處），
兩個要一起裝。

## 與 kungfu 完整版的差異

- 檢查全部改成 SKILL.md 內的 grep/手動清單，不附 python script
- 無 pre-commit / hook 接法
- 無 marketplace / bundle，直接 `npx skills add`
