# CFST Docker: Cloudflare IP 测速与 DNS 自动更新工具

一个基于 Docker 的 Cloudflare IP 测速与 DNS 记录自动更新解决方案，帮助你自动筛选最优 Cloudflare IP 并更新到 Cloudflare DNS，提升网络访问速度。

## 功能特点

- 自动测速 Cloudflare IP 地址（支持 IPv4 和 IPv6）
- 定期筛选最优 IP 并自动更新到 Cloudflare DNS
- 支持自定义测速参数和更新频率
- 多架构支持（amd64/arm64）
- 完整的日志记录和结果保存
- 集成 CloudflareSpeedTest 工具自动更新机制

## 前置要求

- Docker 和 Docker Compose 环境
- Cloudflare 账号及以下信息：
  - API Token（需要 DNS 编辑权限）
  - Zone ID（域名区域 ID）
  - 已在 Cloudflare 托管的域名

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/你的用户名/cfst_docker.git
cd cfst_docker
```

### 2. 配置环境

编辑 `docker-compose.yml` 文件，替换以下参数：

```yaml

services:
  cfst:
    image: ghcr.io/kaige1116/cfst_docker:latest
    restart: always
    environment:
      - CF_API_TOKEN=your_cloudflare_api_token
      - CF_ZONE_ID=your_cloudflare_zone_id
      - CF_DOMAIN=your_domain.com
      - CFST_PARAMS=-f /app/ip.txt -p 443 -t 10 -tl 200
      - IP_COUNT=6
      - UPDATE_INTERVAL=6h
    volumes:
      - ./logs:/var/log
      - ./results:/app/results
```

## 配置文件说明：
  - CF_API_TOKEN=your_cloudflare_api_token  # 你的Cloudflare API令牌
  - CF_ZONE_ID=your_cloudflare_zone_id      # 你的域名Zone ID
  - CF_DOMAIN=your_domain.com               # 你的域名
  - CFST_PARAMS=-f /app/ip.txt -p 443 -t 10 -tl 200  # 测速参数（ip.txt可改为ipv6.txt启用IPv6测速）
  - IP_COUNT=6                               # 保留的最优IP数量
  - UPDATE_INTERVAL=6h                       # 更新间隔（支持d天/h小时，如7d、12h）

### 3. 启动服务

```bash
docker-compose up -d
```

## 配置说明

### 核心参数说明

| 参数名           | 说明                                                                 | 默认值                  |
|------------------|----------------------------------------------------------------------|-------------------------|
| CF_API_TOKEN     | Cloudflare API 令牌（需包含DNS编辑权限）                             | 无（必须设置）          |
| CF_ZONE_ID       | Cloudflare 域名对应的 Zone ID                                        | 无（必须设置）          |
| CF_DOMAIN        | 需要更新DNS的域名（如example.com）                                   | 无（必须设置）          |
| CFST_PARAMS      | CloudflareSpeedTest 测速参数                                         | -f ip.txt -p 443 -t 10  |
| IP_COUNT         | 保留的最优IP数量（会生成ip1到ipN的子域名）                           | 6                       |
| UPDATE_INTERVAL  | 自动更新间隔（格式：数字+d/h，如7d表示7天，6h表示6小时）             | 7d                      |

### 测速参数说明

`CFST_PARAMS` 支持的主要参数：

- `-f 文件`：指定IP列表文件（ip.txt为IPv4，ipv6.txt为IPv6）
- `-p 端口`：指定测速端口（默认443）
- `-t 超时时间`：指定超时时间（秒）
- `-tl 延迟上限`：指定延迟上限（毫秒）
- `-sl 速度下限`：指定下载速度下限（MB/s）

示例：`-f ipv6.txt -p 443 -t 10 -tl 200 -sl 1` 表示使用IPv6列表，测试443端口，超时10秒，延迟上限200ms，下载速度至少1MB/s。

## 目录结构说明

```
cfst_docker/
├── docker-compose.yml       # Docker Compose配置文件
├── start.sh                 # 容器启动脚本（处理定时任务）
├── update_dns.sh            # DNS更新脚本
├── cfst_linux_amd64/        # amd64架构的CloudflareSpeedTest工具
│   ├── cfst                 # 测速工具主程序
│   ├── cfst_hosts.sh        # Hosts自动更新脚本
│   ├── ip.txt               # IPv4地址列表
│   ├── ipv6.txt             # IPv6地址列表
│   ├── 使用+错误+反馈说明.txt # 使用说明文档
│   └── VERSION              # 工具版本信息
├── cfst_linux_arm64/        # arm64架构的CloudflareSpeedTest工具
│   └── ...                  # 包含与amd64目录相同的文件
├── logs/                    # 日志目录（自动生成）
├── results/                 # 测速结果目录（自动生成）
└── .github/workflows/       # GitHub Actions工作流配置
    ├── build.yml            # 多架构Docker镜像构建推送工作流
    └── auto-update-cfst.yml # CloudflareSpeedTest自动更新工作流
```

## 日志与结果查看

- 测速与更新日志：`logs/cfst_update.log`
- 最新测速结果：`results/result.txt`
- 最优IP列表：`results/top_ips.txt`

## 手动执行更新

```bash
# 进入容器
docker exec -it cfst_docker_cfst_1 /bin/sh

# 手动执行更新
/app/update_dns.sh
```

## 自动更新机制

项目包含两个GitHub Actions工作流，实现自动化维护：

1. **CloudflareSpeedTest自动更新**：
   - 每日凌晨零点自动检查更新
   - 支持amd64和arm64两种架构
   - 自动下载最新版本最新版本并提交到代码仓库

2. **多架构Docker镜像构建**：
   - 推送代码到main分支时自动触发
   - 构建建并推送amd64和arm64架构镜像
   - 镜像同时到GitHub Container Registry

## 常见问题

1. **Q: 如何切换IPv4/IPv6测速？**  
   A: 修改`CFST_PARAMS`中的`-f`参数，`-f ip.txt`为IPv4，`-f ipv6.txt`为IPv6。

2. **Q: 测速结果始终为空？**  
   A: 检查是否使用了代理（会影响测速结果），尝试关闭代理后重新测试。

3. **Q: DNS更新失败？**  
   A: 检查API令牌权限是否正确，Zone ID和域名是否匹配，网络是否通畅。

4. **Q: 如何修改测速的IP列表？**  
   A: 可以直接编辑对应架构目录下的`ip.txt`或`ipv6.txt`文件添加自定义IP段。

5. **Q: 如何使用Hosts自动更新功能？**  
   A: 可使用`cfst_hosts.sh`脚本，首次运行需按提示配置初始IP，脚本会自动替换系统Hosts中的Cloudflare IP。

## 开源协议

本项目基于MIT协议开源，CloudflareSpeedTest工具的版权归原作者所有。

## 致谢

本项目基于 [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 开发，感谢原作者的优秀工作。