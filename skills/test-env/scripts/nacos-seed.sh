#!/bin/bash
# nacos-seed.sh — 部署 Nacos 后播种业务配置（幂等，内容硬编码自包含）
#
# 覆盖两组（同一 Nacos，group 不同）：
#
# 组 1: group=iot_data_server（rbIotDataserver）
#   - dataId=mongo        → Mongo 连接配置（rbIotDataserver 的 DatabaseConfig）
#   - dataId=forward      → 转发配置（ForwardConfigData）
#   - dataId=database     → SQL(openGauss) 连接配置（SqlConfig，repo-sql-migration 阶段二）
#   - dataId=mqtt_forward → MQTT 转发配置（MqttForwardConfigData；最小配置=合法 cron+空 sites，
#                           缺失时 cron.AddFunc 报错 panic——本地启动必炸点，故必播）
# 不播种（拍板 2026-09-02）：aggregate（cron 空时 aggregateserver 静默跳过，本地无设备数据无意义）
#
# 组 2: group=iot_server（rbiotserver，2026-09-03 新增）
#   rbiotserver 全 11 dataId：database/device_acl/device_api/emqx/grpc/https/server/session/
#   system_topic/visual_device/worker。内容对齐 round3-verify/phase3-sql-run configs 模板
#   （DB=test_db_pg/test_user，服务端口 8008，cert 走 execDir 相对路径 cert/...）。
#   database 必须含 maxdatalife>30（TTL fail-fast panic）——旧播种内容缺此字段，--force 覆盖。
#
# 组 3: group=log_server（rblogserver，2026-09-03 新增）
#   单 dataId=run.yaml（rblogserver 唯一配置源，Nacos 硬依赖无本地模式）。
#   内容对齐 cmd/rblogserver/cache/config/run-test.yaml（e2e 测试同源模板）：
#   DB=test_db_pg/test_user，HTTP 18008 / gRPC 19009，Redis localhost。
#   注意：rblogserver 启动链无本地 fallback，ip/port 空直接 panic——组 3 必播。
#
# 幂等策略：先 GET 判断，已存在则跳过（--force 覆盖）
# API：Nacos OpenAPI v1，鉴权关闭（test-env custom-application.properties）
#
# 前置条件：
#   1. Nacos 已由 test-env/scripts/nacos.sh 部署并探活
#
# 用法：
#   ./nacos-seed.sh          # 幂等：存在跳过
#   ./nacos-seed.sh --force  # 覆盖已存在配置
#
# 注意（2026-08-31 拍板）：播种内容不读仓内 yml，直接硬编码于此——
# 本脚本是播种内容的唯一事实源；configs/ 下同名文件为本地模式模板（gitignored）。

set -euo pipefail

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
    esac
done

NACOS_HOST="${NACOS_HOST:-127.0.0.1}"
NACOS_PORT="${NACOS_PORT:-8848}"
BASE_URL="http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs"

# ---------- 探活 ----------
if ! curl -sf "http://${NACOS_HOST}:${NACOS_PORT}/nacos/actuator/health" >/dev/null 2>&1; then
    echo "❌ Nacos (${NACOS_HOST}:${NACOS_PORT}) 不可达，先运行 test-env nacos.sh" >&2
    exit 1
fi
echo "Nacos 探活 OK"

# ============================================================
# 组 1 播种内容（iot_data_server）
# ============================================================

# 2026-09-03 拍板：清理死字段——logusername/loguserpwd（8bd799c 删消费方，log 改写 openGauss t_log）、
# maxPoolSize/maxWaitTime（无消费方且 camelCase 键不匹配 yaml.v2 小写键）、writeConcern（struct 未导出 yaml 不可达）。
# 残留旧字段无害（yaml.v2 非严格模式静默忽略），但会误导配置排查，不再播种。
# 2026-09-08 起密码契约变更（dataserver 1.4.11 缺陷 #6 修复）：pkg/database.go Mongo URI
# 凭据改 url.QueryEscape 运行时转义 → 配置写原形密码（Test@12345678）；
# 历史 %40 写法会被二次转义成 %2540 导致认证失败。
MONGO_CONTENT='host: 127.0.0.1
port: 27017
user: admin
password: Test@12345678
databasename: rbiot'

FORWARD_CONTENT='forwardurl: "/api/local/run_scene"
forwardhost: "127.0.0.1"
forwardhttp: "http://"'

# SQL(openGauss) 连接配置（repo-sql-migration 阶段二；test-env 指向 test_db_pg 影子表库）
DATABASE_CONTENT='host: 127.0.0.1
port: 5432
user: test_user
password: Test@1234
databasename: test_db_pg
maxopenconns: 50
maxidleconns: 10
connmaxlife: 1800'

