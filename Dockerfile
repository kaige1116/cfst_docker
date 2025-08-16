FROM alpine:latest

# 安装时区数据并设置时区
RUN apk add --no-cache tzdata
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

# 安装必要依赖
RUN apk add --no-cache bash curl jq

# 初始化日志目录
RUN mkdir -p /var/log

# 根据构建架构复制对应目录（适配 amd64/arm64）
ARG TARGETARCH
COPY cfst_linux_${TARGETARCH}/ /app/

# 添加自动更新脚本和启动脚本
COPY update_dns.sh /app/
COPY start.sh /app/  # 新增启动脚本
RUN chmod +x /app/cfst /app/cfst_hosts.sh /app/update_dns.sh /app/start.sh  # 授权启动脚本

# 入口命令改为执行启动脚本
CMD ["/app/start.sh"]