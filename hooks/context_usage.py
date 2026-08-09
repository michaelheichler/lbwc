"""PostToolUse hook: sample session context occupancy into .lbwc-planning/.context-usage.

Writes the pipe-delimited record `session_id|used_pct|ctx_size_tokens` that
scripts/lib/resolve-caveman-level.sh parses to drive caveman auto mode.
Estimate is transcript bytes / chars-per-token / context window. Fail-open:
any error exits 0 silently, a usage tracker never gates work.
"""
import json
import os
import sys

CHARS_PER_TOKEN = 4
DEFAULT_CONTEXT_WINDOW = 200000
USAGE_FILENAME = ".context-usage"


def _find_planning_dir(start):
    current = os.path.abspath(start or os.getcwd())
    while True:
        candidate = os.path.join(current, ".lbwc-planning")
        if os.path.isdir(candidate):
            return candidate
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent


def _context_window(planning_dir):
    config_path = os.path.join(planning_dir, "config.json")
    try:
        with open(config_path) as config_file:
            value = json.load(config_file).get("context_window_tokens")
        if isinstance(value, int) and value > 0:
            return value
    except (OSError, ValueError):
        pass
    return DEFAULT_CONTEXT_WINDOW


def main():
    try:
        data = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    transcript = data.get("transcript_path") or ""
    if not transcript or not os.path.isfile(transcript):
        sys.exit(0)

    planning_dir = _find_planning_dir(data.get("cwd"))
    if not planning_dir:
        sys.exit(0)

    session_id = str(data.get("session_id") or "unknown")
    ctx_size = _context_window(planning_dir)

    try:
        used_tokens = os.path.getsize(transcript) // CHARS_PER_TOKEN
    except OSError:
        sys.exit(0)

    used_pct = min(100, max(0, used_tokens * 100 // ctx_size))

    usage_path = os.path.join(planning_dir, USAGE_FILENAME)
    tmp_path = usage_path + ".tmp"
    try:
        with open(tmp_path, "w") as usage_file:
            usage_file.write("{}|{}|{}\n".format(session_id, used_pct, ctx_size))
        os.replace(tmp_path, usage_path)
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    sys.exit(0)


if __name__ == "__main__":
    main()
