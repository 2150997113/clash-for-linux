#!/bin/bash

# 自定义action函数，实现通用action功能
success() {
  echo -en "\\033[60G[\\033[1;32m  OK  \\033[0;39m]\r"
  return 0
}

failure() {
  local rc=$?
  echo -en "\\033[60G[\\033[1;31mFAILED\\033[0;39m]\r"
  [ -x /bin/plymouth ] && /bin/plymouth --details
  return $rc
}

action() {
  local STRING rc

  STRING=$1
  echo -n "$STRING "
  shift
  "$@" && success $"$STRING" || failure $"$STRING"
  rc=$?
  echo
  return $rc
}

# 函数，判断命令是否正常执行
if_success() {
  local ReturnStatus=$3
  if [ $ReturnStatus -eq 0 ]; then
          action "$1" /bin::true
  else
          action "$2" /bin::false
          exit 1
  fi
}

# 获取项目根目录（从 scripts/cmd/ 向上两级）
Server_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
Conf_Dir="$Server_Dir/conf"
Log_Dir="$Server_Dir/logs"
Temp_Dir="$Server_Dir/temp"
PID_FILE="$Temp_Dir/clash.pid"

if [ "$1" = "--update" ]; then
	bash "$Server_Dir/scripts/cmd/subscription-update.sh" || exit 1
fi

## 关闭clash服务
Text1="服务关闭成功！"
Text2="服务关闭失败！"
# 查询并关闭程序进程
if [ -f "$PID_FILE" ]; then
	PID=$(cat "$PID_FILE")
	if [ -n "$PID" ]; then
		kill "$PID"
		ReturnStatus=$?
		for i in {1..5}; do
			sleep 1
			if ! kill -0 "$PID" 2>/dev/null; then
				break
			fi
		done
		if kill -0 "$PID" 2>/dev/null; then
			kill -9 "$PID"
		fi
	else
		ReturnStatus=1
	fi
	rm -f "$PID_FILE"
else
	PIDS=$(pgrep -f "clash-linux-")
	if [ -n "$PIDS" ]; then
		kill $PIDS
		ReturnStatus=$?
		for i in {1..5}; do
			sleep 1
			if ! pgrep -f "clash-linux-" >/dev/null; then
				break
			fi
		done
		if pgrep -f "clash-linux-" >/dev/null; then
			kill -9 $PIDS
		fi
	else
		ReturnStatus=0
	fi
fi
if_success $Text1 $Text2 $ReturnStatus

sleep 3

## 获取CPU架构
# shellcheck disable=SC1090
source "$Server_Dir/scripts/lib/cpu-arch.sh"

## 重启启动clash服务
Text5="服务启动成功！"
Text6="服务启动失败！"
# shellcheck disable=SC1090
source "$Server_Dir/scripts/lib/clash-resolve.sh"
Clash_Bin="$(resolve_clash_bin "$Server_Dir" "$CpuArch")"
ReturnStatus=$?

if [ $ReturnStatus -eq 0 ]; then
	nohup "$Clash_Bin" -d "$Conf_Dir" &> "$Log_Dir/clash.log" &
	PID=$!
	ReturnStatus=$?
	if [ $ReturnStatus -eq 0 ]; then
		echo "$PID" > "$PID_FILE"
	fi
	if_success $Text5 $Text6 $ReturnStatus
else
	if_success $Text5 $Text6 $ReturnStatus
fi
