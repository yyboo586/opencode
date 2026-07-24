-- TiDB init for executor testing
--
-- 说明：只做基础设施初始化（建库、建用户），不建业务表。
--
-- 产物：
--   数据库: test_db
--   用户: test_user
--   密码: Test@1234
--

CREATE DATABASE IF NOT EXISTS test_db;
CREATE USER IF NOT EXISTS 'test_user'@'%' IDENTIFIED BY 'Test@1234';
GRANT ALL PRIVILEGES ON test_db.* TO 'test_user'@'%';
