---
name: rb-trace-analysis
description: rb_trace 链路追踪数据分析：重建 span 树与时间线，定位慢链、空档、未埋点等待与阻塞点，输出带数字证据的问题清单与验证方法；可对照 rbEdgeServer/rbruleserver 源码校验语义。触发：分析 trace / 慢链 / 链路追踪 / trace JSON / 解释链路 / slowest 接口 / ruledata.consume / rulechain.execute
---

# rb-trace-analysis：rb_trace 链路分析

> 输入：rb_trace 链路数据（`/query/log/trace/slowest` 或 `/query/log/trace` 返回的 trace JSON）。
> 输出：带数字证据的问题清单。规则源于源码经验总结，可能过时——**代码是事实源，本 skill 是经验规则**，发现冲突以代码为准并回报修正建议（见「代码校验模式」）。

## 触发方式

**显式触发**：
- 用户贴出 trace JSON / 提到慢链、链路追踪、分析 trace、解释链路

**被动触发**：
- 出现 rb_trace 字段名：traceId / spanId / parentSpanId / costNs / totalCost
- 出现特征 span 名：rulechain.execute / rulechain.node / ruledata.consume / rulego.send ruleserver / emqx.exhook*

## 数据格式与字段语义

- trace 级：traceId / totalCost（毫秒，= max(end)−min(start) 的墙钟包络）/ startTimeMs / endTimeMs / spans[]（按 startTimeUnixNano 升序）。
- span 级：spanId / parentSpanId（空串=根）/ name / status（COMPLETED|FAILED|TIMEOUT）/ startTimeUnixNano / endTimeUnixNano（字符串纳秒，**源进程本地时钟**，在 span Start()/End() 时打点）/ costNs（= end−start）/ resourceId（device.id）/ errorCode。
- 取数（可选）：`GET /query/log/trace/slowest?window_days=&limit=`、`GET /query/log/trace?traceId=`（忽略时间过滤）；配套证据 `GET /query/log/v2?traceId=`（logevent）。
- 换算：统一 ms，保留 1~2 位小数；跨服务时间比较存在 ±ms 级时钟偏差。

## 服务归属（数据无 service 字段，按 name 判断）

| name 模式 | 归属 | 说明 |
|---|---|---|
| emqx.exhook.v2.HookProvider/OnMessagePublish | rbEdgeServer | trace 根（EMQX exhook gRPC 回调，server span） |
| edge.message.publish | rbEdgeServer | 消息锚点存根，入队前即 End（2µs 正常） |
| rulego.send ruleserver | rbEdgeServer | 异步 worker job：向 rbruleserver 发送设备数据 |
| rulechain.DeviceService/SendDeviceData | 两条同名 | resourceId 空 = edge 的 gRPC client span；resourceId 非空 = rbruleserver 的 server span（client 的子节点） |
| rulechain.execute <chainId> | rbruleserver | 一条规则链执行；同一设备数据可并行多条链 |
| rulechain.node <nodeId> | rbruleserver | 链内节点执行，父子=执行路径 |
| mqtt.publish <topic>（如 v1/rbruleserver/data） | rbruleserver | 下行控制指令发布（producer），traceparent 注入点 |
| ruledata.consume | rbEdgeServer | 下行消费（MQTT 订阅端），经报文 traceparent 续链 |
| mqtt.publish return | rbEdgeServer | 下行回执发布（producer，span 名固定） |

## 固有语义（以下形态正常，不得报为问题）

1. 异步队列：父 span 先 End、子 span 后 Start（如 edge.message.publish → rulego.send ruleserver，gap 常为亚毫秒~几毫秒）。
2. 根 span 很短（如 0.2ms）：入队前即结束，整条链可远长于根。
3. rulechain.execute 可并行多条；rulechain.node 的父子由引擎上下文决定，可能晚于兄弟节点结束。
4. SendDeviceData 同名两条是 client→server 一对，不是重复数据。
5. 同一 trace 可出现两个设备身份（上报设备 → 控制目标设备），正常。
6. 大 span 无子 span、且实际动作集中在末尾（如 ruledata.consume 内发布在最后几毫秒）是"未埋点等待"的特征形态。

## 判定原则

- span.cost 只是"该 span Start 到 End 的钟表段"，≠ 业务处理耗时。
- 时间构成 = 真实工作 + 未埋点等待 + 故意等待（间隔 sleep）+ 排队/传递等待 + 阻塞（锁/IO/日志/网络）。
- 总耗时 totalCost 是包络（含所有等待）。判断"谁慢"回到：**是否存在一个主体从 min(start) 等到 max(end)**；没有主体在等 ≠ 用户感知耗时。
- 证据等级：① 数据可直接证明；② 数据支持的推测（标注"需验证"）；③ 未知（明说不知道，禁止硬编原因）。

## 分析步骤（必须执行）

