#!/usr/bin/env bash
# 依 skill-sources.txt 安裝／更新團隊 skills（沒裝的裝上、裝過的更新）。
# setup 首次執行用 --now；各 agent 的 session 啟動 hook 每天跑一次，
# 由 stamp 檔節流：24 小時內跑過就直接結束。
set -u
stamp="$HOME/.cache/skills-update.stamp"
if [ "${1:-}" != "--now" ]; then
  find "$stamp" -mtime -1 2>/dev/null | grep -q . && exit 0
fi
mkdir -p "$HOME/.cache" && touch "$stamp"
for repo in $(grep -vE '^[[:space:]]*(#|$)' "$(dirname "$0")/skill-sources.txt"); do
  npx -y skills add "$repo" -g --all </dev/null || echo "FAILED: $repo" >&2
done
