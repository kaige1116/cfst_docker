#!/bin/bash
set -e

# 函数：将 UPDATE_INTERVAL（如 7d、12h）转换为 cron 表达式
interval_to_cron() {
  local interval=$1
  local default_interval="7d"  # 默认7天
  local cron_expr=""

  # 处理空值，使用默认值
  if [ -z "$interval" ]; then
    interval=$default_interval
  fi

  # 解析时间单位（d=天，h=小时）
  local num=${interval%[dh]}
  local unit=${interval: -1}

  # 校验格式（数字+单位，单位只能是d或h，数字必须为正整数）
  if ! [[ $num =~ ^[1-9][0-9]*$ ]] || [[ ! $unit =~ ^[dh]$ ]]; then
    echo "警告：无效的 UPDATE_INTERVAL 格式 '$interval'，使用默认值 $default_interval"
    interval=$default_interval
    num=${interval%[dh]}
    unit=${interval: -1}
  fi

  # 转换为 cron 表达式（确保生成有效表达式）
  case $unit in
    d)  # 每天/每n天：0点执行（n≥1）
      if [ $num -eq 1 ]; then
        cron_expr="0 0 * * *"  # 每天0点
      else
        cron_expr="0 0 */$num * *"  # 每n天0点（n≥2）
      fi
      ;;
    h)  # 每n小时：整点执行（n≥1）
      cron_expr="0 */$num * * *"  # 每n小时（n≥1，cron支持*/1=每小时）
      ;;
  esac

  echo "$cron_expr"
}

# 1. 解析环境变量生成 cron 表达式
CRON_EXPR=$(interval_to_cron "$UPDATE_INTERVAL")
echo "生成的定时任务表达式：$CRON_EXPR"

# 2. 生成 crontab 配置（执行 update_dns.sh 并输出日志）
echo "$CRON_EXPR /app/update_dns.sh >> /var/log/cfst_update.log 2>&1" > /etc/crontabs/root

# 3. 首次启动执行一次更新（失败不影响后续）
echo "首次执行更新任务..."
/app/update_dns.sh || true

# 4. 启动 cron 服务（前台运行，保持容器存活）
echo "启动定时任务服务..."
crond -f