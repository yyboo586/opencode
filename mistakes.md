# 错题本（档案层）

> 记录 AI 错误**事件**。允许重复——重复次数是升格硬规则的信号。
> 本文件**不注入**上下文；注入层是 `positive-rules.md`。
> 行为规则见 `AGENTS.md` §9；条目状态词：已沉淀 / 已升格 / 已失效。

### 2026-08-13 openGauss gsql 无法直接执行

- 场景: test-env opengauss 容器内执行 SQL
- 错误做法: `docker exec -it opengauss gsql ...` → `command not found` 或 `libpq.so.*: cannot open`
- 正确做法: 绝对路径 + LD_LIBRARY_PATH：`docker exec -it opengauss bash -c "LD_LIBRARY_PATH=/usr/local/opengauss/lib /usr/local/opengauss/bin/gsql ..."`
- 状态: 已沉淀（→ positive-rules.md 环境与工具）

---

## 2026-05-28 ~ 08-13 全量扫描批次（688 会话 / 45 块分析）

> 数据源：opencode.db sqlite ro 直读，2026-05-28 → 08-13 全部会话。
> 信号：用户纠正 79 会话 + AI 认错 114 会话 + tool 错误 646 次。
> 以下按主题聚合代表性事件，完整清单见各块分析（/tmp/opencode/blocks/）。

### 一、工具操作类（最高频，占 tool 错误 80%+）

**edit oldString 不精确反复失败（141 + 45 identical + 21 multiple 次）**

- 场景: 文档/代码批量编辑（跨 5 个项目全部会话）
- 错误做法: 未 Read 文件就凭记忆/猜构造 oldString；identical（oldString==newString 仍提交）、multiple matches 不加上下文、失败后不重读文件继续猜
- 代表事件: 2026-05-28 ses_19299d662 注释改中文任务 4 连败（identical×1 + multiple×2 + not found×1）后仍总结"所有英文注释都已改为中文"；2026-06-09 ses_1544ecc4c 章节重组 edit 导致章节整段丢失；2026-07-23 ses_0727e8707 边 edit 边发现接口破坏（6 次失败）
- 正确做法: edit 前先 Read 目标文件取精确文本（含全角空格/缩进）；identical 说明已是目标状态应跳过；失败后重读文件再重试，而非反复猜测
- 状态: 已沉淀（→ positive-rules.md 环境与工具）

**todowrite/question 参数 SchemaError（73 + 27 次）**

- 场景: 任务跟踪 todos / 用户决策 questions 调用
- 错误做法: todos 传入 JSON 字符串而非数组（`{"todos": "[{\"content\":...}]"}`）→ `Expected array, got string`；同格式重试 8 次不修；question options 缺 label/description、`label=` 等号拼写
- 代表事件: 2026-07-28 ses_05929df35 连续 8+ 次同格式重试后放弃 todowrite；2026-07-31 ses_04e05bb89 question 14 次失败
- 正确做法: 参数传数组对象本身（todos/questions 为数组，不字符串化）；SchemaError 后先核对 schema 必填字段再重试
- 状态: 已沉淀（→ positive-rules.md 环境与工具）

**webfetch 凭记忆猜 URL（2 次共 16 连败）**

- 场景: 调研外部资料（MCP 方案、LLM 偏好收集）
- 错误做法: 猜 GitHub 仓库/路径（pinkpixel-dev/SuperMCP 等 5 个 404）、antthropic-cookbook 404、perplexity 403、bilibili 412——连续失败后无 fallback，靠个人知识库作答
- 代表事件: 2026-06-16 ses_1300bdecb 11 连败；2026-07-24 ses_06e6232fd 5 连败
- 正确做法: 不猜 URL，先搜索/官方文档入口；连续失败切换 fallback 工具链；无法访问来源时先声明再作答
- 状态: 已沉淀（→ positive-rules.md 环境与工具）

**容器内命令/端口环境错位（6+ 次）**

- 场景: 容器内执行命令、连接服务
- 错误做法: gsql/gs_guc 不带全路径（gs_guc 在 gsql 沉淀后**又踩一次**）；mongodump 在容器内连宿主机映射端口 32769（容器内监听 27017）→ refused；给用户 `su - omm -c "gsql"` 而非 docker exec
- 代表事件: 2026-08-04 ses_0356491c gs_guc command not found（gsql 同类已沉淀仍复发）；2026-08-07 ses_029996dd3 mongodump 端口
- 正确做法: 给命令前先确认执行环境（容器内/宿主机）、监听地址、既有写法（docker-compose healthcheck）；全路径 + LD_LIBRARY_PATH 通用化
- 状态: 已沉淀（→ positive-rules.md 环境与工具）

**手算时间戳/数据解读错误（5 次）**

