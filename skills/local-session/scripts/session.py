#!/usr/bin/env python3
"""local-session: read one opencode session from the local viewer API.

Default flow is summary-first: locate a session, print its turn summary, then
drill into one turn, one step (request snapshot), or one raw message on demand.

Data sources
  viewer  http://127.0.0.1:7788  (rich: timeline / request / llm segments)
  sqlite  ~/.local/share/opencode/opencode.db  (always available, list/raw only)
"""

import argparse
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

VIEWER = os.environ.get("VIEWER_URL", "http://127.0.0.1:7788").rstrip("/")
DB = os.environ.get("OPENCODE_DB", os.path.expanduser("~/.local/share/opencode/opencode.db"))
PAGE = 50


# ---------- formatting ----------
def fmt_tokens(n):
    n = int(n or 0)
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def fmt_bytes(n):
    n = int(n or 0)
    if n >= 1048576:
        return f"{n / 1048576:.1f}MB"
    if n >= 1024:
        return f"{n / 1024:.1f}KB"
    return f"{n}B"


def fmt_time(ms):
    try:
        return datetime.fromtimestamp(int(ms) / 1000).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return "—"


def fmt_date(ms):
    try:
        return datetime.fromtimestamp(int(ms) / 1000).strftime("%Y-%m-%d")
    except Exception:
        return ""


