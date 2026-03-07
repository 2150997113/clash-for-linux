#!/bin/bash
# =========================
# 环境变量工具库
# 提供 .env 文件读写操作
# =========================

# 转义 .env 值中的特殊字符
escape_env_value() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# 写入 key=value 到 .env 文件
# - 自动创建文件
# - 存在则替换，不存在则追加
# - 统一写成：export KEY="VALUE"
write_env_kv() {
  local file="$1"
  local key="$2"
  local val="$3"

  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  [ -f "$file" ] || touch "$file"

  # 清理 CRLF
  val="$(printf '%s' "$val" | tr -d '\r')"
  local esc
  esc="$(escape_env_value "$val")"

  if grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file"; then
    sed -i -E "s|^[[:space:]]*(export[[:space:]]+)?${key}=.*|export ${key}=\"${esc}\"|g" "$file"
  else
    printf 'export %s="%s"\n' "$key" "$esc" >> "$file"
  fi
}

# 从 .env 文件读取值
read_env_kv() {
  local file="$1"
  local key="$2"
  [ -f "$file" ] || return 1

  local val
  val="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" 2>/dev/null | head -n 1 | sed -E "s/^[[:space:]]*(export[[:space:]]+)?${key}=[\"']?//; s/[\"']?[[:space:]]*$//")"
  [ -n "$val" ] && printf '%s' "$val"
}

# 从 config.yaml 提取 secret
read_secret_from_config() {
  local conf_file="$1"
  [ -f "$conf_file" ] || return 1

  local s
  s="$(
    sed -nE 's/^[[:space:]]*secret:[[:space:]]*//p' "$conf_file" \
      | head -n 1 \
      | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/; s/^[[:space:]]*'\''(.*)'\''[[:space:]]*$/\1/' \
      | tr -d '\r'
  )"

  s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -n "$s" ] || return 1
  printf '%s' "$s"
}