1. 用 spanId/parentSpanId 重建树；父 id 不存在 → 标记"孤儿 span"。
2. 输出时间线表：相对起点(ms) | 时长(ms) | 名称 | resourceId | 备注（根/叶子/有无子 span）。
3. 逐 span 估算 self-time ≈ cost − 直接子 span 时间并集；self 大且无子 span → 标记"未埋点等待/阻塞嫌疑"。
4. 列出所有 ≥50ms 的 gap（父 end → 子 start、相邻动作之间），每个都要给出解释或标注"无法从 trace 解释"。
5. 异常扫描：单 span 占 totalCost >50%；秒级 span；status≠COMPLETED 或 errorCode 非空；无根/无法确认链尾；时间倒挂（负 gap）；同名歧义对。
6. 对每个嫌疑给出：现象（数字）→ 影响（哪个环节、谁在等）→ 原因候选（区分"可证/需验证"）→ 验证方法（边端 app.log、rb_log_event、链配置 ExecuteInteval、goroutine 快照等）。
7. 证据不足时明确列出"还需要什么"，禁止硬编原因。

## 已知阻塞模式（候选方向，需验证，不得直接定案）

- rbEdgeServer：rblog 日志包锁缺陷 + 设备写锁级联（writeVisualdevice 持锁调 log）→ 设备缓存扫描 RLock 卡住 → rulego.send / ruledata.consume 出现秒级"无子 span"等待。验证：边端 app.log 时间窗、goroutine 快照。
- 设备间隔 sleep（规则链 ExecuteInteval>0）：ruledata.consume 尾部 gap；多设备时会出现多个 mqtt.publish return。验证：链配置。
- 队列语义（JobCacheQueue 缓冲 50 + worker 50）：生产者背压（队列满）体现在根 span 时长；消费者饱和（worker 全忙）体现在 job.start 延迟。

## 代码校验模式（Mode B）

> 当运行环境能访问工作区（源码就在工作区内）时启用；不能访问（外部 AI/纯粘贴）时，在输出首行标注「纯数据分析模式（未经源码校验）」。

**代码路径解析**（遵循全局规则，不输出冗余路径表述）：
- 工作区根按 `~/platform/` → WSL `/mnt/d/platform/` 顺序探测，取首个存在的；
- 仓库路径 = `<工作区根>/<仓库名>/`；本 skill 涉及仓库：rbEdgeServer / rbruleserver / rblogserver / log / visualdevice。

**去读代码的触发**：
1. 需要归因（大 cost 无子 span / 无法解释的 gap）；
2. 数据与本文档"固有语义/判定原则"矛盾；
3. 出现本文档未收录的 span 名或形态；
4. 用户要求深挖根因。

**规则**：
- 先数据、后代码：先给"数据能证明什么"，再读代码验证"为什么"；
- 只读、定向：按下方锚点表读，不通读全仓；引用给「文件:符号」；
- **冲突处理**：代码与本文档冲突 → 以代码为准继续分析，并在输出末尾追加「Skill 修正建议」：冲突点 / 代码证据 / 建议改法；
- 不修改任何代码与 skill 文件。

### 代码锚点表

| 主题 | 位置（符号为准，行号可能漂移） |
|---|---|
| edge 根 span / 消息锚点 / 入队 | rbEdgeServer `exhook/exhook.go`（OnMessagePublish） |
| 上行 job | rbEdgeServer `worker/rulego_job.go`（RuleGoJob.Do） |
| 队列与 worker 池 | rbEdgeServer `worker/dispatcher.go`、`worker/worker.go` |
| 下行消费入口 | rbEdgeServer `localEmqxClient/localClient.go`（ruleDataMessageHandler） |
| 下行处理（缓存查询/间隔 sleep/发布） | rbEdgeServer `localEmqxClient/rule_job.go`（Do/deviceActuator） |
| consume/发布 span 与 traceparent 提取 | rbEdgeServer `localEmqxClient/tracing.go` |
| 设备缓存扫描 | rbEdgeServer `visualdevice/visualdevice.go`（GetVisualDevicesDto） |
| gRPC 埋点过滤器 | rbEdgeServer `tracing/tracer.go`（GrpcSpanFilter） |
| ruleserver server span / 多链派发 | rbruleserver `internal/service/device_data.go` |
| 链 span / 节点 span | rbruleserver `internal/tracing/entry.go`、`internal/tracing/aspect.go` |
| 下行发布与 traceparent 注入 | rbruleserver `internal/component/actuator_tracing.go`、`actuator.go` |
| 导出层静默过滤 | rbruleserver `internal/tracing/drop.go`（silentFilterExporter） |
| totalCost 口径 / 慢链组装 | rblogserver `internal/biz/trace.go`（ListSlowestTraces/assembleSlowestTraces） |
| 慢链 SQL | rblogserver `internal/data/trace.go`（SlowestTraceSummaries/ListByTraceIDs） |
| rblog 锁缺陷背景 | log 仓库 `http.go`（Log/startA） |

## 输出格式

1. 结论块（≤5 行）：最慢的 1~2 个环节 + 性质（工作/等待/阻塞）+ 建议动作；首行标注分析模式（是否经源码校验）。
2. 时间线表。
3. 问题清单（按严重度，每条带 spanId 与数字证据）。
4. "易误读但正常"清单（无则写"无"）。
5. 「Skill 修正建议」（仅 Mode B 发现冲突时出现）。
6. 末行可选 JSON 摘要（便于批量汇总）：`{"traceId":"…","totalMs":0,"suspect":"name@spanId","kind":"gap|blocked-work|error|normal","need":"…"}`

## 批量模式

多条 trace：逐条分析后给共性汇总（高频嫌疑名、共性 gap 形态、需要批量验证的假设）。
