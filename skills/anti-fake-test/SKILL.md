---
name: anti-fake-test
description: 编写任何测试代码前必须加载本技能，确保不生成假测试
---

## 说明

本技能定义**假测试**的具体判定标准和正反示例。编写任何测试代码前必须逐项自检，确保测试真实验证被测对象的业务行为。

宪法第二条定义：**假测试是指未能有效验证被测对象核心业务行为的测试。**

## 十二条判定标准

### 1. 名称与验证内容必须一致

测试名称必须准确描述被验证的功能行为。名称说的是A，断言验证的是B，即为假测试。

### 2. 必须包含对实际行为效果的断言

每个测试必须断言被测对象的输出、状态变化或副作用。没有断言的测试不是测试。

### 3. 禁止只创建对象或调用方法而不验证行为效果

仅构造实例、调用方法、确认"没报错"，不验证任何结果 = 假测试。

### 4. 断言必须验证具体业务行为或状态变化，而非仅检查"无错误"

`assert.NoError(t, err)` 不是有效断言，除非被测对象的核心行为就是"不应报错"。必须验证返回值的具体内容。

### 5. 具有多阶段行为的功能，必须验证完整行为路径的核心阶段

如果功能分为"接收→处理→返回"三阶段，不能只验证"接收"阶段，跳过"处理"和"返回"。

### 6. 测试代码发射事件再自行验证 = 假测试

测试中手动 `log.Info("xxx", zap.String("field", val))` 再去日志中找这条记录验证，验证的是测试代码自身，不是被测对象。

### 7. 禁止 Mock 数据库

Mock 数据库的测试不验证真实 SQL 语法、列名映射、类型绑定、事务行为和 Schema 兼容性。所有涉及数据库交互的测试必须连接真实数据库。这是宪法铁律，无例外。

### 8. 测试必须具备反证能力

如果翻转被测代码的核心逻辑（如 `==` 改 `!=`、`true` 改 `false`、删除关键写入步骤），至少一条断言必须失败。测试不能在代码有 bug 时仍然通过。

### 9. 有显式错误处理分支的功能，必须测试失败路径

只测 happy path 给的是虚假信心。被测代码包含 `return err` 分支、校验失败分支、超时分支时，至少有一个测试触发该分支并验证错误行为（错误码、错误消息、状态不推进）。

### 10. 断言必须覆盖全部与本次操作相关的返回字段

返回值有 N 个业务字段时，与本次操作直接相关的字段必须全部断言，不可只挑一个。与 chain-db-validation 规范的"全部写入列不抽样"对齐。

### 11. 禁止用固定 sleep 等待异步操作完成

`time.Sleep(X * time.Second)` 假设操作在 X 秒内完成——太短则 flaky，太长则慢。必须用轮询等待或等待明确信号：

```go
// ❌ 禁止：固定 sleep 假设操作已完成
time.Sleep(3 * time.Second)
row, err := dbRowExists(id)

// ✅ 必须：轮询等待直到条件满足或超时
func waitForCondition(t *testing.T, timeout time.Duration, fn func() bool) bool {
    deadline := time.Now().Add(timeout)
    for time.Now().Before(deadline) {
        if fn() {
            return true
        }
        time.Sleep(200 * time.Millisecond)
    }
    return false
}

ok := waitForCondition(t, 30*time.Second, func() bool {
    exists, _ := dbRowExists(id)
    return exists
})
require.True(t, ok, "超时：条件未满足")