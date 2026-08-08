#!/usr/bin/env bash
# setup 的執行本體：接工作守則、接各 agent 的 session 啟動 hook、
# 照 skill-sources.txt 安裝／更新團隊 skills。冪等，重跑收斂到同一狀態；
# 各 agent 的 hook 每天跑一次，stamp 檔節流，--now 略過節流。
# 各 agent 的接線定義在 agents.json；只在 agent 的偵測目錄已存在時動作，
# 無法無損處理的項目印 CONFLICT，不動原檔。
# 輸出格式：<項目> <agent>: ok（已接好）| linked（本次接上）| skip | CONFLICT。
set -u
here="$(cd "$(dirname "$0")" && pwd)"
STORE="$HOME/.agents/skills/setup/references"
RULES="$STORE/AGENTS.md"
SYNC="$STORE/sync.sh"
HOOK_CMD="bash $SYNC >/dev/null 2>&1 &"
STAMP="$HOME/.cache/skills-update.stamp"

if [ "${1:-}" != "--now" ]; then
  find "$STAMP" -mtime -1 2>/dev/null | grep -q . && exit 0
fi
mkdir -p "$HOME/.cache" && touch "$STAMP"

expand() { printf '%s' "${1/#\~/$HOME}"; }

hook_json() { # $1=settings.json $2=name 欄（空字串＝不加）：無損合併，已有就印 ok
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

python3 - "$here/agents.json" <<'PY' |
import json, sys
for a in json.load(open(sys.argv[1]))["agents"]:
    print(a["name"], a["detect"], a["rules_target"], a["rules_method"],
          a["hook_target"], a["hook_method"])
PY
while read -r name detect rtgt rmeth htgt hmeth; do
  detect=$(expand "$detect"); rtgt=$(expand "$rtgt"); htgt=$(expand "$htgt")
  if [ ! -d "$detect" ]; then echo "$name: skip（未安裝）"; continue; fi

  case "$rmeth" in
    import)
      if grep -qsF "@$RULES" "$rtgt"; then echo "rules $name: ok"
      else printf '\n@%s\n' "$RULES" >> "$rtgt"; echo "rules $name: linked"; fi ;;
    symlink)
      if [ ! -d "$(dirname "$rtgt")" ]; then echo "rules $name: skip（目錄不存在）"
      elif [ -L "$rtgt" ]; then ln -sfn "$RULES" "$rtgt"; echo "rules $name: ok"
      elif [ -e "$rtgt" ]; then echo "CONFLICT rules $name: $rtgt 已是一般檔案，未動"
      else ln -s "$RULES" "$rtgt"; echo "rules $name: linked"; fi ;;
  esac

  case "$hmeth" in
    none) echo "hook $name: skip（無指令型 hook）" ;;
    json|json-named)
      n=""; [ "$hmeth" = "json-named" ] && n="skills-update"
      r=$(hook_json "$htgt" "$n" 2>/dev/null) || r="CONFLICT: $htgt 解析失敗，未動"
      echo "hook $name: $r" ;;
    toml)
      if grep -qs "$SYNC" "$htgt"; then echo "hook $name: ok"
      else
        printf '\n[[hooks.SessionStart]]\nmatcher = "*"\ncommand = "%s"\n' "$HOOK_CMD" >> "$htgt"
        echo "hook $name: linked"
      fi ;;
    script) # 目標是整支 script 的 hook（如 Cline TaskStart），只覆寫自己產生的
      mkdir -p "$(dirname "$htgt")"
      if [ -f "$htgt" ] && ! grep -q "skills-setup managed" "$htgt"; then
        echo "CONFLICT hook $name: $htgt 已有其他 script，未動"
      else
        printf '#!/usr/bin/env bash\n# skills-setup managed\ncat >/dev/null\n%s\necho '\''{"cancel": false}'\''\n' "$HOOK_CMD" > "$htgt"
        chmod +x "$htgt"
        echo "hook $name: ok"
      fi ;;
  esac
done

# —— skills：沒裝的裝上、裝過的更新成 remote 最新 ——
# 清單含本 repo，store（含本 script 與兩個定義檔）因此同批自我更新。
# 這段必須留在檔案最後：覆蓋執行中的自己才安全。
for repo in $(grep -vE '^[[:space:]]*(#|$)' "$here/skill-sources.txt"); do
  npx -y skills add "$repo" -g --all </dev/null || echo "FAILED: $repo" >&2
done
