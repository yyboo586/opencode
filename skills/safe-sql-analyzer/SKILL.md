---
name: safe-sql-analyzer
description: 只读数据库查询工具。通过 MCP 服务器执行 SELECT 语句，自动拒绝所有写操作。数据库环境部署统一由 test-env skill 负责。
---

# safe-sql-analyzer：只读 SQL 查询

## 安全规则（强制执行）

1. 绝对不能以任何理由生成或尝试 INSERT、UPDATE、DELETE、DROP、ALTER、CREATE 语句
2. 只能通过 `execute_readonly_query` 工具执行 SQL
   - 该工具已配置只读数据库账户，自动拒绝所有非 SELECT 语句
3. 无权知道数据库的密码、主机地址或凭证

## 前置条件

- 在 `opencode.json` 的 `mcp.safe-sql-analyzer` 中配置了 MCP 服务器
- 环境变量 `DB_DSN` 已设置为正确的数据库连接字符串
- MCP 服务器二进制已编译

## 数据库环境

数据库启动由 **test-env skill** 统一管理，本 skill 不独立启动数据库。

- 需要数据库时，先调用 test-env 启动目标数据库
- test-env 输出连接信息后，本 skill 通过 MCP 工具连接查询

## 操作流程

1. 如果用户询问表结构，调用 `list_tables` 和 `describe_table` 工具获取
2. 生成 SELECT 语句时，**始终添加 LIMIT 100**，除非用户明确要求更多
3. 执行后，以表格形式返回结果，并附上简单解释

## 构建与配置

MCP 服务器源码在 `11-Go/safe-sql-mcp/`，修改后需重新编译：

```bash
go build -o safe-sql-mcp.exe .
```

预制表和数据定义在 `11-Go/safe-sql-mcp/init.sql`，包含 `users`、`products`、`orders` 三张表及示例数据。

`opencode.json` 中 `mcp.safe-sql-analyzer.env.DB_DSN` 格式：

```
test_user:Test@1234@tcp(localhost:3306)/practice?charset=utf8mb4&parseTime=True
```

> ⚠️ 此 DSN 与 test-env 的 MySQL 环境使用同一套凭证（test_user / Test@1234），确保一致性。
