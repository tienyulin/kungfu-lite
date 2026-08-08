#!/usr/bin/env bash
# setup 的執行本體：接工作守則、接各 agent 的 session 啟動 hook、
# 照 skill-sources.txt 安裝／更新團隊 skills。冪等，重跑收斂到同一狀態；
# 各 agent 的 hook 每天跑一次，stamp 檔節流，--now 略過節流。
# 只在 agent 的目錄已存在時動作；無法無損處理的項目印 CONFLICT，不動原檔。
# 輸出格式：<項目> <agent>: ok（已接好）| linked（本次接上）| skip | CONFLICT。
set -u
STORE="$HOME/.agents/skills/setup/references"
RULES="$STORE/AGENTS.md"
SYNC="$STORE/sync.sh"
HOOK_CMD="bash $SYNC >/dev/null 2>&1 &"
STAMP="$HOME/.cache/skills-update.stamp"

if [ "${1:-}" != "--now" ]; then
  find "$STAMP" -mtime -1 2>/dev/null | grep -q . && exit 0
fi
mkdir -p "$HOME/.cache" && touch "$STAMP"

# —— 工作守則：Claude Code 用 import 行，其餘 symlink 指向 store 的正本 ——
if [ -d "$HOME/.claude" ]; then
  f="$HOME/.claude/CLAUDE.md"
  if grep -qsF "@$RULES" "$f"; then echo "rules claude: ok"
  else printf '\n@%s\n' "$RULES" >> "$f"; echo "rules claude: linked"; fi
else echo "rules claude: skip（未安裝）"; fi

link_rules() { # $1=agent $2=目錄 $3=檔名
  if [ ! -d "$2" ]; then echo "rules $1: skip（未安裝）"; return; fi
  local t="$2/$3"
  if [ -L "$t" ]; then ln -sfn "$RULES" "$t"; echo "rules $1: ok"
  elif [ -e "$t" ]; then echo "CONFLICT rules $1: $t 已是一般檔案，未動"
  else ln -s "$RULES" "$t"; echo "rules $1: linked"; fi
}
link_rules codex    "$HOME/.codex" AGENTS.md
link_rules gemini   "$HOME/.gemini" GEMINI.md
link_rules opencode "$HOME/.config/opencode" AGENTS.md
link_rules cline    "$HOME/Documents/Cline/Rules" AGENTS.md

# —— session hook：settings.json 用 python 無損合併，TOML 檔尾附加 ——
hook_json() { # $1=settings.json $2=name 欄（空字串＝不加）
  python3 - "$1" "$SYNC" "$2" <<'PY'
import json, os, sys
path, sync, name = sys.argv[1], sys.argv[2], sys.argv[3]
d = {}
if os.path.exists(path):
    with open(path) as f:
        d = json.load(f)
arr = d.setdefault("hooks", {}).setdefault("SessionStart", [])
for entry in arr:
    for h in entry.get("hooks", []):
        if sync in h.get("command", ""):
            print("ok"); sys.exit()
inner = {"type": "command", "command": f"bash {sync} >/dev/null 2>&1 &"}
if name:
    inner["name"] = name
arr.append({"matcher": "startup", "hooks": [inner]})
with open(path, "w") as f:
    json.dump(d, f, indent=2); f.write("\n")
print("linked")
PY
}
if [ -d "$HOME/.claude" ]; then
  r=$(hook_json "$HOME/.claude/settings.json" "" 2>/dev/null) \
    || r="CONFLICT: settings.json 解析失敗，未動"
  echo "hook claude: $r"
else echo "hook claude: skip（未安裝）"; fi
if [ -d "$HOME/.gemini" ]; then
  r=$(hook_json "$HOME/.gemini/settings.json" "skills-update" 2>/dev/null) \
    || r="CONFLICT: settings.json 解析失敗，未動"
  echo "hook gemini: $r"
else echo "hook gemini: skip（未安裝）"; fi

if [ -d "$HOME/.codex" ]; then
  f="$HOME/.codex/config.toml"
  if grep -qs "$SYNC" "$f"; then echo "hook codex: ok"
  else
    printf '\n[[hooks.SessionStart]]\nmatcher = "*"\ncommand = "%s"\n' "$HOOK_CMD" >> "$f"
    echo "hook codex: linked"
  fi
else echo "hook codex: skip（未安裝）"; fi

# Cline 的 TaskStart 每個 hook 只接受一支 script，只覆寫自己產生的那支
if [ -d "$HOME/Documents/Cline" ]; then
  mkdir -p "$HOME/Documents/Cline/Hooks"
  t="$HOME/Documents/Cline/Hooks/TaskStart"
  if [ -f "$t" ] && ! grep -q "skills-setup managed" "$t"; then
    echo "CONFLICT hook cline: $t 已有其他 script，未動"
  else
    printf '#!/usr/bin/env bash\n# skills-setup managed\ncat >/dev/null\n%s\necho '\''{"cancel": false}'\''\n' "$HOOK_CMD" > "$t"
    chmod +x "$t"
    echo "hook cline: ok"
  fi
else echo "hook cline: skip（未安裝）"; fi

# —— skills：沒裝的裝上、裝過的更新成 remote 最新 ——
# 清單含本 repo，store（含本 script 與守則正本）因此同批自我更新。
# 這段必須留在檔案最後：覆蓋執行中的自己才安全。
for repo in $(grep -vE '^[[:space:]]*(#|$)' "$(dirname "$0")/skill-sources.txt"); do
  npx -y skills add "$repo" -g --all </dev/null || echo "FAILED: $repo" >&2
done
