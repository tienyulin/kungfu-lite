---
name: release-note
description: 根據兩個 Git tag 之間的 commit（Conventional Commits 格式）產生客戶版本說明文件（docs/release-notes/<版本號>.md），自動分類新功能、改進、問題修正，標記 breaking changes 的升級注意。工程師發版前使用。
---

# Release Note 生成

從兩個 Git tag 間的 commit 整理版本說明，產出給客戶看的 Markdown 文件。

```
進度：
- [ ] 確認版本號
- [ ] 取得 commit log
- [ ] 分類與標準化
- [ ] 確認異常情況
- [ ] 產生文件
```

## 版本號取得

詢問使用者希望生成的版本號（新版本）。如果使用者同時提供舊版本號，直接使用；否則執行 `git describe --tags --abbrev=0 HEAD~1` 取得上一個版本號。

確認兩個版本都存在：

```bash
git rev-parse <舊版本號>
git rev-parse <新版本號>
```

若查詢失敗，停止並報告該版本號無法找到。

## 解析 Commit Log

執行取得兩版本間的 commit：

```bash
git log <舊版本號>..<新版本號> --format='%H|%s|%b' --no-merges
```

輸出每一行為 `<commit-hash>|<主旨>|<本文>`。根據 Conventional Commits 格式解析主旨：

- **格式**：`<type>(<scope>)?: <description>` 或 `<type>: <description>`
- **識別欄位**：type（必須）、scope（可選）、description（必須）
- **有效 type**：`feat`、`fix`、`refactor`、`perf`、`docs`、`test`、`chore`、`ci` 等

提取規則：
- `feat` → 新功能分類
- `fix` → 問題修正分類
- `refactor` → 檢查是否對使用者有可感知的效益（例：變快、變穩、介面改善）；有則列入改進分類並改寫為使用者視角，無則略去
- `perf` → 改進分類（性能提升對使用者可感知）
- `docs`、`test`、`chore`、`ci` → 完全略去（對客戶無感）
- 其他 → 查看本文是否有 `BREAKING CHANGE` 標記，有則標記為重要變更

## 內容檢查與互動

遇到以下情況時，停止並提示使用者確認：

**情況 1：commit 訊息無法解析或描述不夠清楚**

列舉無法處理的 commit（包括 hash、原始主旨與本文），問使用者這些改動應該分類到哪一類（新功能／改進／問題修正），或是否應該排除。

**情況 2：偵測到 breaking change**

掃描 commit 本文或 description 中是否包含：
- 明確的 `BREAKING CHANGE:` 標記
- 常見破壞性變更的詞（例：刪除、移除 API、修改參數、升級依賴版本等）

找到 breaking change 時，列出該 commit 與具體內容，詢問：
- 這是有意的破壞性變更嗎？
- 受影響的功能或組件是什麼？
- 使用者升級時需要執行哪些步驟？（例：資料遷移、依賴更新、設定調整）

根據使用者回應更新該項內容的描述。

## 標準化與組織

所有項目一律改寫成使用者可感知的描述，不照搬 commit 原文。根據分類結果組織內容：

- **新功能**：改寫為使用者視角，突出功能價值；移除內部代號、API 路徑、參數名稱等技術細節
- **改進**：描述對使用者的實際效益（速度提升、穩定性改善、介面優化），去掉純內部的技術細節
- **問題修正**：簡述問題現象與解決後的效果，避免技術術語
- **重要變更與升級注意**（如有 breaking change）：詳述對使用者的影響與升級步驟

全文用白話文，避免技術術語與內部概念。

## 文件產生

根據以上內容產生 Markdown 文件，路徑為 `docs/release-notes/<新版本號>.md`，結構如下：

```markdown
# <新版本號> 版本說明

## 新功能

- （列舉每一項，一句敘述）

## 改進

- （列舉每一項，一句敘述）

## 問題修正

- （列舉每一項，簡述問題與修法）

## 重要變更與升級注意

（僅在有 breaking change 時出現）

**受影響功能**：<描述>

**升級步驟**：
1. <步驟>
2. <步驟>
```

若沒有某一分類的項目，該節點省略不寫。執行完成後，報告產生的檔案路徑與摘要。

## 邊界與限制

- 本 skill 只產生文件，不發佈、不提交 commit、不推送到遠端。
- commit 訊息必須遵循 Conventional Commits 格式，否則無法自動分類。
- 版本號必須是有效的 Git tag，使用者需確保版本號無誤。
