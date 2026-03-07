#!/usr/bin/env bash
# =========================
# Clash for Linux - 卸载脚本
# =========================
set -euo pipefail

# 获取项目根目录
Server_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
Install_Dir="$Server_Dir"
Service_Name="clash-for-linux"

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$Install_Dir/scripts/lib/output.sh"
output_init

# =========================
# 权限检查
# =========================
if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限执行卸载脚本（请使用 sudo make uninstall）"
  exit 1
fi

info "开始卸载 ${Service_Name} ..."

# =========================
# 1) 停止服务
# =========================
if [ -f "${Install_Dir}/scripts/cmd/service-stop.sh" ]; then
  info "停止服务..."
  bash "${Install_Dir}/scripts/cmd/service-stop.sh" >/dev/null 2>&1 || true
fi

# systemd 停止
if command -v systemctl >/dev/null 2>&1; then
  info "停止 systemd 服务..."
  systemctl stop "${Service_Name}.service" >/dev/null 2>&1 || true
  systemctl disable "${Service_Name}.service" >/dev/null 2>&1 || true
fi

# 兜底：按 PID 文件停止
PID_FILE="${Install_Dir}/temp/clash.pid"
if [ -f "$PID_FILE" ]; then
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

# 兜底：按进程名停止
if pgrep -x clash >/dev/null 2>&1; then
  warn "检测到残留 clash 进程，尝试结束..."
  pkill -x clash 2>/dev/null || true
  sleep 1
  pgrep -x clash >/dev/null 2>&1 && pkill -9 -x clash 2>/dev/null || true
fi

# =========================
# 2) 删除 systemd unit
# =========================
Unit_Path="/etc/systemd/system/${Service_Name}.service"

if [ -f "$Unit_Path" ]; then
  rm -f "$Unit_Path"
  ok "已移除: ${Unit_Path}"
fi

if [ -d "/etc/systemd/system/${Service_Name}.service.d" ]; then
  rm -rf "/etc/systemd/system/${Service_Name}.service.d"
  ok "已移除: /etc/systemd/system/${Service_Name}.service.d"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed >/dev/null 2>&1 || true
fi

# =========================
# 3) 清理配置文件
# =========================
[ -f "/etc/default/${Service_Name}" ] && rm -f "/etc/default/${Service_Name}" && ok "已移除: /etc/default/${Service_Name}"
[ -f "/etc/profile.d/clash-for-linux.sh" ] && rm -f "/etc/profile.d/clash-for-linux.sh" && ok "已移除: /etc/profile.d/clash-for-linux.sh"
[ -f "${Install_Dir}/temp/clash-for-linux.sh" ] && rm -f "${Install_Dir}/temp/clash-for-linux.sh" && ok "已移除: ${Install_Dir}/temp/clash-for-linux.sh"
[ -f "/usr/local/bin/clashctl" ] && rm -f "/usr/local/bin/clashctl" && ok "已移除: /usr/local/bin/clashctl"

# =========================
# 4) 完成
# =========================
info "项目目录保留: ${Install_Dir}"
info "如需完全删除，请手动执行: rm -rf ${Install_Dir}"

echo
warn "如果你曾执行 proxy_on，当前终端可能仍保留代理环境变量。可执行："
echo "  unset http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY"

echo
ok "卸载完成 ✅"