def cut(s, n):
    s = " ".join((s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"


def cell(s, n):
    """One markdown table cell: collapse whitespace and escape pipes."""
    return cut((s or "").replace("|", "\\|"), n)


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


# ---------- data sources ----------
def api(path, **params):
    url = VIEWER + path
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        die(f"viewer {e.code}: {url}", 2)
    except Exception as e:
        die(f"viewer 不可用：{e}\n启动：session-viewer（127.0.0.1:7788）后重试，或设置 VIEWER_URL", 2)


def api_up():
    try:
        with urllib.request.urlopen(VIEWER + "/api/meta", timeout=3) as r:
            return r.status == 200
    except Exception:
        return False


def db():
    if not os.path.exists(DB):
        die(f"找不到 opencode.db：{DB}", 2)
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def session_is_v2(con, sid):
    n = con.execute("SELECT COUNT(*) FROM session_v2 WHERE id=?", (sid,)).fetchone()[0]
    return n > 0


# ---------- message helpers ----------
def part_list(m):
    out = []
    for p in m.get("parts") or []:
        if isinstance(p, dict):
            out.append(p)
    return out


def part_text(p):
    if p.get("type") == "text" or p.get("type") == "reasoning":
        return p.get("text") or ""
    return ""


def msg_text(m):
    d = m.get("data") or {}
    if m.get("role") == "user" and d.get("text"):
        return d["text"]
    texts = [part_text(p) for p in part_list(m) if p.get("type") == "text"]
    return "\n".join(t for t in texts if t)


def tool_name(p):
    return p.get("name") or p.get("tool") or "?"


def tool_output_text(st):
    if not isinstance(st, dict):
        return ""
    out = st.get("output")
    if isinstance(out, str):
        return out
    if out is not None:
        return json.dumps(out, ensure_ascii=False)
    c = st.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
    return ""


def tool_input_text(st):
    if not isinstance(st, dict):
        return ""
    inp = st.get("input")
    if isinstance(inp, dict):
        for key in ("command", "filePath", "path", "pattern", "url"):
            if inp.get(key):
                return str(inp[key])
        return json.dumps(inp, ensure_ascii=False)
    return str(inp or "")


def render_tools(m, trunc=160):
    lines = []
    for p in part_list(m):
        if p.get("type") != "tool":
            continue
        st = p.get("state") or {}
        name = tool_name(p)
        inp = cut(tool_input_text(st), 100)
        out = tool_output_text(st)
        suffix = f" → {fmt_bytes(len(out.encode()))}"
        preview = cut(out, trunc)
        lines.append(f"- tool `{name}`: {inp}{suffix}" + (f"\n  ```\n  {preview}\n  ```" if preview else ""))
    return lines


# ---------- commands ----------
def cmd_list(args):
    if api_up():
        # 按日期过滤时要多取一些，否则目标日期可能落在 limit 之外
        fetch_limit = max(args.limit, 100) if args.date else args.limit
        data = api("/api/sessions", q=args.query or None, limit=fetch_limit)
        items = data.get("items", [])
        if args.date:
            items = [x for x in items if fmt_date(x.get("time_updated", 0)) == args.date]
        items = items[: args.limit]
        if not items:
            print("（没有匹配的会话）")
            return
        print("| updated | title | id | msgs | directory |")
        print("|---|---|---|---|---|")
        for x in items:
            print(f"| {fmt_time(x.get('time_updated'))} | {cell(x.get('title') or '(untitled)', 60)} | `{x.get('id')}` | "
                  f"{x.get('message_count', 0)} | {x.get('directory', '')} |")
        return

    con = db()
    rows = con.execute(
        "SELECT id, COALESCE(title,''), COALESCE(directory,''), time_updated FROM session_v2 "
        "UNION ALL SELECT id, COALESCE(title,''), COALESCE(directory,''), time_updated FROM session"
    ).fetchall()
    seen, items = set(), []
    for r in sorted(rows, key=lambda x: x[3] or 0, reverse=True):
        if r[0] in seen:
            continue
        seen.add(r[0])
        if args.query and args.query.lower() not in (r[1] or "").lower():
            continue
        if args.date and fmt_date(r[3]) != args.date:
            continue
        items.append(r)
        if len(items) >= args.limit:
            break
    print("（viewer 不可用，SQLite 兜底：无消息数）")
    print("| updated | title | id | directory |")
    print("|---|---|---|---|")
    for r in items:
        print(f"| {fmt_time(r[3])} | {cell(r[1] or '(untitled)', 60)} | `{r[0]}` | {r[2]} |")


def cmd_summary(args):
    sess = api(f"/api/sessions/{args.session}")["session"]
    tl = api(f"/api/sessions/{args.session}/timeline")
    t = tl.get("totals") or {}
    print(f"## {sess.get('title') or '(untitled)'}")
    print(f"`{sess.get('id')}` · {sess.get('directory')} · {sess.get('model_id') or '?'}@"
          f"{sess.get('provider_id') or '?'} · {sess.get('agent') or '?'} · "
          f"{fmt_time(sess.get('time_created'))} → {fmt_time(sess.get('time_updated'))}")
    print()
    print(f"**总览**：{t.get('turns', 0)} 问 / {t.get('steps', 0)} 步 / {t.get('tool_calls', 0)} 次工具 · "
          f"峰值 {fmt_tokens(t.get('peak_context'))} tokens · 账单 {fmt_tokens(t.get('billed_tokens'))} tokens · "
          f"${(t.get('cost') or 0):.4f}")
    print()
    print("| # | 问题 | 步 | 工具 | 结论 | ctx | 起始消息 |")
    print("|---|---|---|---|---|---|---|")
    for k, turn in enumerate(tl.get("turns") or []):
        tools = " ".join(f"{n}×{c}" for n, c in
                         sorted((turn.get("tools") or {}).items(), key=lambda x: -x[1])[:3]) or "—"
        print(f"| {k} | {cell(turn.get('text'), 40)} | {turn.get('steps', 0)} | {tools} | "
              f"{cell(turn.get('answer'), 60) or '（无文字回复）'} | "
              f"{fmt_tokens(turn.get('context')) if turn.get('context') else '—'} | "
              f"`{turn.get('user_id')}` (#{turn.get('index')}) |")
    print()
    print("下钻：`turn <session> <#>` 看一轮 · `step <session> <消息序号>` 看一步 · `raw <session> <消息ID>` 看原文")


def fetch_index_range(sid, start, end):
    pages, offset = {}, (start // PAGE) * PAGE
    while offset <= end:
        page = api(f"/api/sessions/{sid}/messages", limit=PAGE, offset=offset)
        items = page.get("items") or []
        for i, m in enumerate(items):
            pages[offset + i] = m
        offset += PAGE
        if offset >= page.get("total", 0):
            break
    return {i: m for i, m in pages.items() if start <= i <= end}


def cmd_turn(args):
    sid = args.session
    tl = api(f"/api/sessions/{sid}/timeline")
    turns = tl.get("turns") or []
    if not (0 <= args.turn < len(turns)):
        die(f"turn 超出范围：0..{len(turns) - 1}", 2)
    t = turns[args.turn]
    print(f"## Turn {args.turn} · {t.get('text')}")
    print(f"用户消息 `{t.get('user_id')}` (#{t.get('index')}) · {t.get('steps', 0)} 步 · "
          f"ctx {fmt_tokens(t.get('context'))} · {fmt_time(t.get('time_created'))}")
    if t.get("files"):
        print(f"改过：{', '.join(t['files'])}")
    if t.get("shell"):
        print(f"命令：{' | '.join(t['shell'])}")
    print()
    msgs = fetch_index_range(sid, t.get("index", 0), t.get("end_index", 0))
    for i in sorted(msgs):
        m = msgs[i]
        role = m.get("role") or (m.get("data") or {}).get("role") or "?"
        print(f"### #{i} {role}")
        if role == "user":
            print(msg_text(m))
        else:
            text = msg_text(m)
            if text:
                print(cut(text, 800))
            for line in render_tools(m, trunc=120):
                print(line)
            if not text and not render_tools(m):
                print("（无文字/工具）")
        print()


def cmd_step(args):
    sid = args.session
    tl = api(f"/api/sessions/{sid}/timeline")
    step = next((s for s in (tl.get("steps") or []) if s.get("index") == args.index), None)
    if not step:
        die(f"没有 index={args.index} 的步骤；用 summary 看有效序号", 2)
    r = api(f"/api/sessions/{sid}/request/{step['id']}")
    a = r.get("actual") or {}
    print(f"## Step #{args.index} · turn {step.get('turn')}")
    print(f"actual: in {a.get('input', 0):,} · cache {a.get('cache_read', 0) + a.get('cache_write', 0):,} · "
          f"out {a.get('output', 0):,} · finish `{a.get('finish') or '—'}`"
          + (" · **cache miss**" if r.get("cache_miss") else ""))
    print()

    h = r.get("history") or {}
    print(f"### 发出去的请求（推定重建）\n历史 {h.get('count', 0)} 条 · {fmt_bytes(h.get('bytes'))}")
    print()
    print("| # | role | summary | bytes |")
    print("|---|---|---|---|")
    for it in (h.get("items") or []):
        print(f"| {it.get('index')} | {it.get('role')} | {cell(it.get('summary'), 60)} | {fmt_bytes(it.get('bytes'))} |")

    log = r.get("llm_log")
    if log:
        seg = api(f"/api/llm-logs/{log['index']}", session=sid)
        parts = seg.get("segments") or []
        print()
        print(f"### 系统提示 {fmt_bytes(log.get('bytes'))} · {len(parts)} 段"
              + ("（--system 展开全文）" if not args.system else ""))
        if args.system:
            for p in parts:
                print(f"\n#### {p.get('label')} · {fmt_bytes(p.get('bytes'))}")
                print(p.get("text") or "")
        else:
            print("| 段 | bytes |")
            print("|---|---|")
            for p in parts:
                print(f"| {p.get('label')} | {fmt_bytes(p.get('bytes'))} |")

    print()
    print("### 模型返回")
    for p in r.get("response") or []:
        ty = p.get("type")
        if ty == "reasoning":
            print(f"- thinking ({len((p.get('text') or '').encode())}B)：{cut(p.get('text'), 300)}")
        elif ty == "tool":
            st = p.get("state") or {}
            out = tool_output_text(st)
            print(f"- tool `{tool_name(p)}`: {cut(tool_input_text(st), 100)} → {fmt_bytes(len(out.encode()))}")
            if out and args.full:
                print(f"  ```\n  {out}\n  ```")
            elif out:
                print(f"  ```\n  {cut(out, 200)}\n  ```")
        elif ty == "text":
            text = p.get("text") or ""
            print(text if (args.full or len(text) <= 1200) else cut(text, 1200))
        elif ty == "patch":
            print(f"- patch: {', '.join(p.get('files') or [])}")
    print()
    print(f"原文：`raw {sid} {step['id']} [--full]`")


def cmd_raw(args):
    sid, mid = args.session, args.message
    con = db()
    v2 = session_is_v2(con, sid)
    if v2:
        row = con.execute("SELECT type, data FROM session_message WHERE id=? AND session_id=?",
                          (mid, sid)).fetchone()
        if not row:
            die("消息不存在或不属于该会话", 2)
        role, data = row["type"], json.loads(row["data"] or "{}")
        idx = con.execute(
            "SELECT COUNT(*) FROM session_message WHERE session_id=? AND type IN ('user','assistant','compaction') "
            "AND seq < (SELECT seq FROM session_message WHERE id=?)", (sid, mid)).fetchone()[0]
        parts = data.get("content") or []
        if role == "user" and data.get("text"):
            parts = [{"type": "text", "text": data["text"]}]
    else:
        row = con.execute("SELECT data FROM message WHERE id=? AND session_id=?", (mid, sid)).fetchone()
        if not row:
            die("消息不存在或不属于该会话", 2)
        data = json.loads(row["data"] or "{}")
        role = data.get("role") or "?"
        idx = con.execute(
            "SELECT COUNT(*) FROM message WHERE session_id=? AND "
            "(time_created < (SELECT time_created FROM message WHERE id=?) OR "
            " (time_created = (SELECT time_created FROM message WHERE id=?) AND id < ?))",
            (sid, mid, mid, mid)).fetchone()[0]
        parts = [json.loads(r["data"]) for r in con.execute(
            "SELECT data FROM part WHERE message_id=? ORDER BY id", (mid,))]

    print(f"## {role} · #{idx}")
    print(f"`{mid}` · session `{sid}`")
    print()
    for p in parts:
        ty = p.get("type")
        if ty in ("text", "reasoning"):
            text = p.get("text") or ""
            print(text if (args.full or len(text) <= 4000) else cut(text, 4000))
            print()
        elif ty == "tool":
            st = p.get("state") or {}
            out = tool_output_text(st)
            print(f"### tool `{tool_name(p)}`")
            print(f"input: {tool_input_text(st) or '—'}")
            print(f"output ({fmt_bytes(len(out.encode()))}):")
            print(out if args.full else cut(out, 2000))
            print()
        elif ty == "patch":
            print(f"### patch {', '.join(p.get('files') or [])}")


def main():
    ap = argparse.ArgumentParser(prog="session.py", description="读取本机 opencode 会话")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list", help="按标题/日期找会话")
    p.add_argument("query", nargs="?", default="")
    p.add_argument("--date", help="YYYY-MM-DD")
    p.add_argument("--limit", type=int, default=10)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("summary", help="整场会话摘要（默认）")
    p.add_argument("session")
    p.set_defaults(func=cmd_summary)

    p = sub.add_parser("turn", help="某一轮的对话")
    p.add_argument("session")
    p.add_argument("turn", type=int)
    p.set_defaults(func=cmd_turn)

    p = sub.add_parser("step", help="某一步的请求快照 + 返回")
    p.add_argument("session")
    p.add_argument("index", type=int)
    p.add_argument("--system", action="store_true", help="展开系统提示全文")
    p.add_argument("--full", action="store_true", help="工具输出不截断")
    p.set_defaults(func=cmd_step)

    p = sub.add_parser("raw", help="单条消息原文")
    p.add_argument("session")
    p.add_argument("message")
    p.add_argument("--full", action="store_true")
    p.set_defaults(func=cmd_raw)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
