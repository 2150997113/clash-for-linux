#!/usr/bin/env bash
# =========================
# Clash for Linux - 订阅更新脚本
# =========================
set -euo pipefail

# 获取项目根目录
Server_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# =========================
# 加载 .env
# =========================
ENV_FILE=""

# 1) 手动指定
if [ -n "${CLASH_ENV:-}" ] && [ -f "$CLASH_ENV" ]; then
  ENV_FILE="$CLASH_ENV"
# 2) 脚本所在目录
elif [ -f "$Server_Dir/.env" ]; then
  ENV_FILE="$Server_Dir/.env"
# 3) 标准安装目录
elif [ -f "/opt/clash-for-linux/.env" ]; then
  ENV_FILE="/opt/clash-for-linux/.env"
fi

if [ -z "$ENV_FILE" ]; then
  echo -e "\033[31m[ERROR]\033[0m 未找到 .env 文件"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$Server_Dir/scripts/lib/output.sh"
output_init

# shellcheck disable=SC1090
source "$Server_Dir/scripts/lib/config-check.sh"

# shellcheck disable=SC1090
source "$Server_Dir/scripts/lib/port-check.sh"

# =========================
# 变量设置
# =========================
Conf_Dir="$Server_Dir/conf"
Temp_Dir="$Server_Dir/temp"
Log_Dir="$Server_Dir/logs"

mkdir -p "$Conf_Dir" "$Temp_Dir" "$Log_Dir"

URL="${CLASH_URL:?Error: CLASH_URL variable is not set or empty}"

# Secret 处理
Secret="${CLASH_SECRET:-}"
[ -z "$Secret" ] && [ -f "$Conf_Dir/config.yaml" ] && \
  Secret="$(awk -F': ' '/^secret:/{print $2; exit}' "$Conf_Dir/config.yaml" 2>/dev/null || true)"
[ -z "$Secret" ] && Secret="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export Secret

# 端口默认值
CLASH_HTTP_PORT="${CLASH_HTTP_PORT:-7890}"
CLASH_SOCKS_PORT="${CLASH_SOCKS_PORT:-7891}"
CLASH_REDIR_PORT="${CLASH_REDIR_PORT:-7892}"
CLASH_LISTEN_IP="${CLASH_LISTEN_IP:-0.0.0.0}"
CLASH_ALLOW_LAN="${CLASH_ALLOW_LAN:-false}"
EXTERNAL_CONTROLLER_ENABLED="${EXTERNAL_CONTROLLER_ENABLED:-true}"
EXTERNAL_CONTROLLER="${EXTERNAL_CONTROLLER:-127.0.0.1:9090}"
ALLOW_INSECURE_TLS="${ALLOW_INSECURE_TLS:-false}"
CLASH_HEADERS="${CLASH_HEADERS:-}"

# 端口解析
CLASH_HTTP_PORT="$(resolve_port_value "HTTP" "$CLASH_HTTP_PORT")"
CLASH_SOCKS_PORT="$(resolve_port_value "SOCKS" "$CLASH_SOCKS_PORT")"
CLASH_REDIR_PORT="$(resolve_port_value "REDIR" "$CLASH_REDIR_PORT")"
EXTERNAL_CONTROLLER="$(resolve_host_port "External Controller" "$EXTERNAL_CONTROLLER" "0.0.0.0")"

# =========================
# 函数定义
# =========================
download_config() {
  local url="$1" output="$2"
  local rc=0

  # curl
  local curl_cmd=(curl -L -sS --retry 3 -m 30 -o "$output")
  [ "${ALLOW_INSECURE_TLS}" = "true" ] && curl_cmd+=(-k)
  [ -n "${CLASH_HEADERS}" ] && curl_cmd+=(-H "$CLASH_HEADERS")
  curl_cmd+=("$url")

  set +e
  "${curl_cmd[@]}" 2>/dev/null
  rc=$?
  set -e

  # wget fallback
  if [ $rc -ne 0 ]; then
    local wget_cmd=(wget -q -O "$output")
    [ "${ALLOW_INSECURE_TLS}" = "true" ] && wget_cmd+=(--no-check-certificate)
    [ -n "${CLASH_HEADERS}" ] && wget_cmd+=(--header="$CLASH_HEADERS")
    wget_cmd+=("$url")

    for _ in {1..3}; do
      set +e
      "${wget_cmd[@]}" 2>/dev/null && rc=0 && break
      set -e
    done
  fi

  return $rc
}

# =========================
# 任务执行
# =========================
# 取消代理环境变量
unset http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY || true

# 检测订阅地址
info "检测订阅地址..."

local check_cmd=(curl -o /dev/null -L -sS --retry 3 -m 10 -w "%{http_code}")
[ "${ALLOW_INSECURE_TLS}" = "true" ] && check_cmd+=(-k) && \
  warn "已启用不安全的 TLS 下载（跳过证书校验）"
