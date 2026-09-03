#!/bin/sh
# Upsert the Hyper rule from hyper.json into the selected Karabiner profile.
# Matched by description; other rules and settings are left alone. Karabiner
# reloads karabiner.json on change. Usage: merge-hyper.sh [hyper.json]
set -eu
rule=${1:-"$(dirname "$0")/hyper.json"}
cfg="$HOME/.config/karabiner/karabiner.json"
python3 - "$rule" "$cfg" <<'PY'
import json, sys
rule = json.load(open(sys.argv[1]))
cfg_path = sys.argv[2]
cfg = json.load(open(cfg_path))
profiles = cfg.setdefault("profiles", [])
prof = next((p for p in profiles if p.get("selected")), profiles[0] if profiles else None)
if prof is None:
    prof = {"name": "Default profile", "selected": True}
    profiles.append(prof)
rules = prof.setdefault("complex_modifications", {}).setdefault("rules", [])
rules[:] = [r for r in rules if r.get("description") != rule["description"]
            and not any(m.get("from", {}).get("key_code") == "caps_lock" for m in r.get("manipulators", []))]
rules.insert(0, rule)
json.dump(cfg, open(cfg_path, "w"), indent=4, ensure_ascii=False)
open(cfg_path, "a").write("\n")
PY
