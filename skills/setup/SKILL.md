---
name: setup
description: 一次完成本機的 agent 環境設定：把團隊工作守則接到各 agent 的全域設定讓每個 session 自動載入，並安裝團隊選用的外部 skill repo。使用者第一次設定環境、要 setup、init、裝工作守則、安裝團隊 skills 時使用。
---

# 環境設定

兩件事一次做完：把本 skill 附帶的 [references/AGENTS.md](references/AGENTS.md)
工作守則接到本機各個 agent 的全域 context 檔（各家 CLI 每個 session 會自動載入
自己的全域檔，接上後守則即長期生效），並依 [references/skill-sources.md](references/skill-sources.md)
安裝團隊選用的外部 skills。使用者只要求其中一件時，只做那一件。

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

## 回報

列五類：守則已接上（附驗證輸出）、本機未安裝而略過的 agent、
需要使用者決定的衝突、已安裝的 skill 來源（附 CLI 輸出末段）、
安裝失敗的來源（附錯誤原文）。不產生其他檔案。
