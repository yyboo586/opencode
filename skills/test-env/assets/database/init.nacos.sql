-- init.nacos.sql — Nacos 2.4.3 配置库 schema 自动初始化
--
-- 由 openGauss entrypoint 在首次启动时自动执行 (docker-entrypoint-initdb.d)。
-- 对应 deploy/1.7.0/sh/init_db.sh 的 init_nacos_db() 4 个补丁，此处合并为静态 SQL。
--
-- 补丁清单:
--   1. 创建 nacos 用户 + nacos_config 库 (PG 兼容模式)
--   2. 导入 Nacos 2.4.3 官方 schema (12 张表 + 索引 + 主键 + 初始数据)
--   3. GRANT 授权 + ALTER DEFAULT PRIVILEGES
--   4. now(integer) 兼容函数 (openGauss 原生不支持, Nacos 2.4.3 会调用)
--   5. 批量 DROP NOT NULL (Nacos 不全传值, 69 个非主键 NOT NULL 字段会违反约束)
--
-- 与 init.opengauss.sql 互不依赖, 字母序 'n' < 'o' 先执行也无影响。

-- =====================================================================
-- Block 1: 创建 nacos 用户 (DO 块保证幂等)
-- =====================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'nacos') THEN
        CREATE USER nacos WITH LOGIN PASSWORD 'Password@1234';
    END IF;
END
$$;

-- =====================================================================
-- Block 2: 创建 nacos_config 库
-- 必须 PG 兼容模式: A 模式下空字符串视为 NULL, 会破坏 Nacos
-- CREATE DATABASE 不能在事务/DO 块里, 必须直接执行
-- =====================================================================
CREATE DATABASE nacos_config OWNER nacos DBCOMPATIBILITY = 'PG';

-- \c 是 gsql 元命令, 切到新库 (事务外执行, entrypoint 每条语句独立 autocommit)
\c nacos_config

-- =====================================================================
-- Block 3: schema 级授权
-- entrypoint 用 omm 超级用户跑, 建出的对象 owner 是 omm; nacos 用户需要权限
-- =====================================================================
GRANT ALL ON SCHEMA public TO nacos;
ALTER USER nacos SET search_path TO public;

-- =====================================================================
-- Block 4: Nacos 2.4.3 官方 schema DDL
-- 来源: nacos/nacos-server:v2.4.3 PG distribution, 经 deploy/1.7.0/sql/nacos_init_opengauss.sql 移植
-- =====================================================================

CREATE SCHEMA nacos;

-- ----------------------------
-- Table structure for config_info
-- ----------------------------
DROP TABLE IF EXISTS "config_info";
CREATE TABLE "config_info" (
  "id" bigserial NOT NULL,
  "data_id" varchar(255)  NOT NULL,
  "group_id" varchar(255) NOT NULL,
  "content" text  NOT NULL,
  "md5" varchar(32) ,
  "gmt_create" timestamp(6) NOT NULL,
  "gmt_modified" timestamp(6) NOT NULL,
  "src_user" text ,
  "src_ip" varchar(20) ,
  "app_name" varchar(128) ,
  "tenant_id" varchar(128) NOT NULL,
  "c_desc" varchar(256) ,
  "c_use" varchar(64) ,
  "effect" varchar(64) ,
  "type" varchar(64) ,
  "c_schema" text ,
  "encrypted_data_key" text  NOT NULL
)
;

COMMENT ON COLUMN "config_info"."id" IS 'id';
COMMENT ON COLUMN "config_info"."data_id" IS 'data_id';
COMMENT ON COLUMN "config_info"."content" IS 'content';
COMMENT ON COLUMN "config_info"."md5" IS 'md5';
COMMENT ON COLUMN "config_info"."gmt_create" IS '创建时间';
COMMENT ON COLUMN "config_info"."gmt_modified" IS '修改时间';
COMMENT ON COLUMN "config_info"."src_user" IS 'source user';
COMMENT ON COLUMN "config_info"."src_ip" IS 'source ip';
COMMENT ON COLUMN "config_info"."tenant_id" IS '租户字段';
COMMENT ON COLUMN "config_info"."encrypted_data_key" IS '秘钥';
COMMENT ON TABLE "config_info" IS 'config_info';


