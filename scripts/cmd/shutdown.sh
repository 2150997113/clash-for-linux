#!/usr/bin/env bash
set -euo pipefail

# 关闭 clash 服务
# 获取项目根目录（从 scripts/cmd/ 向上两级）
Server_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
Temp_Dir="$Server_Dir/temp"
Conf_Dir="$Server_Dir/conf"
PID_FILE="$Temp_Dir/clash.pid"

mkdir -p "$Temp_Dir"

# 1) 优先按 PID_FILE 停
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    for _ in {1..8}; do
      sleep 1
      if ! kill -0 "$PID" 2>/dev/null; then
        break
      fi
    done
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
else
  # 2) 兜底：按 "-d $Conf_Dir" 特征找（比 clash-linux- 更稳）
  # 说明：你的 start.sh 启动命令形如：<clashbin> -d "$Conf_Dir"
  PIDS="$(pgrep -f " -d ${Conf_Dir}(\s|$)" || true)"
  if [ -n "${PIDS:-}" ]; then
    kill $PIDS 2>/dev/null || true
    for _ in {1..8}; do
      sleep 1
      if ! pgrep -f " -d ${Conf_Dir}(\s|$)" >/dev/null 2>&1; then
        break
      fi
    done
    if pgrep -f " -d ${Conf_Dir}(\s|$)" >/dev/null 2>&1; then
      kill -9 $PIDS 2>/dev/null || true
    fi
  fi
fi

# 3) 清理环境变量文件（删除，而不是置空）
Env_File="${CLASH_ENV_FILE:-}"
if [ "$Env_File" != "off" ] && [ "$Env_File" != "disabled" ]; then
  if [ -z "$Env_File" ]; then
    if [ -w /etc/profile.d ]; then
      Env_File="/etc/profile.d/clash-for-linux.sh"
    else
      Env_File="$Temp_Dir/clash-for-linux.sh"
    fi
  fi

  if [ -f "$Env_File" ]; then
    rm -f "$Env_File" || true
  fi
fi

echo -e "\n服务关闭成功。若当前终端已开启代理，请执行：proxy_off\n"
