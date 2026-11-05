"""Small persistent fake receiver; never accesses the real keyring or systemd."""
import json
import sys
from pathlib import Path

path = Path(__file__).with_name("fixture.json")
state = json.loads(path.read_text()) if path.exists() else {"running": False, "key": False}
action = sys.argv[1]
if action == "save-key":
    state["key"] = bool(sys.stdin.read())
elif action in ("start", "stop"):
    state["running"] = action == "start"
elif action == "status":
    print(json.dumps(dict(state, installed=True, unit=True, paired=False)))
else:
    raise SystemExit(1)
path.write_text(json.dumps(state))