-- ----------------------------
-- Table structure for config_info_aggr
-- ----------------------------
DROP TABLE IF EXISTS "config_info_aggr";
CREATE TABLE "config_info_aggr" (
  "id" bigserial NOT NULL,
  "data_id" varchar(255)  NOT NULL,
  "group_id" varchar(255)  NOT NULL,
  "datum_id" varchar(255)  NOT NULL,
  "content" text  NOT NULL,
  "gmt_modified" timestamp(6) NOT NULL,
  "app_name" varchar(128) ,
  "tenant_id" varchar(128) NOT NULL
)
;
COMMENT ON COLUMN "config_info_aggr"."id" IS 'id';
COMMENT ON COLUMN "config_info_aggr"."data_id" IS 'data_id';
COMMENT ON COLUMN "config_info_aggr"."group_id" IS 'group_id';
COMMENT ON COLUMN "config_info_aggr"."datum_id" IS 'datum_id';
COMMENT ON COLUMN "config_info_aggr"."content" IS '内容';
COMMENT ON COLUMN "config_info_aggr"."gmt_modified" IS '修改时间';
COMMENT ON COLUMN "config_info_aggr"."tenant_id" IS '租户字段';
COMMENT ON TABLE "config_info_aggr" IS '增加租户字段';

-- ----------------------------
-- Table structure for config_info_beta
-- ----------------------------
DROP TABLE IF EXISTS "config_info_beta";
CREATE TABLE "config_info_beta" (
  "id" bigserial NOT NULL,
  "data_id" varchar(255)  NOT NULL,
  "group_id" varchar(128)  NOT NULL,
  "app_name" varchar(128) ,
  "content" text  NOT NULL,
  "beta_ips" varchar(1024) ,
  "md5" varchar(32) ,
  "gmt_create" timestamp(6) NOT NULL,
  "gmt_modified" timestamp(6) NOT NULL,
  "src_user" text ,
  "src_ip" varchar(20) ,
  "tenant_id" varchar(128) NOT NULL,
  "encrypted_data_key" text  NOT NULL
)
;
COMMENT ON COLUMN "config_info_beta"."id" IS 'id';
COMMENT ON COLUMN "config_info_beta"."data_id" IS 'data_id';
COMMENT ON COLUMN "config_info_beta"."group_id" IS 'group_id';
COMMENT ON COLUMN "config_info_beta"."app_name" IS 'app_name';
COMMENT ON COLUMN "config_info_beta"."content" IS 'content';
COMMENT ON COLUMN "config_info_beta"."beta_ips" IS 'betaIps';
COMMENT ON COLUMN "config_info_beta"."md5" IS 'md5';
COMMENT ON COLUMN "config_info_beta"."gmt_create" IS '创建时间';
COMMENT ON COLUMN "config_info_beta"."gmt_modified" IS '修改时间';
COMMENT ON COLUMN "config_info_beta"."src_user" IS 'source user';
COMMENT ON COLUMN "config_info_beta"."src_ip" IS 'source ip';
COMMENT ON COLUMN "config_info_beta"."tenant_id" IS '租户字段';
COMMENT ON COLUMN "config_info_beta"."encrypted_data_key" IS '秘钥';
COMMENT ON TABLE "config_info_beta" IS 'config_info_beta';

