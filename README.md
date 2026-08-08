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
| [skill-author](skills/skill-author/SKILL.md) | 依團隊標準撰寫或改寫 skill：文字自然、描述欄位通過觸發測試、自檢機器化、試跑通過才交付 |
| [setup](skills/setup/SKILL.md) | 一次完成環境設定：把工作守則接到各 agent 的全域設定、安裝團隊選用的外部 skill repo |

`sop-author` 會讀 `../sop-to-spec/references/` 的共用規範（同一份範本只放一處），
兩個要一起裝。

## 初始設定

安裝完 skills 後，對任何一個 agent 說「幫我 setup」，它會照 `setup` 做三件事：

1. 把 [skills/setup/references/AGENTS.md](skills/setup/references/AGENTS.md)
   （精簡的 agent 工作守則：證據、改動紀律、停下來的時機）接到本機所有
   偵測到的 agent 全域設定，之後每個 session 自動載入。
2. 依 [skills/setup/references/skill-sources.md](skills/setup/references/skill-sources.md)
   的清單，把團隊選用的外部 skill repo 裝到使用者層級的所有 agent。
3. 在各 agent 接一個 session 啟動 hook，每天第一個 session 自動
   `npx skills update`——來源 repo 更新後，隔天所有 agent 就是新的，
   不用另行通知。

之後要加新的 skill 來源，改清單那份檔案再說一次「幫我 setup」即可。

## 與 kungfu 完整版的差異

- 檢查全部改成 SKILL.md 內的 grep/手動清單，不附 python script
- 無 pre-commit / hook 接法，無 marketplace / bundle，直接 `npx skills add`