[ -n "${CLASH_HEADERS}" ] && check_cmd+=(-H "$CLASH_HEADERS")
check_cmd+=("$URL")

set +e
status_code="$("${check_cmd[@]}" 2>/dev/null)"
local check_rc=$?
set -e

if [ $check_rc -ne 0 ] || ! echo "$status_code" | grep -qE '^[23][0-9]{2}$'; then
  err "Clash订阅地址不可访问！(http_code=${status_code:-unknown})"
  exit 1
fi
ok "Clash订阅地址可访问！"

# 下载配置
info "下载配置文件..."

if ! download_config "$URL" "$Temp_Dir/clash.yaml"; then
  err "配置文件下载失败！"
  exit 1
fi
ok "配置文件下载成功！"

# 校验配置内容
if ! grep -Eq '^(proxies:|proxy-groups:|rules:|mixed-port:|port:)' "$Temp_Dir/clash.yaml"; then
  err "下载内容不像 Clash 配置（缺少关键字段）"
  echo "可执行：head -n 20 $Temp_Dir/clash.yaml 查看内容"
  exit 1
fi

cp -a "$Temp_Dir/clash.yaml" "$Temp_Dir/clash_config.yaml"

# subconverter
# shellcheck disable=SC1090
source "$Server_Dir/scripts/lib/subconverter-resolve.sh"

if [ "${Subconverter_Ready:-false}" = "true" ]; then
  info "判断订阅内容是否符合 Clash 配置标准..."
  export SUBCONVERTER_BIN="$Subconverter_Bin"
  bash "$Server_Dir/scripts/lib/profile-convert.sh"
  sleep 1
else
  warn "未检测到可用的 subconverter，跳过订阅转换"
fi

# 生成 config.yaml
if is_full_clash_config "$Temp_Dir/clash_config.yaml"; then
  info "检测到全量配置模式，直接使用订阅"
  cp -a "$Temp_Dir/clash_config.yaml" "$Temp_Dir/config.yaml"
else
  info "检测到节点/片段模式，使用模板合并"
  if [ ! -f "$Temp_Dir/templete_config.yaml" ]; then
    err "未找到模板文件：$Temp_Dir/templete_config.yaml"
    exit 1
  fi
  sed -n '/^proxies:/,$p' "$Temp_Dir/clash_config.yaml" > "$Temp_Dir/proxy.txt"
  cat "$Temp_Dir/templete_config.yaml" > "$Temp_Dir/config.yaml"
  cat "$Temp_Dir/proxy.txt" >> "$Temp_Dir/config.yaml"
fi

# 替换占位符
sed -i "s/CLASH_HTTP_PORT_PLACEHOLDER/${CLASH_HTTP_PORT}/g" "$Temp_Dir/config.yaml"
sed -i "s/CLASH_SOCKS_PORT_PLACEHOLDER/${CLASH_SOCKS_PORT}/g" "$Temp_Dir/config.yaml"
sed -i "s/CLASH_REDIR_PORT_PLACEHOLDER/${CLASH_REDIR_PORT}/g" "$Temp_Dir/config.yaml"
sed -i "s/CLASH_LISTEN_IP_PLACEHOLDER/${CLASH_LISTEN_IP}/g" "$Temp_Dir/config.yaml"
sed -i "s/CLASH_ALLOW_LAN_PLACEHOLDER/${CLASH_ALLOW_LAN}/g" "$Temp_Dir/config.yaml"

# external-controller
if [ "$EXTERNAL_CONTROLLER_ENABLED" = "true" ]; then
  upsert_yaml_kv "$Temp_Dir/config.yaml" "external-controller" "$EXTERNAL_CONTROLLER"
else
  sed -i "s@^external-controller:.*@# external-controller: disabled@g" "$Temp_Dir/config.yaml" 2>/dev/null || true
fi

# 应用 TUN 和 Mixin 配置
apply_tun_config "$Temp_Dir/config.yaml"
apply_mixin_config "$Temp_Dir/config.yaml" "$Server_Dir"

# 检查配置非空
if [ ! -s "$Temp_Dir/config.yaml" ]; then
  err "生成的配置为空，中止写入以保护现有配置"
  exit 1
fi

# 写入最终配置
cp "$Temp_Dir/config.yaml" "$Conf_Dir/config.yaml"

# Dashboard
if [ "$EXTERNAL_CONTROLLER_ENABLED" = "true" ]; then
  local dashboard_dir="$Server_Dir/dashboard/public"
  [ -d "$dashboard_dir" ] && upsert_yaml_kv "$Conf_Dir/config.yaml" "external-ui" "$dashboard_dir"
fi

# 写入 secret
force_write_secret "$Conf_Dir/config.yaml"

ok "订阅更新完成"
echo ""
echo "如需生效请执行: make restart 或 bash scripts/cmd/service-restart.sh"
echo ""