-- ----------------------------
-- Table structure for config_info_tag
-- ----------------------------
DROP TABLE IF EXISTS "config_info_tag";
CREATE TABLE "config_info_tag" (
  "id" bigserial NOT NULL,
  "data_id" varchar(255)  NOT NULL,
  "group_id" varchar(128)  NOT NULL,
  "tenant_id" varchar(128) NOT NULL,
  "tag_id" varchar(128)  NOT NULL,
  "app_name" varchar(128) ,
  "content" text  NOT NULL,
  "md5" varchar(32) ,
  "gmt_create" timestamp(6) NOT NULL,
  "gmt_modified" timestamp(6) NOT NULL,
  "src_user" text ,
  "src_ip" varchar(20)
)
;
COMMENT ON COLUMN "config_info_tag"."id" IS 'id';
COMMENT ON COLUMN "config_info_tag"."data_id" IS 'data_id';
COMMENT ON COLUMN "config_info_tag"."group_id" IS 'group_id';
COMMENT ON COLUMN "config_info_tag"."tenant_id" IS 'tenant_id';
COMMENT ON COLUMN "config_info_tag"."tag_id" IS 'tag_id';
COMMENT ON COLUMN "config_info_tag"."app_name" IS 'app_name';
COMMENT ON COLUMN "config_info_tag"."content" IS 'content';
COMMENT ON COLUMN "config_info_tag"."md5" IS 'md5';
COMMENT ON COLUMN "config_info_tag"."gmt_create" IS '创建时间';
COMMENT ON COLUMN "config_info_tag"."gmt_modified" IS '修改时间';
COMMENT ON COLUMN "config_info_tag"."src_user" IS 'source user';
COMMENT ON COLUMN "config_info_tag"."src_ip" IS 'source ip';
COMMENT ON TABLE "config_info_tag" IS 'config_info_tag';

-- ----------------------------
-- Table structure for config_tags_relation
-- ----------------------------
DROP TABLE IF EXISTS "config_tags_relation";
CREATE TABLE "config_tags_relation" (
  "id" bigserial NOT NULL,
  "tag_name" varchar(128)  NOT NULL,
  "tag_type" varchar(64) ,
  "data_id" varchar(255)  NOT NULL,
  "group_id" varchar(128)  NOT NULL,
  "tenant_id" varchar(128) NOT NULL,
  "nid" bigserial NOT NULL
)
;
COMMENT ON COLUMN "config_tags_relation"."id" IS 'id';
COMMENT ON COLUMN "config_tags_relation"."tag_name" IS 'tag_name';
COMMENT ON COLUMN "config_tags_relation"."tag_type" IS 'tag_type';
COMMENT ON COLUMN "config_tags_relation"."data_id" IS 'data_id';
COMMENT ON COLUMN "config_tags_relation"."group_id" IS 'group_id';
COMMENT ON COLUMN "config_tags_relation"."tenant_id" IS 'tenant_id';
COMMENT ON TABLE "config_tags_relation" IS 'config_tag_relation';

-- ----------------------------
-- Table structure for group_capacity
-- ----------------------------
DROP TABLE IF EXISTS "group_capacity";
CREATE TABLE "group_capacity" (
  "id" bigserial NOT NULL,
  "group_id" varchar(128)  NOT NULL,
  "quota" int4 NOT NULL,
  "usage" int4 NOT NULL,
  "max_size" int4 NOT NULL,
  "max_aggr_count" int4 NOT NULL,
  "max_aggr_size" int4 NOT NULL,
  "max_history_count" int4 NOT NULL,
  "gmt_create" timestamp(6) NOT NULL,
  "gmt_modified" timestamp(6) NOT NULL
)
;
COMMENT ON COLUMN "group_capacity"."id" IS '主键ID';
COMMENT ON COLUMN "group_capacity"."group_id" IS 'Group ID，空字符表示整个集群';
COMMENT ON COLUMN "group_capacity"."quota" IS '配额，0表示使用默认值';
COMMENT ON COLUMN "group_capacity"."usage" IS '使用量';
COMMENT ON COLUMN "group_capacity"."max_size" IS '单个配置大小上限，单位为字节，0表示使用默认值';
COMMENT ON COLUMN "group_capacity"."max_aggr_count" IS '聚合子配置最大个数，，0表示使用默认值';
COMMENT ON COLUMN "group_capacity"."max_aggr_size" IS '单个聚合数据的子配置大小上限，单位为字节，0表示使用默认值';
COMMENT ON COLUMN "group_capacity"."max_history_count" IS '最大变更历史数量';
COMMENT ON COLUMN "group_capacity"."gmt_create" IS '创建时间';
COMMENT ON COLUMN "group_capacity"."gmt_modified" IS '修改时间';
COMMENT ON TABLE "group_capacity" IS '集群、各Group容量信息表';

