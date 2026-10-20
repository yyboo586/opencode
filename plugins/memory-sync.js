// memory-sync — 记忆协同自动触发插件（全局，双兼容 v1/v2）
//
// 机制定位（全局 memory-mechanism.md）：
//   主机制 = 自动持续提醒（每轮 system + 每次认知性工具执行后），
//   兜底   = 特定动作后检查（git commit 后）。
//
// 实现约束：插件只能注入提醒文本（模型可见），文档内容由 AI 生成——
// "自动更新" = 让"即时更新"义务每轮/每次行动都在场，不靠自觉。
//
// 兼容形态（官方 Support V1）：
//   - v2 读 default.id + setup(ctx)；
//   - v1（>=1.18.29）读 default.server(input, options)。
// 两套 hook 各自实现，共享 trigger 判定与去重逻辑。

import { existsSync } from "node:fs";
import { join } from "node:path";

// 每轮注入的常驻规则（v1: experimental.chat.system.transform；v2: ctx.session.hook("context")）
const SYSTEM_RULE = `[记忆协同] 本项目使用 .opencode/ 跨会话记忆（MEMORY.md 索引 + archive/ + memory/ + tracking/）。
规则：每次 edit/write/bash 工具执行后，若形成新认知或任务有进展（根因/决策/踩坑/状态变化），
立即更新对应 tracking/ 或 memory/ 文档并同步 MEMORY.md 索引（详见全局 memory-mechanism.md），
不等会话结束、不依赖特定动作。无新认知则不动作。`;

// 认知性工具：执行后强制检查记忆同步（read/grep 等只读工具不触发，避免噪声）
const COGNITIVE_TOOLS = new Set(["edit", "write", "apply_patch", "patch", "multi_edit"]);

// bash 命令中出现 git commit 视为"动作后兜底"触发点
const COMMIT_RE = /(^|\s)git\s+(commit|push|merge|rebase|cherry-pick)/;

const REMINDER = `\n\n【记忆同步提醒】本次操作可能已形成新认知/任务进展（根因、决策、踩坑、状态变化）。按全局 memory-mechanism.md：立即更新 .opencode/ 下 tracking/ 或 memory/ 文档并同步 MEMORY.md 索引，不等会话结束。无新认知可忽略。`;

const REMIND_WINDOW_MS = 15_000;

// 认知性触发判定：认知性工具直接命中；bash 仅 commit 类命令命中
function isReminderTrigger(tool, args) {
  if (tool === "bash" || tool === "shell" || tool === "execute") {
    const cmd = typeof args?.command === "string" ? args.command : typeof args?.code === "string" ? args.code : "";
    return COMMIT_RE.test(cmd);
  }
  return COGNITIVE_TOOLS.has(tool);
}

// 同 session 短窗口去重：同一轮 LLM 循环内多个认知性工具连续执行时只提醒一次
function createRemindGate() {
  const lastRemindAt = new Map(); // sessionID -> 上次提醒时间戳(ms)
  return (sessionID) => {
    const now = Date.now();
    const lastAt = lastRemindAt.get(sessionID) ?? 0;
    if (now - lastAt < REMIND_WINDOW_MS) return false;
    lastRemindAt.set(sessionID, now);
    return true;
  };
}

// 项目级 .opencode/ 存在才启用（global 规则机制，其余项目零影响）
function isEnabled(directory) {
  return existsSync(join(directory, ".opencode"));
}

export default {
  id: "memory-sync",

  // ── v2：hook 注册式 ──
  async setup(ctx) {
    const enabled = isEnabled(ctx.location.directory);
    const remindGate = createRemindGate();

    // 主机制 1：每轮常驻规则（每次 agent 模型请求前）
    await ctx.session.hook("context", (event) => {
      if (!enabled) return;
      if (!event.system.some((part) => part?.text?.includes("记忆协同"))) {
        event.system.push({ type: "text", text: SYSTEM_RULE });
      }
    });

    // 主机制 2：认知性工具执行后即时提醒；兜底：git commit 后强制检查
    await ctx.tool.hook("execute.after", (event) => {
      if (!enabled) return;
      if (!isReminderTrigger(event.tool, event.input)) return;
      if (!remindGate(event.sessionID)) return;
      if (event.status !== "completed") return; // 失败结果无 content 语义，跳过
      const content = event.result?.content;
      const next =
        typeof content === "string"
          ? content + REMINDER
          : [...(content ?? []), { type: "text", text: REMINDER }];
      event.result = { ...event.result, content: next };
    });
  },

  // ── v1：返回 hook 对象式 ──
  async server({ directory }) {
    const enabled = isEnabled(directory);
    const remindGate = createRemindGate();

    return {
      "experimental.chat.system.transform": async (_input, output) => {
        if (!enabled) return;
        if (!output.system.some((s) => s.includes("记忆协同"))) {
          output.system.push(SYSTEM_RULE);
        }
      },
      "tool.execute.after": async (input, output) => {
        if (!enabled) return;
        if (!isReminderTrigger(input.tool, input.args)) return;
        if (!remindGate(input.sessionID)) return;
        output.output = (output.output ?? "") + REMINDER;
      },
    };
  },
};
