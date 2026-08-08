---
name: setup
description: 一次完成本機的 agent 環境設定：把團隊工作守則接到各 agent 的全域設定讓每個 session 自動載入、安裝團隊選用的外部 skill repo，並接上讓 skills 保持最新的自動更新 hook。使用者第一次設定環境、要 setup、init、裝工作守則、安裝團隊 skills、設定自動更新，或覺得裝好的 skills 過期想更新時使用。
---

# 環境設定

執行本體是 [references/sync.sh](references/sync.sh)：一支冪等的 script，
跑一次就完成全部設定，重跑收斂到同一狀態。它做三件事——

1. **接工作守則**：把 [references/AGENTS.md](references/AGENTS.md) 接到
   各 agent 的全域 context 檔，每個 session 自動載入。哪個 agent 接到
   哪個檔案、用 import 行還是 symlink，定義在
   [references/agents.txt](references/agents.txt)，一行一個 agent。
2. **接自動更新 hook**：在各 agent 接「跑 sync.sh」的 session 啟動 hook，
   目標與接法（settings.json 合併、TOML 附加、產生 script）同樣定義在
   agents.txt。以 `~/.cache/skills-update.stamp` 節流：每天第一個開啟的
   session 在背景收斂一輪，其餘 session 直接結束。無指令型 hook 的 agent
   （如 OpenCode）跳過——安裝是全域的，其他 agent 跑過它的 skills 就是新的。
3. **安裝團隊 skills**：照 [references/skill-sources.txt](references/skill-sources.txt)
   逐列 `npx -y skills add <repo> -g --all`，沒裝的裝上、裝過的更新成
   remote 最新。清單含本 repo，sync.sh 與兩個定義檔因此每天自我更新；
   之後新裝的 agent、新支援的 agent 定義，隔天都自動生效。

安全界線：只在 agent 的目錄已存在時動作，不替沒安裝的 agent 造設定；
設定檔一律無損合併，已有的一般檔案或別人的 script 一律不動、
印 `CONFLICT` 交給使用者決定。

## 步驟

1. 執行並附完整輸出：

   ```bash
   bash <本 skill 目錄>/references/sync.sh --now
   ```

   （`--now` 略過節流。hook 之後每天跑的是 store 裡的同一支：
   `~/.agents/skills/setup/references/sync.sh`。）
2. 轉述輸出：`ok`／`linked` 是接好的，`skip` 是本機未安裝的 agent，
   `FAILED:` 是安裝失敗的來源（附錯誤原文）。`CONFLICT` 逐條列給使用者
   決定；使用者決定後照其指示手動處理，再重跑一次 sync.sh 收斂。
3. 驗證並附輸出：再跑一次不帶 `--now` 的 sync.sh，證明 stamp 未過期時
   直接結束；抽驗一個 symlink（`readlink`）與一個 hook
   （`grep sync.sh <設定檔>`）。

## 回報

依步驟 2 的分類回報，附步驟 1、3 的輸出。不產生其他檔案。