-- ----------------------------
-- Table structure for his_config_info
-- ----------------------------
DROP TABLE IF EXISTS "his_config_info";
CREATE TABLE "his_config_info" (
  "id" int8 NOT NULL,
  "nid" bigserial NOT NULL,
  "data_id" varchar(255)  NOT NULL,
  "group_id" varchar(128)  NOT NULL,
  "app_name" varchar(128) ,
  "content" text  NOT NULL,
  "md5" varchar(32) ,
  "gmt_create" timestamp(6) NOT NULL  DEFAULT '2010-05-05 00:00:00',
  "gmt_modified" timestamp(6) NOT NULL,
  "src_user" text ,
  "src_ip" varchar(20) ,
  "op_type" char(10) ,
  "tenant_id" varchar(128) NOT NULL,
  "encrypted_data_key" text  NOT NULL
)
;
COMMENT ON COLUMN "his_config_info"."app_name" IS 'app_name';
COMMENT ON COLUMN "his_config_info"."tenant_id" IS '租户字段';
COMMENT ON COLUMN "his_config_info"."encrypted_data_key" IS '秘钥';
COMMENT ON TABLE "his_config_info" IS '多租户改造';


-- ----------------------------
-- Table structure for permissions
-- ----------------------------
DROP TABLE IF EXISTS "permissions";
CREATE TABLE "permissions" (
  "role" varchar(50)  NOT NULL,
  "resource" varchar(512)  NOT NULL,
  "action" varchar(8)  NOT NULL
)
;

-- ----------------------------
-- Table structure for roles
-- ----------------------------
DROP TABLE IF EXISTS "roles";
CREATE TABLE "roles" (
  "username" varchar(50)  NOT NULL,
  "role" varchar(50)  NOT NULL
)
;

-- ----------------------------
-- Records of roles
-- ----------------------------
BEGIN;
INSERT INTO "roles" VALUES ('nacos', 'ROLE_ADMIN');
COMMIT;

-- ----------------------------
-- Table structure for tenant_capacity
-- ----------------------------
DROP TABLE IF EXISTS "tenant_capacity";
CREATE TABLE "tenant_capacity" (
  "id" bigserial NOT NULL,
  "tenant_id" varchar(128)  NOT NULL,
  "quota" int4 NOT NULL,
  "usage" int4 NOT NULL,
  "max_size" int4 NOT NULL,
  "max_aggr_count" int4 NOT NULL,
  "max_aggr_size" int4 NOT NULL,
  "max_history_count" int4 NOT NULL,
  "gmt_create" timestamp(6) NOT NULL,
  "gmt_modified" timestamp(6) NOT NULL
)
;
COMMENT ON COLUMN "tenant_capacity"."id" IS '主键ID';
COMMENT ON COLUMN "tenant_capacity"."tenant_id" IS 'Tenant ID';
COMMENT ON COLUMN "tenant_capacity"."quota" IS '配额，0表示使用默认值';
COMMENT ON COLUMN "tenant_capacity"."usage" IS '使用量';
COMMENT ON COLUMN "tenant_capacity"."max_size" IS '单个配置大小上限，单位为字节，0表示使用默认值';
COMMENT ON COLUMN "tenant_capacity"."max_aggr_count" IS '聚合子配置最大个数';
COMMENT ON COLUMN "tenant_capacity"."max_aggr_size" IS '单个聚合数据的子配置大小上限，单位为字节，0表示使用默认值';
COMMENT ON COLUMN "tenant_capacity"."max_history_count" IS '最大变更历史数量';
COMMENT ON COLUMN "tenant_capacity"."gmt_create" IS '创建时间';
COMMENT ON COLUMN "tenant_capacity"."gmt_modified" IS '修改时间';
COMMENT ON TABLE "tenant_capacity" IS '租户容量信息表';

