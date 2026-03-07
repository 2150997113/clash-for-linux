#!/usr/bin/env bash
# =========================
# Clash for Linux - 服务重启脚本
# =========================
set -euo pipefail

# 获取项目根目录
Server_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$Server_Dir/scripts/lib/output.sh"
output_init

# =========================
# 检查参数
# =========================
if [ "${1:-}" = "--update" ]; then
  info "更新订阅..."
  bash "$Server_Dir/scripts/cmd/subscription-update.sh" || exit 1
fi

# =========================
# 停止服务
# =========================
info "停止服务..."

if [ -f "$Server_Dir/scripts/cmd/service-stop.sh" ]; then
  bash "$Server_Dir/scripts/cmd/service-stop.sh" || true
else
  # 兜底：直接杀进程
  PID_FILE="$Server_Dir/temp/clash.pid"
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      for _ in {1..5}; do
        sleep 1
        kill -0 "$pid" 2>/dev/null || break
      done
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
fi

sleep 2

# =========================
# 启动服务
# =========================
info "启动服务..."

if [ -f "$Server_Dir/scripts/cmd/service-start.sh" ]; then
  bash "$Server_Dir/scripts/cmd/service-start.sh"
else
  # 兜底：直接启动
  Conf_Dir="$Server_Dir/conf"
  Log_Dir="$Server_Dir/logs"
  Temp_Dir="$Server_Dir/temp"
  PID_FILE="$Temp_Dir/clash.pid"

  # shellcheck disable=SC1090
  source "$Server_Dir/scripts/lib/cpu-arch.sh"
  # shellcheck disable=SC1090
  source "$Server_Dir/scripts/lib/clash-resolve.sh"

  [ -z "${CpuArch:-}" ] && get_cpu_arch
  Clash_Bin="$(resolve_clash_bin "$Server_Dir" "$CpuArch")"

  nohup "$Clash_Bin" -d "$Conf_Dir" >>"$Log_Dir/clash.log" 2>&1 &
  echo $! > "$PID_FILE"
fi

ok "服务重启完成"
