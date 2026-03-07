#!/bin/bash
set -euo pipefail

# =========================
# Clash for Linux - 安装脚本
# =========================

# 获取项目根目录
Server_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
Install_Dir="$Server_Dir"
Service_Name="clash-for-linux"
Service_User="root"
Service_Group="root"

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$Install_Dir/scripts/lib/output.sh"
output_init "$@"

# shellcheck disable=SC1090
source "$Install_Dir/scripts/lib/env-utils.sh"

# shellcheck disable=SC1090
source "$Install_Dir/scripts/lib/systemd-utils.sh"

# shellcheck disable=SC1090
source "$Install_Dir/scripts/lib/cpu-arch.sh"

# shellcheck disable=SC1090
source "$Install_Dir/scripts/lib/clash-resolve.sh"

# shellcheck disable=SC1090
source "$Install_Dir/scripts/lib/port-check.sh"

# =========================
# 前置校验
# =========================
if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限执行安装脚本（请使用 sudo make install）"
  exit 1
fi

if [ ! -f "${Server_Dir}/.env" ]; then
  err "未找到 .env 文件，请确认脚本所在目录：${Server_Dir}"
  exit 1
fi

# 加载环境变量
# shellcheck disable=SC1090
source "$Install_Dir/.env"

# =========================
# 设置权限
# =========================
chmod +x "$Install_Dir/scripts/cmd/"*.sh 2>/dev/null || true
chmod +x "$Install_Dir/scripts/lib/"*.sh 2>/dev/null || true
chmod +x "$Install_Dir/libs/clash/"* 2>/dev/null || true
chmod +x "$Install_Dir/libs/subconverter/"*/subconverter 2>/dev/null || true
chmod +x "$Install_Dir/clashctl" 2>/dev/null || true

# =========================
# CPU 架构检测
# =========================
if [[ -z "${CpuArch:-}" ]]; then
  get_cpu_arch
fi

if [[ -z "${CpuArch:-}" ]]; then
  err "无法识别 CPU 架构"
  exit 1
fi
info "CPU architecture: ${CpuArch}"

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
    warn "已跳过填写订阅地址，安装完成后请手动编辑：${Install_Dir}/.env"
    return 0
  fi

  if ! echo "$input_url" | grep -Eq '^https?://'; then
    err "订阅地址格式不正确（必须以 http:// 或 https:// 开头）"
    exit 1
  fi

  write_env_kv "${Install_Dir}/.env" "CLASH_URL" "$input_url"
  export CLASH_URL="$input_url"
  ok "已写入订阅地址到：${Install_Dir}/.env"
}

prompt_clash_url

# =========================
# 端口冲突检测
# =========================
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
  warn "检测到端口冲突: ${Port_Conflicts[*]}，运行时将自动分配可用端口"
fi

install -d -m 0755 "$Install_Dir/conf" "$Install_Dir/logs" "$Install_Dir/temp"

# =========================
# Clash 内核检查
# =========================
if ! resolve_clash_bin "$Install_Dir" "$CpuArch" >/dev/null 2>&1; then
  err "Clash 内核未就绪，请检查下载配置或手动放置二进制"
  exit 1
fi

# =========================
# systemd 安装
# =========================
Service_Enabled="unknown"
Service_Started="unknown"
Systemd_Usable="false"

if systemd_ready; then
  Systemd_Usable="true"
fi

if [ "$Systemd_Usable" = "true" ]; then
  if [ "${CLASH_ENABLE_SERVICE:-true}" = "true" ] || [ "${CLASH_START_SERVICE:-true}" = "true" ]; then
    CLASH_SERVICE_USER="$Service_User" CLASH_SERVICE_GROUP="$Service_Group" \
      "$Install_Dir/scripts/cmd/systemd-setup.sh"

    [ "${CLASH_ENABLE_SERVICE:-true}" = "true" ] && systemctl enable "${Service_Name}.service" >/dev/null 2>&1 || true
    [ "${CLASH_START_SERVICE:-true}" = "true" ] && systemctl start "${Service_Name}.service" >/dev/null 2>&1 || true

    Service_Enabled=$(systemctl is-enabled --quiet "${Service_Name}.service" 2>/dev/null && echo "enabled" || echo "disabled")
    Service_Started=$(systemctl is-active --quiet "${Service_Name}.service" 2>/dev/null && echo "active" || echo "inactive")
  else
    info "已按配置跳过 systemd 服务安装与启动"
    Service_Enabled="disabled"
    Service_Started="inactive"
  fi