-- ----------------------------
-- Table structure for tenant_info
-- ----------------------------
DROP TABLE IF EXISTS "tenant_info";
CREATE TABLE "tenant_info" (
  "id" bigserial NOT NULL,
  "kp" varchar(128)  NOT NULL,
  "tenant_id" varchar(128) NOT NULL,
  "tenant_name" varchar(128) ,
  "tenant_desc" varchar(256) ,
  "create_source" varchar(32) ,
  "gmt_create" int8 NOT NULL,
  "gmt_modified" int8 NOT NULL
)
;
COMMENT ON COLUMN "tenant_info"."id" IS 'id';
COMMENT ON COLUMN "tenant_info"."kp" IS 'kp';
COMMENT ON COLUMN "tenant_info"."tenant_id" IS 'tenant_id';
COMMENT ON COLUMN "tenant_info"."tenant_name" IS 'tenant_name';
COMMENT ON COLUMN "tenant_info"."tenant_desc" IS 'tenant_desc';
COMMENT ON COLUMN "tenant_info"."create_source" IS 'create_source';
COMMENT ON COLUMN "tenant_info"."gmt_create" IS '创建时间';
COMMENT ON COLUMN "tenant_info"."gmt_modified" IS '修改时间';
COMMENT ON TABLE "tenant_info" IS 'tenant_info';

-- ----------------------------
-- Table structure for users
-- ----------------------------
DROP TABLE IF EXISTS "users";
CREATE TABLE "users" (
  "username" varchar(50)  NOT NULL,
  "password" varchar(500)  NOT NULL,
  "enabled" boolean NOT NULL
)
;

-- ----------------------------
-- Records of users
-- ----------------------------
BEGIN;
INSERT INTO "users" VALUES ('nacos', '$2a$10$EuWPZHzz32dJN7jexM34MOeYirDdFAZm2kuWj7VEOJhhZkDrxfvUu', TRUE);
COMMIT;

-- ----------------------------
-- Indexes structure for table config_info
-- ----------------------------
CREATE UNIQUE INDEX "uk_configinfo_datagrouptenant" ON "config_info" ("data_id","group_id","tenant_id");

-- ----------------------------
-- Primary Key structure for table config_info
-- ----------------------------
ALTER TABLE "config_info" ADD CONSTRAINT "config_info_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Indexes structure for table config_info_aggr
-- ----------------------------
CREATE UNIQUE INDEX "uk_configinfoaggr_datagrouptenantdatum" ON "config_info_aggr" USING btree ("data_id","group_id","tenant_id","datum_id");

-- ----------------------------
-- Primary Key structure for table config_info_aggr
-- ----------------------------
ALTER TABLE "config_info_aggr" ADD CONSTRAINT "config_info_aggr_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Indexes structure for table config_info_beta
-- ----------------------------
CREATE UNIQUE INDEX "uk_configinfobeta_datagrouptenant" ON "config_info_beta" USING btree ("data_id","group_id","tenant_id");

-- ----------------------------
-- Primary Key structure for table config_info_beta
-- ----------------------------
ALTER TABLE "config_info_beta" ADD CONSTRAINT "config_info_beta_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Indexes structure for table config_info_tag
-- ----------------------------
CREATE UNIQUE INDEX "uk_configinfotag_datagrouptenanttag" ON "config_info_tag" USING btree ("data_id","group_id","tenant_id","tag_id");

