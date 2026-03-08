#!/bin/bash
set -euo pipefail

# =========================
# Clash for Linux - 安装脚本
# =========================

# 获取项目根目录
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_DIR="$SERVER_DIR"
SERVICE_NAME="clash-for-linux"
SERVICE_USER="root"
SERVICE_GROUP="root"

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/lib/output.sh"
output_init "$@"

# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/lib/env-utils.sh"

# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/lib/systemd-utils.sh"

# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/lib/cpu-arch.sh"

# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/lib/clash-resolve.sh"

# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/lib/port-check.sh"

# =========================
# 前置校验
# =========================
if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限执行安装脚本（请使用 sudo just install）"
  exit 1
fi

if [ ! -f "${SERVER_DIR}/.env" ]; then
  err "未找到 .env 文件，请确认脚本所在目录：${SERVER_DIR}"
  exit 1
fi

# 加载环境变量
# shellcheck disable=SC1090
source "$INSTALL_DIR/.env"

# =========================
# 安装进度提示
# =========================
log ""
log "${C_BOLD}▶ 开始安装 clash-for-linux${C_NC}"
log "${C_GRAY}────────────────────────────────────────${C_NC}"

# =========================
# 设置权限
# =========================
info "设置脚本执行权限..."
chmod +x "$INSTALL_DIR/scripts/cmd/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/scripts/lib/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/libs/clash/"* 2>/dev/null || true
chmod +x "$INSTALL_DIR/libs/subconverter/"*/subconverter 2>/dev/null || true
chmod +x "$INSTALL_DIR/clashctl" 2>/dev/null || true

# =========================
# CPU 架构检测
# =========================
info "检测 CPU 架构..."
if [[ -z "${CPU_ARCH:-}" ]]; then
  get_cpu_arch
fi

if [[ -z "${CPU_ARCH:-}" ]]; then
  err "无法识别 CPU 架构"
  exit 1
fi
ok "CPU 架构: ${CPU_ARCH}"

# =========================
# 交互式填写订阅地址
# =========================
prompt_clash_url() {
  local cur="${CLASH_URL:-}"
  cur="${cur%\"}"; cur="${cur#\"}"

  [ -n "$cur" ] && return 0

  # 非交互环境
  if [ ! -t 0 ]; then
    warn "CLASH_URL 为空且当前为非交互环境，将跳过输入引导。"
    return 0
  fi

  echo
  warn "未检测到订阅地址（CLASH_URL 为空）"
  echo "请粘贴你的 Clash 订阅地址（直接回车跳过，稍后手动编辑 .env）："
  read -r -p "Clash URL: " input_url

  input_url="$(printf '%s' "$input_url" | tr -d '\r')"

  if [ -z "$input_url" ]; then
    warn "已跳过填写订阅地址，安装完成后请手动编辑：${INSTALL_DIR}/.env"
    return 0
  fi

  if ! echo "$input_url" | grep -Eq '^https?://'; then
    err "订阅地址格式不正确（必须以 http:// 或 https:// 开头）"
    exit 1
  fi

  write_env_kv "${INSTALL_DIR}/.env" "CLASH_URL" "$input_url"
  export CLASH_URL="$input_url"
  ok "已写入订阅地址到：${INSTALL_DIR}/.env"
}

prompt_clash_url

# =========================
# 端口冲突检测
# =========================
info "检查端口占用..."
CLASH_HTTP_PORT="${CLASH_HTTP_PORT:-7890}"
CLASH_SOCKS_PORT="${CLASH_SOCKS_PORT:-7891}"
CLASH_REDIR_PORT="${CLASH_REDIR_PORT:-7892}"
EXTERNAL_CONTROLLER="${EXTERNAL_CONTROLLER:-127.0.0.1:9090}"

Port_Conflicts=()
for port in "$CLASH_HTTP_PORT" "$CLASH_SOCKS_PORT" "$CLASH_REDIR_PORT" "${EXTERNAL_CONTROLLER##*:}"; do
  [ "$port" = "auto" ] || [ -z "$port" ] && continue
  [[ "$port" =~ ^[0-9]+$ ]] && is_port_in_use "$port" && Port_Conflicts+=("$port")
done

if [ "${#Port_Conflicts[@]}" -ne 0 ]; then
  warn "端口冲突: ${Port_Conflicts[*]}（运行时自动分配）"
fi

install -d -m 0755 "$INSTALL_DIR/conf" "$INSTALL_DIR/logs" "$INSTALL_DIR/temp"

# =========================
# Clash 内核检查
# =========================
info "检查 Clash 内核..."
if ! resolve_clash_bin "$INSTALL_DIR" "$CPU_ARCH" >/dev/null 2>&1; then
  err "Clash 内核未就绪，请检查下载配置或手动放置二进制"
  exit 1
fi
ok "Clash 内核就绪"

# =========================
# systemd 安装
# =========================
info "配置 systemd 服务..."
Service_Enabled="unknown"
Service_Started="unknown"
Systemd_Usable="false"

if systemd_ready; then
  Systemd_Usable="true"
fi

