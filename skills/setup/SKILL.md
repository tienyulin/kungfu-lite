---
name: setup
description: 一次完成本機的 agent 環境設定：把團隊工作守則接到各 agent 的全域設定讓每個 session 自動載入、安裝團隊選用的外部 skill repo，並接上讓 skills 保持最新的自動更新 hook。使用者第一次設定環境、要 setup、init、裝工作守則、安裝團隊 skills、設定自動更新，或覺得裝好的 skills 過期想更新時使用。
---

# 環境設定

三件事一次做完：把本 skill 附帶的 [references/AGENTS.md](references/AGENTS.md)
工作守則接到本機各個 agent 的全域 context 檔（各家 CLI 每個 session 會自動載入
自己的全域檔，接上後守則即長期生效）、依 [references/skill-sources.md](references/skill-sources.md)
安裝團隊選用的外部 skills、接上每日自動更新的 hook。
使用者只要求其中一部分時，只做那一部分。

## 安裝工作守則

1. 確認來源檔存在：本 skill 目錄下的 `references/AGENTS.md`，取得絕對路徑。
2. 逐一檢查下表的目標。只在目標所在目錄已存在時動作；目錄不存在代表
   該 agent 沒安裝，列入略過。全程不建立任何目錄——建了目錄等於
   替沒安裝的 agent 造設定，是錯誤不是完成。

   | Agent | 目標 | 接法 |
   |-------|------|------|
   | Claude Code | `~/.claude/CLAUDE.md` | 檔尾加一行 `@<來源絕對路徑>`（import） |
   | Codex | `~/.codex/AGENTS.md` | symlink 指向來源 |
   | Gemini CLI | `~/.gemini/GEMINI.md` | symlink 指向來源 |
   | OpenCode | `~/.config/opencode/AGENTS.md` | symlink 指向來源 |
   | Cline | `~/Documents/Cline/Rules/AGENTS.md` | symlink 指向來源 |

3. 已經接好的（import 行已存在、symlink 已指向來源）跳過，不重複加。
4. 目標位置已有一般檔案（不是 symlink、也還沒 import）：不覆蓋，
   列出該檔案請使用者決定——併入、改用 import、還是略過。
5. 完成後執行一次驗證並附輸出：處理過的目標，symlink 用 `readlink`
   確認指向來源、import 用 `grep` 確認該行存在；略過的 agent 用
   `test -d` 確認其目錄仍然不存在。

## 安裝外部 skills

6. 讀 `references/skill-sources.md` 的清單，逐列執行：

   ```bash
   npx -y skills add <repo> -g --all
   ```

   安裝到使用者層級、所有偵測到的 agent。已安裝過的照跑，CLI 會自行更新。
7. 某一列失敗（網路、repo 不存在）就記下錯誤原文，繼續跑下一列，
   最後一併回報，不中斷整個流程。

## 接自動更新 hook

裝好的 skills 是快照，來源 repo 更新後要靠 `npx skills update` 拉新。
在各 agent 接一個 session 啟動時執行的 hook 讓這件事自動發生：
所有 agent 共用同一行指令與同一個 stamp 檔，每天第一個開啟的 session
在背景更新一次（`-g` 是全域更新，所有 agent 的 skills 同批更新），
其餘 session 看到 stamp 未過期就直接跳過。

8. Hook 指令，各家都用這一行：

   ```bash
   find ~/.cache/skills-update.stamp -mtime -1 2>/dev/null | grep -q . || { mkdir -p ~/.cache && touch ~/.cache/skills-update.stamp && npx -y skills update -g -y >/dev/null 2>&1 & }
   ```

   逐一接到下表的目標。安裝判斷同步驟 2：agent 的目錄已存在才動作，
   否則列入略過。

   | Agent | 目標 | 接法 |
   |-------|------|------|
   | Claude Code | `~/.claude/settings.json` | `hooks.SessionStart` 陣列加下方 JSON 物件 |
   | Gemini CLI | `~/.gemini/settings.json` | 同下方 JSON 物件，內層 hook 多加 `"name": "skills-update"` 欄 |
   | Codex | `~/.codex/config.toml` | 檔尾加 `[[hooks.SessionStart]]` 區塊：`matcher = "*"`、`command` 為上列指令 |
   | Cline | `~/Documents/Cline/Hooks/TaskStart` | 產生下方 script 並 `chmod +x`；`~/Documents/Cline` 存在才算已安裝，`Hooks/` 不存在就建 |

   Claude Code 與 Gemini 的 hook 物件是兩層結構，照這個形狀放進
   `hooks.SessionStart` 陣列，不省略外層：

   ```json
   { "matcher": "startup", "hooks": [{ "type": "command", "command": "<步驟 8 的指令>" }] }
   ```

   Cline 的 TaskStart 是一支可執行 script，stdin 要讀掉、stdout 必須是 JSON：

   ```bash
   #!/usr/bin/env bash
   cat >/dev/null
   find ~/.cache/skills-update.stamp -mtime -1 2>/dev/null | grep -q . || { mkdir -p ~/.cache && touch ~/.cache/skills-update.stamp && npx -y skills update -g -y >/dev/null 2>&1 & }
   echo '{"cancel": false}'
   ```

9. 修改設定檔的紀律：JSON 與 TOML 一律讀入、修改、寫回（jq 或 python 皆可），
   保留既有的鍵與 hooks，不整檔覆寫；目標檔不存在但 agent 目錄存在，就建只含
   這個 hook 的最小設定檔。指令已在檔中（以 stamp 檔路徑判斷）就跳過。
   無法無損合併的情況——例如 Cline 的 TaskStart 已有別人的 script
   （它每個 hook 只接受一支）——不動原檔，列出請使用者決定。
   OpenCode 沒有指令型 hook，列入略過；更新是全域的，
   其他 agent 跑過它的 skills 就是新的。
10. 驗證並附輸出：每個接過的目標 `grep skills-update.stamp` 確認 hook 已在
    檔中；手動執行一次 hook 指令，`ls -l` stamp 檔證明生成，立刻再執行一次
    證明 stamp 未過期時不重跑。

## 回報

列六類：守則已接上（附驗證輸出）、本機未安裝而略過的 agent、
需要使用者決定的衝突、已安裝的 skill 來源（附 CLI 輸出末段）、
安裝失敗的來源（附錯誤原文）、自動更新 hook 接到哪幾家（附驗證輸出）。
不產生其他檔案。