- 场景: 时间戳过滤 SQL、goroutine 计数、/proc/diskstats 解析
- 错误做法: 手算 "2026-07-30 18:54:00 ≈ 1754268840000"（实际对应 2025 年）；grep 行数当 goroutine 数（320 vs 实际 160）；/proc/diskstats 字段序搞错（inflight 实为写扇区）
- 正确做法: 时间戳让数据库算（extract epoch）；goroutine 按栈块分割统计（awk RS="\n\n"）；/proc 字段先对照文档验证再统计
- 状态: 已沉淀（→ positive-rules.md 代码与测试）

### 二、断言纪律类（30+ 次被证伪，最高风险）

**方言/兼容性断言未实测（12+ 次）**

- 场景: openGauss/MySQL/Redis 行为断言
- 错误做法: 以确定语气断言"openGauss 分区表唯一约束必须含分区键"（行存实测不需要）、"DATETIME 是别名/TIMESTAMP 无时区"（实测相反）、"B 模式 ? 不可用"（实测可用）、"有 4 种兼容模式"（实测 5 种）、"Redis 行尾注释合法"（反驳用户后被 FATAL 证实）
- 代表事件: 2026-05-29 ses_18e840139 断言被实测推翻后用户才建立 verify skill 动机；2026-07-28 ses_05929df35 bson 大小写敏感错误规则写入 AGENTS.md（用户 3 轮纠正才翻案）
- 正确做法: 涉及方言/驱动/内核行为差异先实测（建表实验/SHOW/pg_type/最小复现），未验证显式标注；用户质疑时先验证而非反驳
- 状态: 已沉淀（→ positive-rules.md 流程纪律，§7 已有规则）

**性能/可行性断言未实测（8+ 次）**

- 场景: 资源配额、迁移耗时、benchmark 对比
- 错误做法: "TiDB 1G 内存绰绰有余"→ OOM Kill（实际 1.85G）；"迁移 2780 万行 ≈ 10 分钟"→ 实跑 6 分钟仅 37%；"RC3 吞吐 +55%"→ 重测同版本差异 +44% 推翻；"ns/op×6"→ 实测 ×15
- 正确做法: 性能断言基于实测（先跑一批计时/多轮同条件对比），单轮对比不构成结论
- 状态: 已沉淀（→ positive-rules.md 流程纪律）

**存在性/状态断言漏搜索（8+ 次）**

- 场景: "0 引用/不存在/已删除"类断言
- 错误做法: "14 个 GetXxxCollectionName 0 调用方"→ 实施发现 cmd/migrator 14 个 ETL 文件在用（漏搜 cmd/）；"rbiotserver 无任何 Mongo 痕迹"→ 正在做 Mongo 迁移；"仓库没有 tracking 目录"→ 目录存在；"文件已 staged"→ 未即时 git status 核对
- 正确做法: 存在性断言附搜索命令+范围（含 cmd/、test/、跨仓库）；git 状态断言前先 git status
- 状态: 已沉淀（→ positive-rules.md 流程纪律，§7 已有规则）

**AI 编造证据冒充权威（2 次严重）**

- 场景: Redis 源码行为、docker 镜像架构
- 错误做法: 编造函数名 `aofManifestGetAndValidateDataFiles()` 包装成"查证过的事实"（自认"幻觉冒充权威"）；未跑 docker inspect 就引用虚构的 `Arch: amd64` 输出
- 正确做法: 不确定的内容禁止编造细节（函数名/行号/命令输出）；引用输出必须实际执行过
- 状态: 已沉淀（→ positive-rules.md 流程纪律）

### 三、破坏性操作类（最高伤害）

**未确认/未备份的破坏性操作（6 次）**

- 场景: 文件删除、数据库重建、git 回退
- 错误做法: ① 2026-07-23 ses_0727e8707 Plan 模式 `rm storage/repository/tsl.go`（untracked 未提交文件）→ 数据永久丢失，stash/reflog 都找不到，用户"你真是个废物"；② 2026-07-21 ses_07ddac654 擅自 DROP DATABASE test_db_pg（根因其实是自己部署漏 DBCOMPATIBILITY）；③ 2026-06-17 ses_12cd4b621 Python 批量替换误插 9 处，git restore 整文件回退又丢 6 个测试用例；④ 2026-08-07 ses_024a8d14c 把"删除内容"执行为"删除文件"（Practice/AGENTS.md 整文件 rm）
- 正确做法: rm/DROP/checkout/删文件前先 git status 确认跟踪状态 + 备份 + 征得用户同意；untracked 文件禁 rm 恢复路径；"删内容 vs 删文件"先确认
- 状态: 已沉淀（→ positive-rules.md 流程纪律）

**未经同意修改业务源码（2 次）**

