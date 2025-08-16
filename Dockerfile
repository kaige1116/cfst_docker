FROM alpine:latest

# 安装时区数据并设置时区
RUN apk add --no-cache tzdata
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

# 安装必要依赖
RUN apk add --no-cache bash curl jq

# 复制项目文件
COPY cfst_linux_amd64/ /app/

# 添加自动更新脚本
COPY update_dns.sh /app/
RUN chmod +x /app/cfst /app/cfst_hosts.sh /app/update_dns.sh

# 设置定时任务
RUN echo "0 0 */7 * * /app/update_dns.sh >> /var/log/cfst_update.log 2>&1" > /etc/crontabs/root

# 启动时执行一次更新并启动 cron
CMD /app/update_dns.sh && crond -f