# MQTT 转发最小配置（2026-09-02 拍板）：合法 cron + 空 sites——服务启动必需（缺失即 panic），
# 本地无 EMQX/无转发目标，空跑无副作用
MQTT_FORWARD_CONTENT='corpid: ""
cron: "0 */5 * * *"
sites: []'

# ============================================================
# 组 2 播种内容（iot_server / rbiotserver，2026-09-03 拍板）
# 键名对齐各 struct yaml.v2 小写规则；内容对齐 phase3-sql-run configs（execDir=仓根约定）
# ============================================================

# rbiotserver DbConfig：database.NewDb + MustInitExecutorFromConfig + TTL 三服务。
# maxdatalife 必填且 >30（database.go:106/152 panic）；maxforeverydatalife<=0 时 forever TTL 跳过。
# 注意与组 1 database 词表不同（无 maxopenconns 等池键，有 maxdatalife）。
RB_DATABASE_CONTENT='host: 127.0.0.1
port: 5432
user: test_user
password: Test@1234
databasename: test_db_pg
maxdatalife: 60
maxforeverydatalife: 720'

# DeviceACL：config/device_acl_config.go（Pubsub 控 v1/gateway 主题族）
RB_DEVICE_ACL_CONTENT='publish:
subscribe:
pubsub: ['"'"'v1/gateway/{{clientid}}/connect'"'"','"'"'v1/gateway/{{clientid}}/disconnect'"'"','"'"'v1/gateway/{{clientid}}/data'"'"','"'"'v1/gateway/{{clientid}}/attributes'"'"','"'"'v1/gateway/{{clientid}}/attributes/request'"'"','"'"'v1/gateway/{{clientid}}/attributes/response'"'"','"'"'v1/gateway/{{clientid}}/telemetry'"'"','"'"'v1/gateway/{{clientid}}/rpc'"'"','"'"'v1/gateway/{{clientid}}/event'"'"']'

# DeviceApi：config/device_api_config.go（下行 RPC 方法名映射）
RB_DEVICE_API_CONTENT='method:
  reboot: device_reboot
  uploadlog: device_log_upload
  deletesubdevice: subdev_delete
event:
attribute:'

# EmqxConfig：config/emqx_config.go。returntopic/clientid 双实例区分用；
# 本地单实例沿用 phase3 值（mqtt_message_return 与 rb 前缀）
RB_EMQX_CONTENT='#下列 ip,port 用于将mqtt消息重新送回emqx系统
ip: 127.0.0.1
port: 1883
# 被拦截器处理后的消息需要重新回到emqx，如果直接扔回emqx则会重新被hook获取又再次进入拦截器形成死循环
# 因此被拦截器处理后的消息重新回到emqx前在topic前加一个标志，有此标志的消息直接通过hook返回给emqx
republishflag: RB7interceptor7publishRB_
maxluapool: 100
# server 主动下行消息发回 EMQX 的回环 topic（双实例：SQL 版 rb_sql / Mongo 版 rb_mongo）
returntopic: mqtt/message/return/rb
# server 作为 MQTT 客户端连 EMQX 的 ClientID（双实例必须不同，否则互踢）
clientid: mqtt_message_return'

# GrpcConfig：config/grpc_config.go。dataserver 必填（grpc.Dial panic）；bypass/rulego/powermeter
# 为空列表时惰性重连不 panic；cert 路径相对 execDir（仓根运行约定 → cert/...）
RB_GRPC_CONTENT='dataserver:
  ip: 127.0.0.1
  port: 9090
bypassserver:
  appid: 29b41d4a71
  appsecret: 550e8400e29b41d4a716446655440000
  bypassport: 12671
rulegoservers:
  servers:
    - server: 127.0.0.1:9527
      name: rb-iot-rule-server
powermeterservers:
  cacertfile: cert/ca.crt
  certfile: cert/client-rbPowerMeterGrpcClient.crt
  keyfile: cert/client-rbPowerMeterGrpcClient.key
  servers:
    - server: 127.0.0.1:9528
      name: rb-powermeter-server'

# HttpsConfig：config/https_config.go。PowerMeterApi.Servers 空 → PowerMeterApiForwardInit panic
# （api/power_meter_forward.go:30）；cert 路径相对 execDir（仓根运行 → cert/...）。
# center-server url/secret 空 → center forward disabled（日志行，非 panic）。
RB_HTTPS_CONTENT='#此配置为电量计量api转发
powermeterapi:
  cacertfile: cert/ca.crt
  certfile: cert/client-rbPowerMeterGrpcClient.crt
  keyfile: cert/client-rbPowerMeterGrpcClient.key
  servers:
    - forwardurl: https://127.0.0.1:9530/power-meter
      name: rb-powermeter-https-server
