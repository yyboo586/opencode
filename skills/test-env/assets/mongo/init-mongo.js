// ============================================================
// init-mongo.js — Mongo 容器首次启动自动初始化（docker-entrypoint-initdb.d）
// ============================================================
// 产物：
//   根用户:   admin / Test@1234（MONGO_INITDB_ROOT_USERNAME/PASSWORD 注入，此文件不重复创建）
//   业务用户: test_user / Test@1234（建于 rbiot 库，读写 rbiot 全部 collection）
//   业务库:   rbiot
//
// 注意：
//   - initdb 脚本仅在数据目录为空时执行一次（docker-entrypoint.sh 固有行为）
//   - MONGO_INITDB_DATABASE=rbiot 决定本脚本执行时的当前库，无需 use rbiot
//   - 用户必须建在 rbiot 库（roles 定义于此），连接方 authSource 即为 rbiot
// ============================================================

db.createUser({
    user: "test_user",
    pwd: "Test@12345678",
    roles: [
        { role: "readWrite", db: "rbiot" },
        { role: "dbAdmin", db: "rbiot" }
    ]
});

// logUser — 日志 hook 专用（rbIotDataserver log.InitLog() 用 LogUsername/LogUserPwd 连 Mongo，
// 凭据来自 Nacos dataId=mongo 播种内容：logUser/passWord1122#4566）
db.createUser({
    user: "logUser",
    pwd: "passWord1122#4566",
    roles: [
        { role: "readWrite", db: "rbiot" }
    ]
});