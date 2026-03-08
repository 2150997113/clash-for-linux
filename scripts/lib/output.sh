#!/bin/bash
# =========================
# 输出工具库
# 提供统一的彩色输出和日志函数
# =========================

# ---- 关色开关检测 ----
_OUTPUT_NO_COLOR=0

# 初始化颜色（调用一次即可）
output_init() {
  # 命令行参数检测
  for arg in "${@:-}"; do
    case "$arg" in
      --no-color|--nocolor)
        _OUTPUT_NO_COLOR=1
        ;;
    esac
  done

  # 环境变量检测
  if [[ -n "${NO_COLOR:-}" ]] || [[ -n "${CLASH_NO_COLOR:-}" ]]; then
    _OUTPUT_NO_COLOR=1
  fi

  # ---- 初始化颜色变量 ----
  if [[ "$_OUTPUT_NO_COLOR" -eq 0 ]] && [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    if tput setaf 1 >/dev/null 2>&1; then
      C_RED="$(tput setaf 1)"
      C_GREEN="$(tput setaf 2)"
      C_YELLOW="$(tput setaf 3)"
      C_BLUE="$(tput setaf 4)"
      C_CYAN="$(tput setaf 6)"
      C_GRAY="$(tput setaf 8 2>/dev/null || echo '')"
      C_BOLD="$(tput bold)"
      C_UL="$(tput smul)"
      C_NC="$(tput sgr0)"
    fi
  fi

  # ---- ANSI fallback ----
  if [[ "$_OUTPUT_NO_COLOR" -eq 0 ]] && [[ -t 1 ]] && [[ -z "${C_NC:-}" ]]; then
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_GRAY=$'\033[90m'
    C_BOLD=$'\033[1m'
    C_UL=$'\033[4m'
    C_NC=$'\033[0m'
  fi

  # ---- 强制无色 ----
  if [[ "$_OUTPUT_NO_COLOR" -eq 1 ]] || [[ ! -t 1 ]]; then
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_GRAY='' C_BOLD='' C_UL='' C_NC=''
  fi

  # 导出供子进程使用
  export C_RED C_GREEN C_YELLOW C_BLUE C_CYAN C_GRAY C_BOLD C_UL C_NC
}

# =========================
# 基础输出函数
# =========================
log()   { printf "%b\n" "$*"; }
info()  { log "${C_CYAN:-}[INFO]${C_NC:-} $*"; }
ok()    { log "${C_GREEN:-}[OK]${C_NC:-} $*"; }
warn()  { log "${C_YELLOW:-}[WARN]${C_NC:-} $*"; }
err()   { log "${C_RED:-}[ERROR]${C_NC:-} $*"; }

# =========================
# 样式助手
# =========================
path()  { printf "%b" "${C_BOLD:-}$*${C_NC:-}"; }
cmd()   { printf "%b" "${C_GRAY:-}$*${C_NC:-}"; }
url()   { printf "%b" "${C_UL:-}$*${C_NC:-}"; }
good()  { printf "%b" "${C_GREEN:-}$*${C_NC:-}"; }
bad()   { printf "%b" "${C_RED:-}$*${C_NC:-}"; }

# =========================
# 分段标题
# =========================
section() {
  local title="$*"
  log ""
  log "${C_BOLD:-}▶ ${title}${C_NC:-}"
  log "${C_GRAY:-}────────────────────────────────────────${C_NC:-}"
}

# =========================
# 盒子输出（用于关键信息展示）
# =========================

# 剥离 ANSI 转义序列（用于计算可视宽度）
strip_ansi() {
  printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# 计算字符串可视宽度（中文按 2 宽处理，忽略 ANSI 转义）
vis_width() {
  local s
  s="$(strip_ansi "$1")"
  printf '%s' "$s" | python3 -c '
import sys
s = sys.stdin.read()
w = 0
for ch in s:
  w += 2 if ord(ch) >= 0x2E80 else 1
print(w)
'
}

pad_right() {
  local s="$1" w="$2"
  local cur
  cur="$(vis_width "$s")"
  local pad=$(( w - cur ))
  (( pad < 0 )) && pad=0
  printf "%s%*s" "$s" "$pad" ""
}

# 生成指定数量的横线
_make_dashes() {
  local _n="$1"
  local _dashes=""
  local _i
  for ((_i=0; _i<_n; _i++)); do
    _dashes="${_dashes}─"
  done
  printf '%s' "$_dashes"
}

box_title() {
  local title="$1"
  local width="${2:-50}"
  local inner=$((width-2))
  printf "┌%s┐\n" "$(_make_dashes "$inner")"
  local t=" $title "
  local tw; tw="$(vis_width "$t")"
  local left=$(( (inner - tw)/2 )); ((left<0)) && left=0
  local right=$(( inner - tw - left )); ((right<0)) && right=0
  printf "│%*s%s%*s│\n" "$left" "" "$t" "$right" ""
  printf "├%s┤\n" "$(_make_dashes "$inner")"
}

box_row() {
  local k="$1"
  local v="$2"
  local width="${3:-50}"
  local keyw="${4:-12}"
  local inner=$((width-2))
  local left="$(pad_right "$k" "$keyw")"

  # 计算值可用的最大宽度：总宽度 - 2(边框) - keyw - 4(空格和分隔)
  local max_valw=$(( inner - keyw - 4 ))
  (( max_valw < 10 )) && max_valw=10

  # 获取值的可视内容（无颜色）
  local v_stripped
  v_stripped="$(strip_ansi "$v")"

  # 如果值过长，截断并添加 ...
  if [ "$(vis_width "$v_stripped")" -gt "$max_valw" ]; then
    # 逐步截断直到合适
    local truncated="$v_stripped"
    while [ "$(vis_width "$truncated")" -gt $((max_valw - 3)) ] && [ -n "$truncated" ]; do
      truncated="${truncated%?}"
    done
    v="${truncated}..."
  fi

  local line=" ${left}  ${v}"
  local lw; lw="$(vis_width "$line")"
  local pad=$(( inner - lw )); ((pad<0)) && pad=0
  printf "│%s%*s│\n" "$line" "$pad" ""
}

box_end() {
  local width="${1:-50}"
  local inner=$((width-2))
  printf "└%s┘\n" "$(_make_dashes "$inner")"
}

# =========================
# Action 输出（用于 systemd 兼容）
# =========================
action_success() {
  echo -en "\033[60G[\033[1;32m OK \033[0;39m]\r"
  return 0
}

action_failure() {
  local rc=$?
  echo -en "\033[60G[\033[1;31mFAILED\033[0;39m]\r"
  [ -x /bin/plymouth ] && /bin/plymouth --details 2>/dev/null || true
  return "$rc"
}

action() {
  local STRING="$1"
  shift
  if "$@"; then
    action_success || true
    return 0
  else
    action_failure || true
    return 1
  fi
}

# 判断命令是否正常执行
# - 手动模式：失败直接 exit
# - systemd 模式：只打印状态，不影响退出码
if_success() {
  local ok_msg="$1" fail_msg="$2" rc="$3"

  if [ "$rc" -eq 0 ]; then
    action "$ok_msg" /bin/true 2>/dev/null || true
    return 0
  fi

  action "$fail_msg" /bin/false 2>/dev/null || true

  if [ "${SYSTEMD_MODE:-false}" = "true" ]; then
    return "$rc"
  else
    exit "$rc"
  fi
}
