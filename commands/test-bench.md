---
name: "test-bench"
description: 检测并执行数据库基准测试（benchmark），支持多数据库对比
category: Testing
tags: [benchmark, database]
---

用户调用 `/test-bench` 时，按以下流程执行：

### Step 1: 检测基准测试

```bash
go test -list "Benchmark" ./...
```

解析输出：
- 过滤 `[no test files]`、`ok` 状态等噪音
- 按包路径分组
- 提取基准测试函数名列表，注明预置数据量
```
./internal/data:
  BenchmarkInsertParallel (preload: 1M rows)
  BenchmarkSelectParallel (preload: 1M rows)
  BenchmarkCountParallel (preload: 1M rows)
  BenchmarkMinDateParallel (preload: 1M rows)

./internal/data/executor:
  BenchmarkConvertQuery
  BenchmarkBuildPagination
  BenchmarkCount
  BenchmarkAggregate
  BenchmarkBatchInsertParallel
  BenchmarkSelectParallel
  BenchmarkBatchInsert
```

### Step 2: 用户选择

使用 AskUserQuestion 让用户选择：

**问题1：选择包**
```
检测到以下包包含基准测试：
1. ./internal/data (4个，预置 1M 行)
2. ./internal/data/executor (7个，无需预置数据)

选择要执行的包：
```

**问题2：选择范围**
```
执行范围：
1. 执行全部 Benchmark
2. 执行单个 Benchmark
```

**问题3：数据库**
```
数据库选择：
1. 全部数据库（默认）
2. MySQL
3. TiDB
4. openGauss
```

**问题4：预置数据量（可选，通过 `PRELOAD_COUNT` 环境变量控制）**
```
预置数据量：
1. 1K
2. 10K
3. 100K
4. 1M（默认）
```

### Step 3: 执行测试

```bash
# 执行全部 Benchmark
PRELOAD_COUNT=<数据量> TEST_DB=<数据库> go test <包路径> -bench=Benchmark -benchmem -run=^$ -count=1 -timeout=30m

# 或执行单个 Benchmark
PRELOAD_COUNT=<数据量> TEST_DB=<数据库> go test <包路径> -bench=^<BenchmarkFunctionName>$ -benchmem -run=^$ -count=1 -timeout=30m
```

### Step 4: 处理测试失败

如果测试用例失败（非连接问题）：

1. 分析失败原因（查看 FAIL 行的错误信息）
2. **询问用户**：是否需要修复代码？
3. 用户确认后，执行修复并重试；否则由用户自行处理

### Step 5: 连接失败提示

如果测试输出包含连接失败错误（如 "connection refused"、"connect: connection refused"、"连接失败"）：

**读取配置源文件**，确认具体 DSN 后报告给用户：
1. `internal/data/setup_test.go` — data 包的 `AllTestDBConfigs`
2. `internal/data/executor/testconfig_test.go` — executor 包的 `allDBConfigs`

**报告格式**：
```
数据库连接失败：[具体错误信息]

当前 DSN 配置：
- MySQL:          [读取实际值]
- TiDB:           [读取实际值]
- openGauss-row:  [读取实际值]
- openGauss-col:  [读取实际值]

环境变量覆盖：
- export TEST_MYSQL_DSN="test_user:pass@tcp(host:port)/db"
- export TEST_OG_DSN="postgres://user:pass@host:port/db"

说明：数据库环境由用户自行准备，AI 不负责启动容器。请确保目标数据库已运行并可访问。
```

### Step 6: 报告结果

按数据库报告关键指标：
```
=== MySQL ===
BenchmarkInsertParallel-8   	     100	  12345678 ns/op	 500000 B/op	   10000 allocs/op

=== TiDB ==="""  ===
BenchmarkInsertParallel-8   	      50	  23456789 ns/op	 550000 B/op	   11000 allocs/op

=== openGauss-row ===
BenchmarkInsertParallel-8   	      20	  34567890 ns/op	 600000 B/op	   12000 allocs/op
```

对比关注点：
- **吞吐差异**：哪个数据库最快（ns/op 最低）
- **内存分配**：B/op 和 allocs/op 是否一致（异常高可能表明驱动差异）
- **openGauss 行列对比**：row vs col 在聚合/查询场景的差异