if [ "$Systemd_Usable" = "true" ]; then
  if [ "${CLASH_ENABLE_SERVICE:-true}" = "true" ] || [ "${CLASH_START_SERVICE:-true}" = "true" ]; then
    CLASH_SERVICE_USER="$SERVICE_USER" CLASH_SERVICE_GROUP="$SERVICE_GROUP" \
      "$INSTALL_DIR/scripts/cmd/systemd-setup.sh"

    [ "${CLASH_ENABLE_SERVICE:-true}" = "true" ] && systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
    [ "${CLASH_START_SERVICE:-true}" = "true" ] && systemctl start "${SERVICE_NAME}.service" >/dev/null 2>&1 || true

    Service_Enabled=$(systemctl is-enabled --quiet "${SERVICE_NAME}.service" 2>/dev/null && echo "enabled" || echo "disabled")
    Service_Started=$(systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null && echo "active" || echo "inactive")
    ok "systemd 服务已配置"
  else
    info "已按配置跳过 systemd 服务安装与启动"
    Service_Enabled="disabled"
    Service_Started="inactive"
  fi
else
  command -v systemctl >/dev/null 2>&1 && \
    warn "systemctl 不可用（Docker？），跳过服务配置" || \
    info "无 systemd，使用 clashctl 管理进程"
fi

# =========================
# Shell 代理快捷命令
# =========================
info "安装代理快捷命令..."
install_profiled "$INSTALL_DIR" "$CLASH_HTTP_PORT" "$CLASH_SOCKS_PORT" || true
ok "已安装 proxy_on / proxy_down"

# =========================
# 安装 clashctl 和 m 命令
# =========================
[ -f "$INSTALL_DIR/clashctl" ] && ln -sf "$INSTALL_DIR/clashctl" /usr/local/bin/clashctl
[ -f "$INSTALL_DIR/m" ] && ln -sf "$INSTALL_DIR/m" /usr/local/bin/m

# =========================
# 安装完成输出
# =========================
# 使用紧凑格式输出安装结果
box_title "clash-for-linux 安装完成" 52
box_row "安装目录" "${INSTALL_DIR}" 52 10
box_row "运行用户" "${SERVICE_USER}:${SERVICE_GROUP}" 52 10
box_row "服务名称" "${SERVICE_NAME}.service" 52 10

# 服务状态
if [ "$Systemd_Usable" = "true" ]; then
  [[ "$Service_Enabled" == "enabled" ]] && se_colored="$(good "$Service_Enabled")" || se_colored="$(bad "$Service_Enabled")"
  [[ "$Service_Started" == "active" ]] && ss_colored="$(good "$Service_Started")" || ss_colored="$(bad "$Service_Started")"
  box_row "开机自启" "${se_colored}" 52 10
  box_row "服务状态" "${ss_colored}" 52 10
else
  box_row "服务管理" "clashctl (无 systemd)" 52 10
fi

# API 信息
api_port="${EXTERNAL_CONTROLLER##*:}"
api_host="${EXTERNAL_CONTROLLER%:*}"
[[ -z "$api_host" || "$api_host" == "$EXTERNAL_CONTROLLER" ]] && api_host="127.0.0.1"
CONF_FILE="$INSTALL_DIR/conf/config.yaml"
SECRET_VAL=""
if wait_secret_ready "$CONF_FILE" 6; then
  SECRET_VAL="$(read_secret_from_config "$CONF_FILE" || true)"
fi
box_row "API" "http://${api_host}:${api_port}" 52 10
if [[ -n "$SECRET_VAL" ]]; then
  # SECRET 过长时截断（先截断再加颜色）
  if [ ${#SECRET_VAL} -gt 32 ]; then
    SECRET_VAL="${SECRET_VAL:0:16}...${SECRET_VAL: -8}"
  fi
  box_row "SECRET" "${SECRET_VAL}" 52 10
else
  box_row "SECRET" "启动中..." 52 10
fi

# 订阅状态
if [[ -n "${CLASH_URL:-}" ]]; then
  box_row "订阅" "已配置" 52 10
else
  box_row "订阅" "未配置" 52 10
fi

box_end 52

# 操作提示
log ""
log "${C_BOLD}常用命令：${C_NC}"
if [ "$Systemd_Usable" = "true" ]; then
  log "  $(cmd "just status")   # 查看状态"
  log "  $(cmd "sudo just restart")   # 重启服务"
else
  log "  $(cmd "sudo clashctl status")   # 查看状态"
  log "  $(cmd "sudo clashctl restart")   # 重启服务"
fi

# 未配置订阅提示
if [[ -z "${CLASH_URL:-}" ]]; then
  log ""
  warn "请配置订阅地址后重启服务："
  log "  $(cmd "sudo bash -c 'echo \"CLASH_URL=<订阅地址>\" >> ${INSTALL_DIR}/.env'")"
fi

# 开启代理提示
PROFILED_FILE="/etc/profile.d/clash-for-linux.sh"
if [ -f "$PROFILED_FILE" ]; then
  log ""
  log "本 shell 复制执行：$(cmd "source $PROFILED_FILE && proxy_on")"
fi

# 启动诊断
sleep 1
if [ "$Systemd_Usable" = "true" ] && command -v journalctl >/dev/null 2>&1; then
  if journalctl -u "${SERVICE_NAME}.service" -n 50 --no-pager 2>/dev/null | grep -q "Clash订阅地址不可访问"; then
    log ""
    warn "服务启动异常：订阅不可用，请检查 CLASH_URL"
  fi
fi
