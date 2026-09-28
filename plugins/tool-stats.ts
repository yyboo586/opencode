// tool-stats — 工具调用统计插件（全局，双兼容 v1/v2）
//
// 用途：把每次工具调用记成一行 JSONL，供 plugins/tool-stats/report.sh 出月报/日报。
// 数据：~/.local/share/opencode/tool-stats/YYYY-MM.jsonl（按月分文件）
// 文档：plugins/tool-stats/README.md
//
// 兼容形态（同 memory-sync）：
//   - v2 读 default.id + setup(ctx)，用 ctx.tool.hook("execute.before/after")；
//   - v1（>=1.18.29）读 default.server(input)，返回 tool.execute.before/after。
// 两套实现共享：时长配对、命令首词提取、JSONL 落盘。
//
// 隐私边界：bash/shell 只记命令首词（w 字段，如 git/docker），不记命令全文。

import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DATA_DIR = join(homedir(), ".local", "share", "opencode", "tool-stats");

interface ToolRecord {
  ts: number;
  tool: string;
  status?: string;
  ms?: number;
  sid?: string;
  agent?: string;
  w?: string;
}

// 追加一行；统计失败不影响工具主流程
function appendRecord(rec: ToolRecord): void {
  try {
    const d = new Date();
    const file = join(DATA_DIR, `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}.jsonl`);
    mkdirSync(DATA_DIR, { recursive: true });
    appendFileSync(file, JSON.stringify(rec) + "\n");
  } catch {
    // 静默：统计属旁路能力
  }
}

// bash/shell 命令首词（去路径前缀），如 "git"、"docker"；只取词，不落全文
function firstWord(tool: string, input: unknown): string | undefined {
  if (tool !== "bash" && tool !== "shell") return undefined;
  const cmd =
    input && typeof input === "object" && typeof (input as { command?: unknown }).command === "string"
      ? ((input as { command: string }).command)
      : "";
  const m = cmd.trim().match(/^(?:\w+=\S+\s+)*([^\s|;&]+)/);
  return m ? m[1].replace(/^.*\//, "") : undefined;
}

// 时长配对：before 记起始，after 落一行完整记录
function makeTracker() {
  const startAt = new Map<string, number>(); // callID -> 起始毫秒
  return {
    before(callID: unknown): void {
      if (typeof callID === "string" && callID) startAt.set(callID, Date.now());
    },
    after(
      callID: unknown,
      tool: string,
      sessionID: unknown,
      agent: unknown,
      status: unknown,
      input: unknown,
    ): void {
      const key = typeof callID === "string" ? callID : undefined;
      const t0 = key ? startAt.get(key) : undefined;
      if (key) startAt.delete(key);
      const rec: ToolRecord = { ts: Date.now(), tool };
      if (t0 != null) rec.ms = rec.ts - t0;
      if (typeof status === "string" && status) rec.status = status;
      if (typeof sessionID === "string" && sessionID) rec.sid = sessionID;
      if (typeof agent === "string" && agent) rec.agent = agent;
      const w = firstWord(tool, input);
      if (w) rec.w = w;
      appendRecord(rec);
    },
  };
}

// v2 事件与上下文最小面（运行时不校验，仅类型用；不引入包依赖）
interface V2ToolEvent {
  id?: unknown;
  tool?: string;
  sessionID?: unknown;
  agent?: unknown;
  status?: unknown;
  input?: unknown;
}

interface V2Context {
  tool: {
    hook(
      name: "execute.before" | "execute.after",
      fn: (event: V2ToolEvent) => void,
    ): Promise<unknown>;
  };
}

// v1 hook 输入最小面
interface V1BeforeInput {
  callID?: unknown;
}
interface V1AfterInput extends V1BeforeInput {
  tool: string;
  sessionID?: unknown;
  agent?: unknown;
  args?: unknown;
}

export default {
  id: "tool-stats",

  // ── v2：hook 注册式 ──
  async setup(ctx: V2Context) {
    const tracker = makeTracker();
    await ctx.tool.hook("execute.before", (event) => {
      tracker.before(event.id);
    });
    await ctx.tool.hook("execute.after", (event) => {
      tracker.after(event.id, event.tool ?? "unknown", event.sessionID, event.agent, event.status, event.input);
    });
  },

  // ── v1：返回 hook 对象式 ──
  async server() {
    const tracker = makeTracker();
    return {
      "tool.execute.before": async (input: V1BeforeInput) => {
        tracker.before(input?.callID);
      },
      "tool.execute.after": async (input: V1AfterInput) => {
        tracker.after(input?.callID, input.tool, input.sessionID, input.agent, undefined, input.args);
      },
    };
  },
};