- 场景: 密钥/私钥调试
- 错误做法: 2026-06-15 ses_13577a92 未经用户同意把新公钥写入业务源码 license/pkg/rsa.go（用户"我不希望 rsa.go 被修改"）
- 正确做法: 改动业务源码前先确认用户授权；调试优先用文件/环境变量
- 状态: 已沉淀（→ positive-rules.md 流程纪律）

### 四、迁移语义类（rbiotserver 特有，6 次）

- 场景: Mongo→openGauss 迁移，SQL 版 vs Mongo 版语义对比
- 错误做法: ① 查询维度变化漏检——SQL 版用 tslID 查询、Mongo 版用 ProductID（最大 Bug，两会话连续复发且被用户抓出"你理解的一致是什么呢"）；② 错误分支合并——Mongo 区分"无物模型 vs DB 故障"两条，SQL 版并成一条；③ 部分迁移——tsl reader 切 SQL、writer 留 Mongo，读写分离两套存储；④ 加原库没有的 UNIQUE INDEX 后照搬 upsert 模式；⑤ 漏存在性检查（TslNew 丢 FindOne）；⑥ 迁移 diff 混入风格改动（nil != err → err != nil 18 处、errors.Wrap → fmt.Errorf 14 处、多余中间变量 productType）
- 正确做法: 逐步骤对照原版语义（查询维度→后续引用、错误分支数、存在性检查、不加原库没有的约束）；diff 只含需求触发变更
- 状态: 已沉淀（→ positive-rules.md 流程纪律；项目级 AGENTS.md 已有契约注释纪律）

### 五、文档治理类（Practice 特有，12+ 次）

- 场景: Q-A 回填/归档、章节删除、规范写作
- 错误做法: ① 回填遗漏（06-06 AOF 内容漏掉）且归档后不瘦身（509→113 行才收敛）；② 删除章节后不修编号/索引表（两次复发，需用户逐个指出 1.2→1.1 后 1.3/1.4 仍漏）；③ 通用规范混入项目实现细节（30-01 写 rblogserver 测试策略）、B 模式专属 DDL 写进通用文档（用户"你是智障吗"）；④ 文档与代码脱节（删除分支后注释残留、README 与文档口径打架）；⑤ 索引表指向缺失文件（7 个 memory 文件 6 个不存在，反复命中不修）
- 正确做法: 删除/重排后全量检查编号连续性与引用；规范写作先区分通用 vs 项目；"已回填"类声明做存在性验证
- 状态: 已沉淀（→ positive-rules.md 流程纪律）

### 六、流程/规则违反类（10+ 次）

- 场景: skill 流程、记忆机制、openspec 操作
- 错误做法: ① 跳过 verify skill Step 3 用户审核直接执行；② 绕过 openspec-archive-change skill 手动归档（verify 缺失）；③ 完成态 tracking 文档移入 memory/（应保留原地+status 标记）；④ 认知形成不即时更新 MEMORY.md（用户"全局规则的文档写作机制没有生效"）；⑤ 任务执行遗忘已确认主体任务（只写了 AGENTS.md 规则忘改 spec 文件）；⑥ 用错 skill（该 brainstorming 却用别的）
- 正确做法: 按 skill 流程执行（Step 3 审核不可跳）；openspec 操作走对应 skill；记忆即时更新（§6）；多步骤任务建 todo 逐项核对
- 状态: 已沉淀（→ positive-rules.md 流程纪律）

### 七、沟通/解释类（用户画像相关）

- 场景: 概念解释、方案讲解
- 错误做法: ① 2026-06-06 ses_165816060 打比方解释被明确拒绝（"我不喜欢打比方……我是编程初学者，不是小白"）；② 2026-07-28 ses_057ec7c2 解释变更越讲越远，用户 4 次"没看懂"；③ 2026-06-05 学习任务直接写代码（违反引导原则，应给操作顺序级提示）
- 正确做法: 按用户画像分层解释（精确术语+数据流拆解）；先回答原始问题再开新话题；学习任务只引导不代写
- 状态: 已沉淀（→ profile.md 已有画像条目）

---

## 沉淀映射

| 模式 | positive-rules.md 落点 |
|------|----------------------|
| edit 先 Read / 失败重读 | 环境与工具 |
| todowrite/question 参数数组化 | 环境与工具 |
| 容器命令全路径/环境核对 | 环境与工具 |
| webfetch 不猜 URL | 环境与工具 |
| 断言先实测/标注待验证 | 流程纪律 |
| 破坏性操作先确认+备份 | 流程纪律 |
| 迁移语义等价 / 修改最小化 | 流程纪律 |
| 删除后同步编号索引 | 流程纪律 |
| 数据解读工具化 | 代码与测试 |
