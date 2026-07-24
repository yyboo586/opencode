-- MySQL init for executor testing
--
-- 说明：只做基础设施初始化（建库、建用户），不建业务表。
--
-- 产物：
--   数据库: test_db
--   用户: test_user
--   密码: Test@1234
--

CREATE DATABASE IF NOT EXISTS test_db DEFAULT CHARACTER SET utf8mb4;

DELIMITER //
CREATE PROCEDURE create_user_if_not_exists()
BEGIN
    DECLARE user_count INT;
    SELECT COUNT(*) INTO user_count FROM mysql.user WHERE user = 'test_user' AND host = '%';
    IF user_count = 0 THEN
        CREATE USER 'test_user'@'%' IDENTIFIED BY 'Test@1234';
    END IF;
END //
DELIMITER ;
CALL create_user_if_not_exists();
DROP PROCEDURE create_user_if_not_exists;

GRANT ALL PRIVILEGES ON test_db.* TO 'test_user'@'%';
FLUSH PRIVILEGES;