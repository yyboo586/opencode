#!/usr/bin/env python3
"""tool-stats 历史统计：从 opencode.db 复算插件上线前的工具调用分布。

用法：
  python3 stats-history.py                      # 全量
  python3 stats-history.py --since 2026-09-01   # 本地日期（含）起
  python3 stats-history.py --db /path/to.db
依赖：python3 内置模块。
"""
import argparse
import collections
import datetime
import json
import re
import sqlite3
from pathlib import Path

DEFAULT_DB = Path.home() / ".local/share/opencode/opencode.db"


def first_word(tool, part):
    if tool not in ("bash", "shell"):
        return None
    cmd = ((part.get("state") or {}).get("input") or {}).get("command")
    if not isinstance(cmd, str):
        return None
    m = re.match(r"^(?:\w+=\S+\s+)*([^\s|;&]+)", cmd.strip())
    return m.group(1).rsplit("/", 1)[-1] if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="本地日期 YYYY-MM-DD（含）")
    ap.add_argument("--db", default=str(DEFAULT_DB))
    args = ap.parse_args()

    since = 0
    if args.since:
        since = int(datetime.datetime.strptime(args.since, "%Y-%m-%d").timestamp() * 1000)

    con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    tools = collections.Counter()
    words = collections.Counter()
    total = 0
    for data, tc in con.execute(
        "SELECT data, time_created FROM session_message WHERE type='assistant'"
    ):
        if tc < since:
            continue
        try:
            msg = json.loads(data)
        except Exception:
            continue
        for part in msg.get("content", []):
            if not isinstance(part, dict) or part.get("type") != "tool":
                continue
            name = part.get("name", "?")
            tools[name] += 1
            total += 1
            w = first_word(name, part)
            if w:
                words[w] += 1

    print(f"工具调用总量: {total}" + (f"（since {args.since}）" if args.since else ""))
    print("\n== 工具分布 top 20 ==")
    for k, v in tools.most_common(20):
        print(f"{v:7d}  {k}")
    print("\n== shell/bash 命令词 top 50 ==")
    for k, v in words.most_common(50):
        print(f"{v:7d}  {k}")


if __name__ == "__main__":
    main()
