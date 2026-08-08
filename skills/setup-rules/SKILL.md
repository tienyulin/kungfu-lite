---
name: setup-rules
description: 把團隊工作守則（references/AGENTS.md）安裝到本機各 agent 的全域設定，讓每個 session 自動載入。使用者要裝工作守則、安裝守則、setup rules、把守則套用到所有 agent 時使用。
---

# 安裝工作守則

把本 skill 附帶的 [references/AGENTS.md](references/AGENTS.md) 接到本機各個
agent 的全域 context 檔。各家 CLI 每個 session 會自動載入自己的全域檔，
接上後守則即長期生效。

## 步驟

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

## 回報

列三類：已接上（附驗證輸出）、本機未安裝而略過的 agent、
需要使用者決定的衝突。不產生其他檔案。