center-server:
  url: ""
  secret: ""'

# SinoServer：config/server_config.go。port 必填（graceful.Run 监听）；ntp-port 留空
# （123 特权端口；留空则 StartNtpServer 直接 return）
RB_SERVER_CONTENT='port: 8008
# 用于设备固件升级填写下载url
ip: 127.0.0.1
ntp-port:'

# SessionConfig：config/session_config.go（cookie 会话，default 标签装饰性须显式给值）
RB_SESSION_CONTENT='secret: rbiot_service_repair_web_secret
path: /
maxage: 604800
httponly: True'

# WorkerConfig：config/worker_config.go（worker 池大小；0 时 NewDispatcher 兜底 10000）
RB_WORKER_CONTENT='maxworker: 100
maxcachequeue: 200'

# VisualDeviceConfig：config/visual_device_config.go（在线检查周期/重试）
RB_VISUAL_DEVICE_CONTENT='#设备在线检查间隔（秒）
onlinecheckinterval: 600
#在线检查重试次数
retrycount: 1
#子设备离线识别周期（小时）。只对无网关的子设备生效
subdevicecheckinterval: 48'

# SystemTopicConfig：config/system_topic.go（主题族；NewSystemTopic 里做正则编译，缺字段空串安全）
RB_SYSTEM_TOPIC_CONTENT='topic: ['"'"'subscribe/message/page/send'"'"','"'"'subscribe/message/to/page'"'"']
offtopic: '"'"'v1/gateway/{{clientid}}/disconnect'"'"'
onlinetopic: '"'"'v1/gateway/{{clientid}}/connect'"'"'
eventtopic: '"'"'v1/gateway/{{clientid}}/event'"'"'
rpctopic: '"'"'v1/gateway/{{clientid}}/rpc'"'"'
datatopic: '"'"'v1/gateway/{{clientid}}/data'"'"'
attributetopic: '"'"'v1/gateway/{{clientid}}/attributes'"'"'
edgeforwardtopic: '"'"'mqtt/edgeserver/forwordmessage'"'"'
edgeforwardcompresstopic: '"'"'mqtt/edgeserver/forwordmessage/compress'"'"'
edgeattributetopic: '"'"'rb/edge/device/{{clientid}}/attributes'"'"'
edgerpctopic: '"'"'rb/edge/device/{{clientid}}/rpc'"'"'
edgenoticetopic: '"'"'rb/edge/device/{{clientid}}/notice'"'"'
responsetopic: '"'"'v1/gateway/{{clientid}}/attributes/response'"'"'
#直接设备
attributedirecttopic: '"'"'v1/device/{{clientid}}/attributes'"'"'
eventdirecttopic: '"'"'v1/device/{{clientid}}/event'"'"'
datadirecttopic: '"'"'v1/device/{{clientid}}/data'"'"'
responsedirecttopic: '"'"'v1/device/{{clientid}}/attributes/response'"'"''

# ============================================================
# 组 3 播种内容（log_server / rblogserver，2026-09-03 拍板）
# 内容对齐 cmd/rblogserver/cache/config/run-test.yaml（e2e 测试同源模板）。
# rblogserver 启动链 Nacos 硬依赖（无本地模式），组 3 必播。
# ============================================================

RBLOG_RUN_YAML_CONTENT='# run.yaml — 测试环境配置（rblogserver 本地启动 / e2e 测试用）
# 对齐 cmd/rblogserver/cache/config/run-test.yaml；生产模板见 run.yaml（同目录）。
server:
  http:
    addr: 0.0.0.0:18008
    timeout: 1s
  grpc:
    addr: 0.0.0.0:19009
    timeout: 1s
data:
  maxlife: 6
  database:
    driver: pgx
    source: postgres://test_user:Test@1234@127.0.0.1:5432/test_db_pg
    max_open_conns: 50
    max_idle_conns: 10
    conn_max_life_minutes: 30
redis:
  addr: "127.0.0.1:6379"
  password: "Test@1234"
  trace_stream: "rb:trace:stream"
  logevent_stream: "rb:logevent:stream"
  consumer_group: "rb-log-server"
  consumer_name: "consumer-1"
  read_count: 10
  block_ms: 5000
  stream_max_len: 500
  dial_timeout_ms: 1000
  read_timeout_ms: 2000
  write_timeout_ms: 1000
  message_timeout_ms: 3000
