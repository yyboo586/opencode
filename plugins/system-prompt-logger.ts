// system-prompt-logger — 记录每轮 LLM 请求的完整 system prompt（本地 fork，双兼容 v1/v2）
//
// 上游 opencode-system-prompt-logger@1.0.0 只有 v1 API（client.app.log），未适配 v2；
// v2 无 app.log 等价 API，故 fork 本地并双实现：
//   - v1（server）：client.app.log 原样（session-viewer 现有解析链路不变）；
//   - v2（setup）：注册 context/compaction/generate/title 四个请求钩子，
//     写 JSONL 到 ~/.local/share/opencode/log/system-prompt/YYYY-MM-DD.jsonl。
//
// JSONL 行格式（字段名对齐 session-viewer 的 logfile.Record，便于其加解析分支）：
//   {"time":"...","session_id":"ses_...","provider_id":"...","model_id":"...","kind":"...","message":"<完整 system prompt>"}

import { appendFile, mkdir } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

const LOG_DIR = join(homedir(), ".local", "share", "opencode", "log", "system-prompt")

/** v1 插件输入中的 client 最小面（仅用于类型提示，运行时不校验） */
interface V1Client {
	app: {
		log(input: {
			body: {
				service: string
				level: string
				message: string
				extra?: Record<string, unknown>
			}
		}): Promise<unknown>
	}
}

/** v2 请求钩子事件最小面（四个 kind 共有字段） */
interface V2RequestEvent {
	sessionID: string
	model: { providerID: string; id: string }
	system: ReadonlyArray<{ type: string; text: string }>
}

/** v2 插件上下文最小面（不引入 @opencode/plugin 依赖） */
interface V2LoggerContext {
	session: {
		hook(
			name: "context" | "compaction" | "generate" | "title",
			callback: (event: V2RequestEvent) => void | Promise<void>,
		): Promise<unknown>
	}
}

// v1 与 v2 的记录文本保持同一拼接方式（session-viewer 按 "Instructions from: ..." 分段）
function joinSystem(system: ReadonlyArray<string>): string {
	return system.map((prompt) => `\n${prompt}`).join("\n-----") || ""
}

function joinSystemParts(system: ReadonlyArray<{ text: string }>): string {
	return joinSystem(system.map((part) => part.text))
}

// v2 落盘：按日一个 JSONL 文件；失败只告警，不影响请求
async function appendRecord(
	kind: string,
	event: V2RequestEvent,
): Promise<void> {
	try {
		const time = new Date()
		const day = time.toISOString().slice(0, 10)
		const record = {
			time: time.toISOString(),
			session_id: event.sessionID ?? "",
			provider_id: event.model?.providerID ?? "",
			model_id: event.model?.id ?? "",
			kind,
			message: joinSystemParts(event.system ?? []),
		}
		await mkdir(LOG_DIR, { recursive: true })
		await appendFile(join(LOG_DIR, `${day}.jsonl`), `${JSON.stringify(record)}\n`, "utf8")
	} catch (error) {
		console.warn(`[system-prompt-logger] append failed: ${String(error)}`)
	}
}

export default {
	id: "system-prompt-logger",

	// ── v2：四个请求 kind 各注册一次（与 v1 transform 覆盖所有 LLM 请求对齐）──
	async setup(ctx: V2LoggerContext) {
		await ctx.session.hook("context", (event) => appendRecord("context", event))
		await ctx.session.hook("compaction", (event) => appendRecord("compaction", event))
		await ctx.session.hook("generate", (event) => appendRecord("generate", event))
		await ctx.session.hook("title", (event) => appendRecord("title", event))
	},

	// ── v1：上游 1.0.0 行为原样 ──
	async server({ client }: { client: V1Client }) {
		return {
			"experimental.chat.system.transform": async (
				input: { sessionID?: string; model: { providerID: string; id: string } },
				output: { system: string[] },
			) => {
				const message = joinSystem(output.system)
				await client.app.log({
					body: {
						service: "system-prompt-logger",
						level: "info",
						message,
						extra: {
							sessionID: input.sessionID || "",
							providerID: input.model.providerID,
							modelID: input.model.id,
						},
					},
				})
			},
		}
	},
}
