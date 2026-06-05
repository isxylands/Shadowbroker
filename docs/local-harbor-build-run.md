# 本地镜像打包与启动说明

本文说明如何使用本项目的 Harbor 本地打包脚本构建镜像、启动应用，以及把已经构建好的镜像放到其它机器上运行。

## 一、构建环境要求

构建机器需要：

- Docker Engine 或 Docker Desktop
- `docker compose` 或 `docker-compose`
- Linux/macOS/WSL 使用 `bash`
- Windows 使用 PowerShell
- 首次构建需要能访问基础镜像和依赖源，例如 Docker Hub/镜像代理、Debian apt、NodeSource、npm、Python 包源、crates.io、Playwright CDN

后端镜像构建较重，建议至少：

- 8GB 内存，16GB 更稳
- 20GB 以上可用磁盘

## 二、本地构建镜像

Linux/macOS/WSL：

```bash
cd /opt/shadowbroker-build-2069af1
chmod +x scripts/build-harbor-images.sh
./scripts/build-harbor-images.sh
```

Windows PowerShell：

```powershell
cd D:\workspace\codex\Shadowbroker
powershell -ExecutionPolicy Bypass -File scripts\build-harbor-images.ps1
```

脚本会自动生成：

```text
短sha-yyyyMMdd-HHmmss
```

并构建两个镜像：

```text
harbor.trscd.com.cn/baseapp/bigbodycobain-shadowbroker:backend-短sha-yyyyMMdd-HHmmss
harbor.trscd.com.cn/baseapp/bigbodycobain-shadowbroker:frontend-短sha-yyyyMMdd-HHmmss
```

脚本还会自动写出 `.env.harbor`：

```env
SHADOWBROKER_IMAGE_REPOSITORY=harbor.trscd.com.cn/baseapp/bigbodycobain-shadowbroker
SHADOWBROKER_IMAGE_TAG=短sha-yyyyMMdd-HHmmss
```

后续启动、推送、导出镜像时都应使用这个 `.env.harbor`，确保使用的是刚构建出来的 tag。

## 三、启动应用

在构建目录下执行：

```bash
docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml up -d
```

如果当前机器使用的是 Docker Compose v2 插件，也可以写成：

```bash
docker compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml up -d
```

默认只绑定本机回环地址：

```text
http://127.0.0.1:3000
```

如果要让局域网其它机器访问：

```bash
BIND=0.0.0.0 docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml up -d
```

然后访问：

```text
http://服务器IP:3000
```

查看状态：

```bash
docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml ps
```

查看日志：

```bash
docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml logs -f
```

停止：

```bash
docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml down
```

## 四、推送到 Harbor 后在其它机器运行

构建并推送：

```bash
./scripts/build-harbor-images.sh --push
```

其它机器只需要准备这些文件：

```text
docker-compose.yml
docker-compose.harbor.yml
.env.harbor
.env                # 可选，放端口、API key、功能开关等本地配置
```

然后在目标机器上拉取并启动：

```bash
docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml pull
docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml up -d
```

目标机器需要能访问：

```text
harbor.trscd.com.cn
```

如果 Harbor 需要登录，先执行：

```bash
docker login harbor.trscd.com.cn
```

## 五、不推 Harbor，离线拷贝到其它机器运行

在构建机器上读取 `.env.harbor` 中的 tag：

```bash
source .env.harbor
echo "$SHADOWBROKER_IMAGE_TAG"
```

导出两个镜像：

```bash
docker save -o shadowbroker-images-${SHADOWBROKER_IMAGE_TAG}.tar \
  ${SHADOWBROKER_IMAGE_REPOSITORY}:backend-${SHADOWBROKER_IMAGE_TAG} \
  ${SHADOWBROKER_IMAGE_REPOSITORY}:frontend-${SHADOWBROKER_IMAGE_TAG}
```

把以下文件复制到目标机器：

```text
shadowbroker-images-短sha-yyyyMMdd-HHmmss.tar
docker-compose.yml
docker-compose.harbor.yml
.env.harbor
.env                # 可选
```

目标机器导入镜像：

```bash
docker load -i shadowbroker-images-短sha-yyyyMMdd-HHmmss.tar
```

启动：

```bash
docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml up -d
```

## 六、目标机器只运行时需要哪些文件

如果目标机器只负责运行，不在目标机器上重新构建镜像，那么不需要完整源码。

最小文件集：

```text
docker-compose.yml
docker-compose.harbor.yml
.env.harbor
```

可选文件：

```text
.env
```

`.env` 用于配置端口、绑定地址、API key、功能开关等，例如：

```env
BIND=0.0.0.0
FRONTEND_PORT=3000
BACKEND_PORT=8000
ADMIN_KEY=change-me
NEWS_ENABLED=true
FINANCIAL_ENABLED=false
```

还需要二选一：

```text
方式一：目标机器能从 Harbor pull 到 .env.harbor 指定的两个镜像
方式二：目标机器已经通过 docker load 导入了这两个镜像
```

## 七、目标机器也要重新构建时需要哪些文件

如果目标机器也要执行本地构建，则需要完整源码目录，包括：

```text
backend/
frontend/
privacy-core/
pyproject.toml
uv.lock
docker-compose.yml
docker-compose.harbor.yml
scripts/build-harbor-images.sh
```

然后执行：

```bash
./scripts/build-harbor-images.sh
```

## 八、缓存说明

首次构建会下载基础镜像和大量依赖。后续在同一台机器上再次构建时，Docker 会复用缓存层，通常不需要全部重新下载。

缓存主要保存在 Docker 数据目录中，而不是源码目录中。例如当前远端机器的 Docker 数据目录是：

```text
/TRS/lib/docker
```

如果执行过以下命令，缓存可能被清理，下次构建会重新下载：

```bash
docker builder prune
docker system prune
docker image prune
```

## 九、常见问题

### 启动时找不到镜像

检查 `.env.harbor` 中的 tag 是否和本机已有镜像一致：

```bash
cat .env.harbor
docker images | grep bigbodycobain-shadowbroker
```

### 修改端口

在 `.env` 中配置：

```env
FRONTEND_PORT=3000
BACKEND_PORT=8000
```

### 局域网访问

启动时设置：

```bash
BIND=0.0.0.0 docker-compose --env-file .env.harbor -f docker-compose.yml -f docker-compose.harbor.yml up -d
```

### 只想看脚本会生成什么 tag

Linux/macOS/WSL：

```bash
./scripts/build-harbor-images.sh --print-only
```

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-harbor-images.ps1 -PrintOnly
```

注意：`--print-only` 也会写出 `.env.harbor`，用于预览当前 tag。
