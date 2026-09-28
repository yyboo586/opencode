# 本地 Mock 服务（test-env 资源）

> 2026-09-22 从 `platform/local/mock/` 迁入。`platform/local/` 的全量 compose 仍构建同名容器（构建路径见其 `build.sh`）。
> 用途：替代服务本地联调时缺失的真实依赖，由 `scripts/mock.sh` 部署为固定名容器（host 网络）。

| 目录 | 端口 | 替代的真实服务 | 行为 |
|------|------|----------------|------|
| `endpoint/` | 9096 gRPC | rbendpoint（无源码，镜像非最新） | 实现 `rb.rbIotEndPoint.endPointProto.EndPointProvider/RbIotMessage`，返回 `{code:200}`，打印 `type/topic/payload_bytes` |
| `http/` | 9999 HTTP | rbDockerUpgrade（DU）+ 远端 IoT | `/device/serial`、`/server/ready`、`/api/device/license`、`/api/device/alert`、`/api/query/visualdevice`、`/ping` |
| `device-sim/` | — | 设备（DEV） | 按间隔上报 `v1/gateway/{device}/data` 并订阅 `attributes`+`rpc` 打印指令；`-device`/`-devices`/`-mode`/`-interval`/`-count`/`-broker` 可配 |

## 部署

```bash
bash ~/.config/opencode/skills/test-env/scripts/mock.sh up            # endpoint(9096) + http(9999)
bash ~/.config/opencode/skills/test-env/scripts/mock.sh up device-sim # 设备模拟器（连 EMQX，需先起 emqx.sh）
bash ~/.config/opencode/skills/test-env/scripts/mock.sh up --force    # 源码改动后重建容器
bash ~/.config/opencode/skills/test-env/scripts/mock.sh status / down
```

宿主需要 Go 工具链（在 `assets/mock/bin/` 静态编译，容器只挂二进制，无需 Dockerfile）。与 `platform/local/` compose 的 `local-mock-*` 容器端口互斥，勿同时运行。

## 维护

- `endpoint/pb/` 两个文件拷自 `rbEdgeServer/endPointClient/`（proto 生成物，勿手改；proto 变更时重新拷贝）。
- 单测：各目录下 `go test ./...`。