trace:
  scan_interval: 1
  scan_delay: 1
  scan_page_size: 100
  clean_interval: 15
  retention_ttl: 1
  pre_create_months: 3
  partition_interval: 86400
app_log:
  filename: ./logs/app.log
  max_size: 100
  max_age: 7
  max_backups: 10
  local_time: true
  compress: false
  level: debug'

# ---------- 通用播种函数 ----------
seed_config() {
    local group="$1"
    shift
    local label="$1"
    shift
    local content="$1"
    local dataId="${label}"

    # GET 判断是否已存在（-sf 在 404 时退出码 22 且无输出，用 -s 不带 f，取 http_code 判断）
    local exists
    exists=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs?dataId=${dataId}&group=${group}") || exists="ERR"
    if [[ "$exists" == "200" && "$FORCE" != "1" ]]; then
        echo "⏭️  dataId=${dataId}（group=${group}）已存在，跳过（--force 覆盖）"
        return 0
    fi

    # POST 发布（type=yaml；--data-urlencode 保 UTF-8 与换行；-s 不带 f 取 http_code）
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "dataId=${dataId}" \
        --data-urlencode "group=${group}" \
        --data-urlencode "type=yaml" \
        --data-urlencode "content=${content}")

    if [[ "$http_code" == "200" ]]; then
        echo "✅ dataId=${dataId}（group=${group}）已播种（内容硬编码于本脚本）"
        return 0
    fi
    echo "❌ dataId=${dataId}（group=${group}）播种失败 HTTP=${http_code}" >&2
    return 1
}

# ---------- 组 1：iot_data_server（rbIotDataserver） ----------
echo
echo "=== 组 1：iot_data_server（rbIotDataserver）==="
seed_config "iot_data_server" "mongo"         "$MONGO_CONTENT"
seed_config "iot_data_server" "forward"       "$FORWARD_CONTENT"
seed_config "iot_data_server" "database"      "$DATABASE_CONTENT"
seed_config "iot_data_server" "mqtt_forward"  "$MQTT_FORWARD_CONTENT"

# ---------- 组 2：iot_server（rbiotserver） ----------
echo
echo "=== 组 2：iot_server（rbiotserver）==="
seed_config "iot_server" "database"      "$RB_DATABASE_CONTENT"
seed_config "iot_server" "device_acl"    "$RB_DEVICE_ACL_CONTENT"
seed_config "iot_server" "device_api"    "$RB_DEVICE_API_CONTENT"
seed_config "iot_server" "emqx"          "$RB_EMQX_CONTENT"
seed_config "iot_server" "grpc"          "$RB_GRPC_CONTENT"
seed_config "iot_server" "https"         "$RB_HTTPS_CONTENT"
seed_config "iot_server" "server"        "$RB_SERVER_CONTENT"
seed_config "iot_server" "session"       "$RB_SESSION_CONTENT"
seed_config "iot_server" "worker"        "$RB_WORKER_CONTENT"
seed_config "iot_server" "visual_device" "$RB_VISUAL_DEVICE_CONTENT"
seed_config "iot_server" "system_topic"  "$RB_SYSTEM_TOPIC_CONTENT"

# ---------- 组 3：log_server（rblogserver） ----------
echo
echo "=== 组 3：log_server（rblogserver）==="
seed_config "log_server" "run.yaml"  "$RBLOG_RUN_YAML_CONTENT"

# ---------- 回读验证 ----------
echo
echo "=== 回读验证 ==="
verify_group() {
    local group="$1"
    shift
    for dataId in "$@"; do
        content=$(curl -sf "http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs?dataId=${dataId}&group=${group}")
        if [[ -n "$content" ]]; then
            echo "✅ GET dataId=${dataId}（${group}）: $(echo "$content" | head -1) ..."
        else
            echo "❌ GET dataId=${dataId}（${group}）为空" >&2
            exit 1
        fi
    done
}
verify_group "iot_data_server" mongo forward database mqtt_forward
verify_group "iot_server" database device_acl device_api emqx grpc https server session worker visual_device system_topic
verify_group "log_server" run.yaml

echo
echo "=== 数据库层确认（openGauss config_info）==="
docker exec opengauss su - omm -c "gsql -d nacos_config -c \"SELECT data_id, group_id FROM config_info ORDER BY group_id, data_id;\"" 2>/dev/null || \
    echo "（gsql 查询失败，以 API 回读为准）"

echo
echo "🎉 播种完成。rbIotDataserver（iot_data_server）+ rbiotserver（iot_server）+ rblogserver（log_server）均可走 Nacos 配置链"