-- ----------------------------
-- Primary Key structure for table config_info_tag
-- ----------------------------
ALTER TABLE "config_info_tag" ADD CONSTRAINT "config_info_tag_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Indexes structure for table config_tags_relation
-- ----------------------------
CREATE INDEX "idx_tenant_id" ON "config_tags_relation" USING btree (
  "tenant_id"
);
CREATE UNIQUE INDEX "uk_configtagrelation_configidtag" ON "config_tags_relation" USING btree (
  "id",
  "tag_name",
  "tag_type"
);

-- ----------------------------
-- Primary Key structure for table config_tags_relation
-- ----------------------------
ALTER TABLE "config_tags_relation" ADD CONSTRAINT "config_tags_relation_pkey" PRIMARY KEY ("nid");

-- ----------------------------
-- Indexes structure for table group_capacity
-- ----------------------------
CREATE UNIQUE INDEX "uk_group_id" ON "group_capacity" USING btree (
  "group_id"
);

-- ----------------------------
-- Primary Key structure for table group_capacity
-- ----------------------------
ALTER TABLE "group_capacity" ADD CONSTRAINT "group_capacity_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Indexes structure for table his_config_info
-- ----------------------------
CREATE INDEX "idx_did" ON "his_config_info" USING btree (
  "data_id"
);
CREATE INDEX "idx_gmt_create" ON "his_config_info" USING btree (
  "gmt_create"
);
CREATE INDEX "idx_gmt_modified" ON "his_config_info" USING btree (
  "gmt_modified"
);

-- ----------------------------
-- Primary Key structure for table his_config_info
-- ----------------------------
ALTER TABLE "his_config_info" ADD CONSTRAINT "his_config_info_pkey" PRIMARY KEY ("nid");

-- ----------------------------
-- Indexes structure for table permissions
-- ----------------------------
CREATE UNIQUE INDEX "uk_role_permission" ON "permissions" USING btree (
  "role",
  "resource",
  "action"
);

-- ----------------------------
-- Indexes structure for table roles
-- ----------------------------
CREATE UNIQUE INDEX "uk_username_role" ON "roles" USING btree (
  "username",
  "role"
);

-- ----------------------------
-- Indexes structure for table tenant_capacity
-- ----------------------------
CREATE UNIQUE INDEX "uk_tenant_id" ON "tenant_capacity" USING btree (
  "tenant_id"
);

-- ----------------------------
-- Primary Key structure for table tenant_capacity
-- ----------------------------
ALTER TABLE "tenant_capacity" ADD CONSTRAINT "tenant_capacity_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Indexes structure for table tenant_info
-- ----------------------------
CREATE UNIQUE INDEX "uk_tenant_info_kptenantid" ON "tenant_info" USING btree (
  "kp",
  "tenant_id"
);

-- =====================================================================
-- Block 5: 表级授权 + 默认权限 (后续 CREATE TABLE 也授权给 nacos)
-- =====================================================================
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO nacos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO nacos;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES    TO nacos;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO nacos;

-- =====================================================================
-- Block 6: now(integer) 兼容函数
-- Nacos 2.4.3 调用 now(integer), openGauss 原生不支持
-- CREATE OR REPLACE 本身幂等
-- =====================================================================
CREATE OR REPLACE FUNCTION now(integer) RETURNS timestamp with time zone
AS $$ SELECT now(); $$ LANGUAGE SQL IMMUTABLE;

-- =====================================================================
-- Block 7: 批量 DROP NOT NULL (非主键字段)
-- Nacos 不全传值, 69 个非主键 NOT NULL 字段会触发约束违反
-- 用 DO 块 + FOR LOOP + EXECUTE format() 把 deploy init_db.sh 的动态 SQL 压成静态
-- 跳过 id/nid (主键/伪主键必须保持 NOT NULL)
-- =====================================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND is_nullable = 'NO'
          AND column_name NOT IN ('id', 'nid')
    LOOP
        EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I DROP NOT NULL;',
                       r.table_name, r.column_name);
    END LOOP;
END
$$;
