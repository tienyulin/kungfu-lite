# 外部 skill 來源

`setup` 依這份清單安裝外部 skills，每列執行
`npx -y skills add <repo> -g --all`。要新增來源，加一列即可。

Repo 欄接受三種寫法：GitHub 縮寫（`owner/repo`）、完整 https URL、
完整 ssh URL（例 `git@github.com:org/repo.git`）。private 或內部 git server
的 repo 用 ssh URL，前提是本機已設好對該 server 的 ssh key。

| Repo | 內容 |
|------|------|
| obra/superpowers | 通用工程工作流：brainstorming、systematic debugging、TDD 等 |
| forrestchang/andrej-karpathy-skills | 依 Andrej Karpathy 的建議整理的寫作與工程習慣 |
