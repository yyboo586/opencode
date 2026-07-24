---
name: "test-integration"
description: 检测并执行集成测试，连接失败时输出排查指引
category: Testing
tags: [integration-test, database]
---

用户调用 `/test-integration` 时，按以下流程执行：

### Step 1: 检测集成测试

集成测试的判断标准：测试函数中使用了数据库连接（如 `setupTestExecutor`、`testConnect`、`NewFromDSN` 等），不依赖命名约定。

**查找包含数据库连接的测试文件：**
```bash
grep -rl "setupTestExecutor\|testConnect\|NewFromDSN\|sql\.Open\|executor\.New" --include="*_test.go" ./
```

**从匹配文件中提取测试函数：**
```bash
grep -h "^func Test" $(grep -rl "setupTestExecutor\|testConnect\|NewFromDSN" --include="*_test.go" ./) 2>/dev/null | sed 's/func //; s/(.*//'
```

**按包路径分组整理输出**，格式如：
```
./internal/data:
  TestIntegrationCLog_Save (8 subtests)
  TestIntegrationCLog_Query (15 subtests)
  TestIntegrationCLog_Delete (2 subtests)

./internal/data/executor:
  TestNewFromDSN_MySQL
  TestBatchExec
  ...
```

### Step 2: 用户选择

使用 AskUserQuestion 让用户选择：

**问题1：选择测试包**
```
检测到以下包包含集成测试：
1. ./internal/data (6个测试)
2. ./internal/data/executor (5个测试)

选择要执行的包：
```

**问题2：选择测试范围（可选）**
```
执行范围：
1. 执行全部测试
2. 执行单个测试函数（列出具体函数名）
```

**问题3：环境变量过滤（如果项目支持 `TEST_DB` 等机制）**
```
数据库选择：
1. 全部数据库（默认）
2. MySQL
3. openGauss-row
4. TiDB
```

### Step 3: 执行测试

根据 Step 1 检测到的测试函数名直接运行（不依赖 `TestIntegration` 命名约定）：

```bash
# 执行整个包的测试（包内所有测试）
go test <包路径> -v -count=1 -timeout=5m

# 或执行单个测试函数
go test <包路径> -v -count=1 -run ^<TestFunctionName>$ -timeout=5m
```

环境变量设置：
```bash
# 仅测 MySQL
TEST_DB=MySQL go test ./internal/data/ -v -count=1 -run ^TestIntegrationCLog_Save$ -timeout=5m
```

### Step 4: 连接失败提示

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

### Step 5: 处理测试失败

如果测试用例失败（非连接问题）：

1. 分析并报告失败原因（查看 FAIL 行的错误信息）
2. **询问用户**：是否需要修复代码？
3. 用户同意修复后，再执行修复并重试；否则禁止修改代码。

### Step 6: 报告结果

测试完成后报告摘要：
- PASS/FAIL 数量
- 失败用例的诊断（如果有）

---

## 检测示例

扫描包含 DB 连接的测试文件 → 提取测试函数：

```
# grep 匹配的测试文件
internal/data/integration_test.go
internal/data/setup_test.go
internal/data/executor/executor_test.go

# 提取的测试函数
TestIntegrationCLog_Save
TestIntegrationCLog_Query
TestIntegrationCLog_Query_OrderByDesc
TestIntegrationCLog_Query_CountTotal
TestIntegrationCLog_Delete
TestIntegrationCLog_Select
TestNewFromDSN_MySQL
TestNewFromDSN_OpenGauss
TestNewFromDSN_Invalid
```

**运行子测试**：`go test -run "^TestIntegrationCLog_Save$/Complete"`

