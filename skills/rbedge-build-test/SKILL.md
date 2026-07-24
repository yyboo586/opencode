---
name: rbedge-build-test
description: rbEdgeServer 构建与测试流程. Use when building the project image (make lint / make test / bash build.sh) or running tests (make test).
---

# rbEdgeServer 构建与测试流程

本 skill 是 rbEdgeServer 的**项目领域知识**：构建或测试时按此处流程执行。
原则性约束（文件组织、新包条件、OpenSpec 工作流）见 `CLAUDE.md`，不在此重复。

## When to Activate

- 出服务镜像（构建 + lint + 跑测试 → .tar 镜像包）
- 单独跑测试（开发期改动验证）
- 编写或修改测试（尤其是 `storage/` 包及其 `executor/` 子包）

## 服务构建

按顺序执行四步，前一步失败即停（不进镜像构建 / 不导出 tar）：

```bash
make lint        # 静态检查 (golangci-lint, 仅 storage 包)
make test        # 测试 (go test ./storage/..., 需 openGauss)
bash build.sh    # 交叉编译 + 打 docker 镜像
docker save rbedgeserver:v<version>_<arch> -o rbedgeserver_v<version>_<arch>.tar   # build.sh 成功后自动导出部署 tar 包
```

> build.sh 末尾会打印确切的 `docker save` 命令（含已提取的版本号 / 架构），直接执行该行即可，无需手填 version/arch。本地验证构建（amd64）可跳过此步。

**环境要求**
- Go 1.22.12（见 `go.mod`）
- Docker
- 三个本地 replace 包在位（`../tsl` / `../visualdevice` / `../log`）

**`build.sh` 关键约定**
- 默认 `ARCH=arm64`（aarch64，信创环境部署目标）
- 切回原生 amd64：`ARCH=amd64 bash build.sh`
- 版本号**自动提取**自 `data/version.go`（单一事实源，避免双源漂移）→ image tag 形如 `v<version>_<arch>`
- 产物命名一律用下划线分隔（`rbEdgeServer_<arch>` / `v<version>_<arch>`）
- x86 host 上构建 arm64 时自动注册 QEMU/binfmt 跨架构模拟（会比原生慢一个数量级）
- `CGO_ENABLED=0` 静态链接，`-trimpath -ldflags "-s -w"`
- 本地包缺失 / 非 Go 仓库 / 版本号提取失败等前置检查会 `exit 1`

**产物**
- Go 二进制：`bin/rbEdgeServer_<arch>`
- Docker 镜像：`rbedgeserver:v<version>_<arch>`（例如 `v1.4.6_arm64`）
- 部署 tar 包（"镜像包"，构建后自动导出）：`rbedgeserver_v<version>_<arch>.tar`
- 部署机：`docker load -i rbedgeserver_v<version>_<arch>.tar`

## 执行测试

```bash
make test -v        # = go test -v ./storage/...
```

- `make test` 只覆盖 `./storage/...`。其他包（`visualdevice`/`license`/`exhook` 等）是历史代码：init 时硬读 `configs/config.yml`、绑 udp:123 等，未做测试治理；需要时单独 `go test ./xxx/...`，不纳入 `make test`。
