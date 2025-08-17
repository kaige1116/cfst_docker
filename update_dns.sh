#!/bin/bash

# 定义输出路径（与Docker挂载路径对应）
LOG_PATH="/var/log/cfst_update.log"  # 对应本地logs目录
RESULTS_PATH="/app/results"          # 对应本地results目录（已挂载）
TOP_IPS_FILE="${RESULTS_PATH}/top_ips.txt"
RESULT_FILE="${RESULTS_PATH}/result.txt"

# 确保结果目录存在
mkdir -p "$RESULTS_PATH" || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误：无法创建结果目录 $RESULTS_PATH" >&2; exit 1; }

# 日志函数：允许日志写入失败但不终止主流程
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  # 日志写入失败时仅输出错误到stderr，不终止脚本
  echo "$msg" >> "$LOG_PATH" 2>/dev/null || echo "$msg (警告：日志写入失败)" >&2
}

# 检查依赖工具是否存在
check_dependencies() {
  local dependencies=("jq" "curl")
  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      log "错误：依赖工具 $dep 未安装，请先安装"
      exit 1
    fi
  done
}

# 检查必填环境变量
check_env_vars() {
  local required_vars=("CF_API_TOKEN" "CF_ZONE_ID" "CF_DOMAIN")
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      log "错误：必填环境变量 $var 未设置"
      exit 1
    fi
  done
}

# 执行测速并检查结果
run_speed_test() {
  log "开始执行Cloudflare IP测速..."
  # 从环境变量获取测速参数（默认使用ip.txt）
  local cfst_params="${CFST_PARAMS:--f ip.txt -p 443 -t 10}"
  /app/cfst $cfst_params -o "$RESULT_FILE"
  
  # 检查测速是否成功（结果文件存在且非空）
  if [ $? -ne 0 ] || [ ! -s "$RESULT_FILE" ]; then
    log "错误：测速失败或结果为空（文件：$RESULT_FILE）"
    exit 1
  fi
  log "测速结果已保存到：$RESULT_FILE"
}

# 提取最优IP并检查有效性
extract_top_ips() {
  log "获取前${IP_COUNT:-6}个最优IP..."
  local ip_count="${IP_COUNT:-6}"
  
  # 从结果文件提取前N个IP（跳过首行标题）
  head -n $((ip_count + 1)) "$RESULT_FILE" | tail -n $ip_count | awk -F, '{print $1}' > "$TOP_IPS_FILE"
  
  # 检查最优IP列表是否有效
  if [ ! -s "$TOP_IPS_FILE" ]; then
    log "错误：无法提取有效IP，最优IP列表为空（文件：$TOP_IPS_FILE）"
    exit 1
  fi
  
  log "本次优选IP列表已保存到：$TOP_IPS_FILE"
  log "本次优选IP列表："
  cat "$TOP_IPS_FILE" | while read ip; do log "  - $ip"; done
}

# 判断IP类型（IPv4/IPv6）
get_ip_type() {
  local ip="$1"
  # IPv4格式校验（简单匹配，不严格校验）
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "A"
  # IPv6格式校验（简单匹配，不严格校验）
  elif [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
    echo "AAAA"
  else
    echo "invalid"
  fi
}

# 调用Cloudflare API更新DNS记录（带重试机制）
update_dns() {
  local ip_index=$1
  local ip_address=$2
  local record_name="ip${ip_index}.${CF_DOMAIN}"
  
  # 检查IP有效性
  local record_type=$(get_ip_type "$ip_address")
  if [ "$record_type" = "invalid" ]; then
    log "警告：IP $ip_address 格式无效，跳过更新"
    return 1
  fi
  
  log "开始更新 ${record_name}（类型：${record_type}）→ ${ip_address}"

  # 查询现有记录（最多重试3次）
  local retry=3
  local RECORD_RESPONSE
  for ((i=1; i<=retry; i++)); do
    RECORD_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${record_name}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --ssl-reqd)  # 强制验证SSL证书
    
    # 检查curl是否成功（0为成功）
    if [ $? -eq 0 ]; then
      break
    fi
    log "查询记录失败，重试第 $i 次（共 $retry 次）"
    sleep 2
  done
  
  # 若多次重试后仍失败，终止流程
  if [ $? -ne 0 ]; then
    log "错误：查询DNS记录失败，无法继续更新 ${record_name}"
    return 1
  fi
  
  # 解析记录ID（处理jq解析失败的情况）
  local RECORD_ID
  RECORD_ID=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].id')
  if [ $? -ne 0 ]; then
    log "错误：解析DNS记录ID失败，响应：$RECORD_RESPONSE"
    return 1
  fi
  
  # 构建更新/创建请求数据
  local request_data=$(jq -n \
    --arg type "$record_type" \
    --arg name "$record_name" \
    --arg content "$ip_address" \
    '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
  
  # 更新或创建记录（最多重试3次）
  local RESPONSE
  for ((i=1; i<=retry; i++)); do
    if [ "$RECORD_ID" != "null" ] && [ -n "$RECORD_ID" ]; then
      # 更新现有记录
      RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        --ssl-reqd)
    else
      # 创建新记录
      RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        --ssl-reqd)
    fi
    
    # 检查curl是否成功
    if [ $? -eq 0 ]; then
      break
    fi
    log "更新记录失败，重试第 $i 次（共 $retry 次）"
    sleep 2
  done
  
  # 检查API响应是否成功
  if [ $? -ne 0 ]; then
    log "错误：API请求失败，无法更新 ${record_name}"
    return 1
  fi
  
  if echo "$RESPONSE" | jq -r '.success' | grep -q "true"; then
    log "${record_name} 更新成功"
    return 0
  else
    log "${record_name} 更新失败！响应: ${RESPONSE}"
    return 1
  fi
}

# 主流程
main() {
  # 前置检查：依赖和环境变量
  check_dependencies
  check_env_vars
  
  # 执行测速和IP提取
  run_speed_test
  extract_top_ips
  
  # 批量更新IP（允许部分失败，不终止整体流程）
  local index=1
  local total_success=0
  local total_failed=0
  
  while IFS= read -r ip; do
    if [ -n "$ip" ]; then
      if update_dns "$index" "$ip"; then
        total_success=$((total_success + 1))
      else
        total_failed=$((total_failed + 1))
      fi
      index=$((index + 1))
    else
      log "跳过空IP记录"
    fi
  done < "$TOP_IPS_FILE"
  
  # 输出最终统计结果
  log "DNS更新完成 - 成功: $total_success, 失败: $total_failed"
  if [ $total_failed -gt 0 ]; then
    log "警告：部分IP更新失败，请检查日志排查问题"
    exit 1  # 整体返回失败（可选，根据需求调整）
  fi
}

# 启动主流程
main