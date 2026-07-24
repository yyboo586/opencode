-- openGauss 6.0.0+ ROW/COLUMN STORE infra init
--
-- ⚠ 本脚本必须由超级用户（omm）执行。
--   原因：CREATE DATABASE / CREATE EXTENSION dolphin 需要超级用户权限。
--   注意：不可用 gaussdb 替代 omm——B 库首次连接必须由 omm 触发 dolphin 自动加载。

-- =====================================================================
-- Block 1: 创建用户
-- =====================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'test_user') THEN
        CREATE USER test_user WITH LOGIN PASSWORD 'Test@1234';
    END IF;
END
$$;

-- =====================================================================
-- Block 2: 创建数据库及初始化
-- DBCOMPATIBILITY 可选值：A(Oracle) / B(MySQL) / C(Teradata) / PG(PostgreSQL)，默认 A
-- =====================================================================
CREATE DATABASE IF NOT EXISTS test_db_oracle OWNER test_user DBCOMPATIBILITY = 'A';
CREATE DATABASE IF NOT EXISTS test_db_mysql OWNER test_user DBCOMPATIBILITY = 'B';
CREATE DATABASE IF NOT EXISTS test_db_pg OWNER test_user DBCOMPATIBILITY = 'PG';

\c test_db_oracle
GRANT ALL ON SCHEMA public TO test_user;
ALTER USER test_user SET search_path TO public;

\c test_db_mysql
CREATE EXTENSION IF NOT EXISTS dolphin;
GRANT ALL ON SCHEMA public TO test_user;
ALTER USER test_user SET search_path TO public;

\c test_db_pg
GRANT ALL ON SCHEMA public TO test_user;
ALTER USER test_user SET search_path TO public;

-- =====================================================================
-- Block 3: 调整配置参数（与 MySQL 对称）
-- 注意：openGauss 不支持 work_mem，已删除
-- =====================================================================
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET max_connections = 500;

-- 重新加载配置（部分参数需要重启才生效，但 init 脚本在首次启动时执行，重启后生效）
SELECT pg_reload_conf();
