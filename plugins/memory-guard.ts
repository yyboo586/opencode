// memory-guard — hard write gate for .opencode/MEMORY.md (v1 + v2).
//
// Deterministic enforcement, not a prompt rule:
//   1. before any tool call, snapshot MEMORY.md (content + hash);
//   2. after the call, if the hash changed, run memory-lint;
//   3. if the write introduced new index errors, restore the snapshot and
//      replace the tool result with the violation list.
//
// Existing debt is recorded in .opencode/memory-lint-baseline.json the first
// time a repository is touched, so "enable first, clean later" works: old
// violations do not block, new ones do. Cleanup can prune the baseline with
// `memory-lint --repo <repo> --write-baseline`.
//
// This catches edit/write, shell redirection, and execute-based indirect writes
// because it compares the file hash around every tool call.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";

const LINT_BIN =
  process.env.MEMORY_LINT_BIN ?? join(homedir(), ".config", "opencode", "bin", "memory-lint");
const BASELINE = "memory-lint-baseline.json";
const LOG = join(homedir(), ".local", "share", "opencode", "log", "memory-guard.log");

type Snapshot = { path: string; content: string; hash: string; repo: string };

const snapshots = new Map<string, Snapshot>();
const baselineReady = new Set<string>();

function hash(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

/** Walk up from start until .opencode/MEMORY.md is found. */
function findMemory(start: string): string | null {
  let dir = start;
  for (;;) {
    const candidate = join(dir, ".opencode", "MEMORY.md");
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

function repoOf(memoryPath: string): string {
  return dirname(dirname(memoryPath));
}

function log(line: string): void {
  try {
    mkdirSync(dirname(LOG), { recursive: true });
    appendFileSync(LOG, `${new Date().toISOString()} ${line}\n`);
  } catch {
    // Logging must never break the guard.
  }
}

type LintResult = {
  status: number;
  found?: boolean;
  new_errors?: number;
  new_issues?: Array<{ severity: string; code: string; path: string; line?: number; message: string }>;
};

function runLint(repo: string, writeBaseline = false): LintResult {
  const args = ["--repo", repo, "--json"];
  if (writeBaseline) args.push("--write-baseline");
  try {
    const out = execFileSync(LINT_BIN, args, { encoding: "utf8", timeout: 15_000 });
    return { status: 0, ...JSON.parse(out || "{}") };
  } catch (err: any) {
    const out = typeof err?.stdout === "string" ? err.stdout : err?.stdout?.toString?.("utf8");
    if (out) {
      try {
        return { status: err?.status ?? 1, ...JSON.parse(out) };
      } catch {
        // fall through
      }
    }
    return { status: err?.status ?? -1 };
  }
}

function ensureBaseline(repo: string): void {
  if (baselineReady.has(repo)) return;
  const path = join(repo, ".opencode", BASELINE);
  if (!existsSync(path)) {
    const res = runLint(repo, true);
    log(`baseline ${repo}: status=${res.status}`);
  }
  baselineReady.add(repo);
}

function startDirFor(input: any, fallback: string): string {
  const raw = input?.path ?? input?.filePath;
  if (typeof raw === "string" && raw) {
    const p = isAbsolute(raw) ? raw : join(fallback, raw);
    return dirname(p);
  }
  return fallback;
}

function snapshot(id: string, start: string): void {
  const memoryPath = findMemory(start);
  if (!memoryPath) return;
  const repo = repoOf(memoryPath);
  ensureBaseline(repo);
  const content = readFileSync(memoryPath, "utf8");
  snapshots.set(id, { path: memoryPath, content, hash: hash(content), repo });
}

function violationText(res: LintResult): string {
  const list = (res.new_issues ?? [])
    .filter((i) => i.severity === "error")
    .slice(0, 12)
    .map((i) => `- ${i.code} ${i.path}${i.line ? `:${i.line}` : ""} — ${i.message}`)
    .join("\n");
  return (
    `[memory-guard] MEMORY.md 写入被拒绝：新增 ${res.new_errors ?? 0} 个索引错误，已回滚。\n` +
    list +
    `\n修复后再写；历史欠账见 .opencode/${BASELINE}。` +
    `\n规则：条目一行≤300字符、无子 bullet、链接必须存在、Tracking 只放进行中、闭环条目移到 .opencode/archive/MEMORY-ARCHIVE.md。`
  );
}

function validate(id: string): string | null {
  const snap = snapshots.get(id);
  if (!snap) return null;
  snapshots.delete(id);
  if (!existsSync(snap.path)) return null;
  const now = readFileSync(snap.path, "utf8");
  if (hash(now) === snap.hash) return null;
  const res = runLint(snap.repo);
  if (res.status === 0) return null;
  if (res.status === 1 && (res.new_errors ?? 0) > 0) {
    writeFileSync(snap.path, snap.content);
    log(`blocked ${snap.path}: new_errors=${res.new_errors}`);
    return violationText(res);
  }
  if (res.status !== 0) {
    writeFileSync(snap.path, snap.content);
    log(`blocked ${snap.path}: linter status=${res.status}`);
    return `[memory-guard] memory-lint 失败（status=${res.status}），已回滚 MEMORY.md。先修 linter 再写。`;
  }
  return null;
}

export default {
  id: "memory-guard",

  // ── v2: hook registration ──
  async setup(ctx: any) {
    const base = ctx.location?.directory ?? process.cwd();
    await ctx.tool.hook("execute.before", (event: any) => {
      const id = event.id ?? `${event.sessionID}:${event.tool}`;
      snapshot(id, startDirFor(event.input, base));
    });
    await ctx.tool.hook("execute.after", (event: any) => {
      const id = event.id ?? `${event.sessionID}:${event.tool}`;
      const message = validate(id);
      if (!message) return;
      const content = event.result?.content;
      const next =
        typeof content === "string"
          ? content + "\n\n" + message
          : [...(content ?? []), { type: "text", text: message }];
      event.result = { ...event.result, content: next };
    });
  },

  // ── v1: hook object ──
  async server({ directory }: { directory: string }) {
    return {
      "tool.execute.before": async (input: any) => {
        snapshot(input.callID, startDirFor(input.args, directory));
      },
      "tool.execute.after": async (input: any, output: any) => {
        const message = validate(input.callID);
        if (!message) return;
        output.output = (output.output ?? "") + "\n\n" + message;
      },
    };
  },
};