else
  command -v systemctl >/dev/null 2>&1 && \
    warn "检测到 systemctl 但不可用（常见于 Docker 容器），已跳过服务单元生成" || \
    warn "未检测到 systemd，已跳过服务单元生成"
fi

# =========================
# Shell 代理快捷命令
# =========================
install_profiled "$Install_Dir" "$CLASH_HTTP_PORT" "$CLASH_SOCKS_PORT" || true

# =========================
# 安装 clashctl 命令
# =========================
[ -f "$Install_Dir/clashctl" ] && install -m 0755 "$Install_Dir/clashctl" /usr/local/bin/clashctl

# =========================
# 安装完成输出
# =========================
section "安装完成"
ok "Clash for Linux 已安装至: $(path "${Install_Dir}")"
log "📦 安装目录：$(path "${Install_Dir}")"
log "👤 运行用户：${Service_User}:${Service_Group}"
log "🔧 服务名称：${Service_Name}.service"

# 服务状态
section "服务状态"
if [ "$Systemd_Usable" = "true" ]; then
  [[ "$Service_Enabled" == "enabled" ]] && se_colored="$(good "$Service_Enabled")" || se_colored="$(bad "$Service_Enabled")"
  [[ "$Service_Started" == "active" ]] && ss_colored="$(good "$Service_Started")" || ss_colored="$(bad "$Service_Started")"

  log "🧷 开机自启：${se_colored}"
  log "🟢 服务状态：${ss_colored}"
  log ""
  log "${C_BOLD}常用命令：${C_NC}"
  log "  $(cmd "make status")"
  log "  $(cmd "sudo make restart")"
else
  warn "当前环境未启用 systemd，请使用 clashctl 管理进程"
  log "  $(cmd "sudo clashctl start")"
  log "  $(cmd "sudo clashctl restart")"
fi

# Dashboard
section "控制面板"
api_port="${EXTERNAL_CONTROLLER##*:}"
api_host="${EXTERNAL_CONTROLLER%:*}"
[[ -z "$api_host" || "$api_host" == "$EXTERNAL_CONTROLLER" ]] && api_host="127.0.0.1"

CONF_FILE="$Install_Dir/conf/config.yaml"
SECRET_VAL=""
if wait_secret_ready "$CONF_FILE" 6; then
  SECRET_VAL="$(read_secret_from_config "$CONF_FILE" || true)"
fi

dash="http://${api_host}:${api_port}/ui"
log "🌐 Dashboard：$(url "$dash")"

if [[ -n "$SECRET_VAL" ]]; then
  MASKED="${SECRET_VAL:0:4}****${SECRET_VAL: -4}"
  log "🔐 Secret：${C_YELLOW}${MASKED}${C_NC}"
  log "   查看完整 Secret：$(cmd "sudo sed -nE 's/^[[:space:]]*secret:[[:space:]]*//p' \"$CONF_FILE\" | head -n 1")"
else
  log "🔐 Secret：${C_YELLOW}启动中暂未读到（稍后再试）${C_NC}"
fi

# 订阅状态
section "订阅状态"
if [[ -n "${CLASH_URL:-}" ]]; then
  ok "订阅地址已配置（CLASH_URL 已写入 .env）"
else
  warn "订阅地址未配置（必须）"
  log ""
  log "配置订阅地址："
  log "  $(cmd "sudo bash -c 'echo \"CLASH_URL=<订阅地址>\" >> ${Install_Dir}/.env'")"
  log ""
  log "配置完成后重启服务："
  [ "$Systemd_Usable" = "true" ] && log "  $(cmd "sudo make restart")" || log "  $(cmd "sudo clashctl restart")"
fi

# 下一步
section "下一步（可选）"
PROFILED_FILE="/etc/profile.d/clash-for-linux.sh"
if [ -f "$PROFILED_FILE" ]; then
  log "开启终端代理："
  log "  $(cmd "source $PROFILED_FILE")"
  log "  $(cmd "proxy_on")"
fi

# 启动诊断
sleep 1
if [ "$Systemd_Usable" = "true" ] && command -v journalctl >/dev/null 2>&1; then
  if journalctl -u "${Service_Name}.service" -n 50 --no-pager 2>/dev/null | grep -q "Clash订阅地址不可访问"; then
    warn "服务启动异常：订阅不可用，请检查 CLASH_URL"
  fi
fi
