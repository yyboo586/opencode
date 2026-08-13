# 正面指令（注入层）

> 每次会话自动注入。本文件由 AI 自主管理（归并/重组/压缩/淘汰），**禁止平铺堆积**，人类不干涉内容管理。
> 每条一行：`场景: 正确做法`，必要时加半句易错锚点。写入前先查可归并条目，无法归并才新增。机制见 `AGENTS.md` §9。

## 环境与工具

- opengauss 容器内执行 gsql: 绝对路径 + LD_LIBRARY_PATH：`docker exec -it opengauss bash -c "LD_LIBRARY_PATH=/usr/local/opengauss/lib /usr/local/opengauss/bin/gsql ..."`（gsql 不在 PATH，直接 exec 会报错）
- 容器内其他二进制（gs_guc/mongodump 等）: 先确认执行环境与监听地址再给命令（gsql 教训通用化；容器内连宿主机映射端口必 refused）
- edit 工具: 先 Read 目标文件取精确 oldString（含全角/缩进/行尾），失败后重读再重试，不凭记忆猜（identical 说明已是目标状态应跳过；multiple 加唯一上下文锚点）
- todowrite/question 工具: 参数传数组对象本身不序列化成字符串（`{"todos": "[...]"}` → SchemaError）；报错后先核对 schema 字段（label/description/content/status/priority）再重试，不原样重试
- webfetch/URL: 不凭记忆猜 URL，先搜索或官方文档入口；连续失败切换 fallback 工具链；无法访问来源时先声明再作答
- 时间戳换算: 手算毫秒时间戳必错，让数据库算 `extract(epoch from ...) * 1000` 或使用代码库工具函数
- 给用户的生产/目标机命令: 先核对环境（docker-compose healthcheck 既有写法、busybox 无 pidof -f、部署机 uname -m、容器名 docker ps 实测），不套本地经验

## 流程纪律

- 方言/驱动/内核行为断言（openGauss/MySQL/Redis/pgx）: 先实测（建表实验/SHOW/pg_type/最小复现）再下结论，未验证显式标注"待验证"；用户质疑时先验证而非反驳
- 性能/可行性断言: 基于实测（先跑一批计时、多轮同条件对比），单轮对比与拍脑袋估算不构成结论
- "0 引用/不存在/已删除"类断言: 附搜索命令+范围（含 cmd/、test/、跨仓库引用），git 状态断言前先 git status
- 破坏性操作（rm/DROP/checkout/删文件）: 先 git status 确认跟踪状态 + 备份 + 征得用户同意；untracked 文件禁 rm 恢复路径；"删内容 vs 删文件"先确认
- 迁移/重构语义等价: 逐步骤对照原版（查询维度→后续引用、错误分支数、存在性检查、不加原库没有的约束），diff 只含需求触发变更不动未触及行风格
- 删除章节/文件/重排后: 立即全量检查编号连续性与内部引用、索引表同步，不等用户逐个指出
- 不确定内容禁止编造细节（函数名/行号/命令输出）: 引用的输出必须实际执行过，标注来源
- skill 流程: 按 skill 步骤执行（Step 3 用户审核不可跳），openspec 操作必须走对应 skill（verify → archive），不手动 mv 绕过
- 多步骤任务: 先建 todo 清单含全部子项，完成时逐项核对再收尾（防遗忘已确认主体任务）
- 写规则/文档前: 先 grep 定位既有规则实际位置与上级规则，跨仓库通用机制落全局、项目特有落项目 AGENTS.md

## 代码与测试

- 测试断言: 测被测单元真实行为点（如 consumeLoop 而非 processBatch），保证测试实际可执行（不永远 skip）
- 引入新依赖: 先查其 go.mod 的 go 版本声明（> 项目版本拒绝或降级），go get 后立即验证 go.mod 未升级
- 测试数据清理: 按测试特征键 + t.Cleanup 防御，不按脆弱 id 前缀；测试库残留用 TRUNCATE 而非逐条 DELETE
- 数据解读: goroutine 按栈块分割统计（awk RS="\n\n"）不用 grep 行数；/proc/diskstats 等字段先对照文档验证再统计
- 写完即验证: 自查漏 import/语法/注释与实现一致，改动后编译或测试立即验证再宣称完成
