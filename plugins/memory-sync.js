// memory-sync — 记忆协同自动触发插件（全局）
//
// 机制定位（全局 memory-mechanism.md）：
//   主机制 = 自动持续提醒（每轮 system + 每次认知性工具执行后），
//   兜底   = 特定动作后检查（git commit 后）。
//
// 实现约束：插件只能注入提醒文本（模型可见），文档内容由 AI 生成——
// "自动更新" = 让"即时更新"义务每轮/每次行动都在场，不靠自觉。

import { existsSync } from "node:fs";
import { join } from "node:path";

// 每轮注入的常驻规则（experimental.chat.system.transform，每次 LLM 调用前触发）
const SYSTEM_RULE = `[记忆协同] 本项目使用 .opencode/ 跨会话记忆（MEMORY.md 索引 + memory/ + tracking/）。
规则：每次 edit/write/bash 工具执行后，若形成新认知或任务有进展（根因/决策/踩坑/状态变化），
立即更新对应 tracking/ 或 memory/ 文档并同步 MEMORY.md 索引（详见全局 memory-mechanism.md），
不等会话结束、不依赖特定动作。无新认知则不动作。`;

// 认知性工具：执行后强制检查记忆同步（read/grep 等只读工具不触发，避免噪声）
const COGNITIVE_TOOLS = new Set(["edit", "write", "apply_patch", "patch", "multi_edit"]);

// bash 命令中出现 git commit 视为"动作后兜底"触发点
const COMMIT_RE = /(^|\s)git\s+(commit|push|merge|rebase|cherry-pick)/;

const REMINDER = `\n\n【记忆同步提醒】本次操作可能已形成新认知/任务进展（根因、决策、踩坑、状态变化）。按全局 memory-mechanism.md：立即更新 .opencode/ 下 tracking/ 或 memory/ 文档并同步 MEMORY.md 索引，不等会话结束。无新认知可忽略。`;

export const MemorySync = async ({ directory }) => {
  // 项目级 .opencode/ 存在才启用（global 规则机制，其余项目零影响）。
  // 状态放闭包内：每个项目实例独立，避免多项目共享进程时互相干扰。
  const enabled = existsSync(join(directory, ".opencode"));
  // 同 session 短窗口去重：同一轮 LLM 循环内多个认知性工具连续执行时只提醒一次
  const lastRemindAt = new Map(); // sessionID -> 上次提醒时间戳(ms)
  const REMIND_WINDOW_MS = 15_000;

  return {
    // ── 主机制 1：每轮常驻规则（自动、持续，不依赖特定动作）──
    "experimental.chat.system.transform": async (input, output) => {
      if (!enabled) return;
      if (!output.system.some((s) => s.includes("记忆协同"))) {
        output.system.push(SYSTEM_RULE);
      }
    },

    // ── 主机制 2：认知性工具执行后即时提醒（自动、行动后立刻）──
    // ── 兜底：git commit 后强制检查（防漏网）──
    "tool.execute.after": async (input, output) => {
      if (!enabled) return;
      const { tool, sessionID, args } = input;
      if (tool === "bash") {
        const cmd = typeof args?.command === "string" ? args.command : "";
        if (!COMMIT_RE.test(cmd)) return; // 非 commit 类 bash 不提醒
      } else if (!COGNITIVE_TOOLS.has(tool)) {
        return;
      }
      const now = Date.now();
      const lastAt = lastRemindAt.get(sessionID) ?? 0;
      if (now - lastAt < REMIND_WINDOW_MS) return; // 短窗口去重
      lastRemindAt.set(sessionID, now);
      output.output = (output.output ?? "") + REMINDER;
    },
  };
};
