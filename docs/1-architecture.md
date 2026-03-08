# 架构设计文档

## 1. 项目定位

面向 Linux 服务器的 Clash 自动化管理脚本集。

### 核心特性

- 开箱即用：自动配置 systemd 服务
- 可维护：配置、日志、二进制分离
- 可回滚：多订阅管理与配置兜底
- 安全默认：API 仅绑定本机，自动生成 Secret

### 技术栈

| 层级 | 技术 |
|------|------|
| 代理内核 | Clash Meta / Mihomo |
| 脚本语言 | Bash (`set -euo pipefail`) |
| 服务管理 | systemd |
| 订阅转换 | subconverter (可选) |

---

## 2. 目录结构

```
clash-for-linux/
├── libs/                      # 二进制文件
│   ├── clash/                 # Clash 内核 (amd64/arm64/armv7)
│   └── subconverter/          # 订阅转换工具
├── scripts/
│   ├── lib/                   # 库脚本
│   └── cmd/                   # 执行脚本
├── conf/                      # 配置目录
├── volumes/                   # 用户数据
│   ├── geoip/                 # GeoIP 数据库
│   └── mixin.d/               # Mixin 配置
├── logs/                      # 日志
├── temp/                      # 临时文件
├── docs/                      # 文档
├── .env                       # 环境变量
├── justfile                   # 命令入口
└── clashctl                   # CLI 工具
```

---

## 3. 模块架构

```
┌─────────────────────────────────────────────┐
│              clashctl (CLI)                  │
│   start / stop / restart / status / update  │
└─────────────────────┬───────────────────────┘
                      │
┌─────────────────────▼───────────────────────┐
│           service-start.sh                   │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │cpu-arch │ │port-check│ │config   │       │
│  │         │ │         │ │-check   │       │
│  └─────────┘ └─────────┘ └─────────┘       │
└─────────────────────┬───────────────────────┘
                      │
┌─────────────────────▼───────────────────────┐
│           Clash 内核 (Mihomo)                │
│   HTTP (7890) │ SOCKS5 (7891) │ Redir (7892)│
└─────────────────────────────────────────────┘
```

### 模块职责

| 模块 | 文件 | 职责 |
|------|------|------|
| CLI | `clashctl` | 统一命令入口 |
| 启动 | `service-start.sh` | 订阅下载、配置生成、内核启动 |
| 安装 | `service-install.sh` | 一键安装、systemd 配置 |
| 配置 | `config-check.sh` | Mixin 合并、配置注入 |

---

## 4. 启动流程

```
1. 加载 .env → 2. 检测 CPU 架构 → 3. 端口检测
       ↓
4. 下载订阅 → 5. 配置解析/转换 → 6. 注入配置
       ↓
7. Mixin 合并 → 8. 启动内核
```

### 关键逻辑

| 模式 | 订阅失败行为 |
|------|-------------|
| systemd (`SYSTEMD_MODE=true`) | 使用兜底配置，不退出 |
| 手动模式 | 直接退出，提示用户 |

### 配置优先级

```
订阅配置 < Mixin 配置 < 运行时注入
```

---

## 5. 安装流程

| 步骤 | 动作 |
|------|------|
| 1 | 检查 root 权限、.env 文件 |
| 2 | 检测 CPU 架构 |
| 3 | 端口冲突检测 |
| 4 | 交互式填写订阅地址（若为空） |
| 5 | 创建 conf/logs/temp 目录 |
| 6 | 验证 Clash 内核 |
| 7 | 生成 systemd 服务 |
| 8 | 启动服务 |
| 9 | 安装 clashctl 到 /usr/local/bin |
| 10 | 安装 profile.d 脚本 |

---

## 6. 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLASH_URL` | - | 订阅地址（必填） |
| `CLASH_SECRET` | 自动生成 | API 密钥 |
| `CLASH_HTTP_PORT` | 7890 | HTTP 代理端口 |
| `CLASH_SOCKS_PORT` | 7891 | SOCKS5 端口 |
| `CLASH_REDIR_PORT` | 7892 | 透明代理端口 |
| `EXTERNAL_CONTROLLER` | 127.0.0.1:9090 | API 地址 |
| `EXTERNAL_CONTROLLER_ENABLED` | true | 是否启用 API |

---

## 7. systemd 配置

```ini
[Unit]
Description=Clash for Linux
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/clash-for-linux
ExecStart=/bin/bash /opt/clash-for-linux/scripts/cmd/service-start.sh
Restart=on-failure
RestartSec=5
Environment=SYSTEMD_MODE=true

[Install]
WantedBy=multi-user.target
```

---

## 8. 开发规范

### 脚本规范

```bash
#!/bin/bash
set -euo pipefail
trap 'echo "[ERR] line=$LINENO" >&2' ERR
```

### 函数命名

| 前缀 | 用途 | 示例 |
|------|------|------|
| `ensure_` | 确保资源存在 | `ensure_subconverter` |
| `resolve_` | 解析返回值 | `resolve_clash_bin` |
| `force_` | 强制写入 | `force_write_secret` |
| `is_` | 布尔判断 | `is_running` |

### 日志格式

```bash
echo "[INFO] message"
echo -e "\033[33m[WARN]\033[0m message"
echo -e "\033[31m[ERROR]\033[0m message" >&2
echo -e "\033[32m[OK]\033[0m message"
```

---

## 9. 版本兼容性

### 操作系统

Ubuntu 18.04+、Debian 10+、CentOS 7+、RHEL 7+

### 架构

| 架构 | 二进制 |
|------|--------|
| x86_64/amd64 | `clash-linux-amd64` |
| aarch64/arm64 | `clash-linux-arm64` |
| armv7l | `clash-linux-armv7` |

---

## 10. 参考链接

- [Mihomo 文档](https://wiki.metacubex.one/)
- [subconverter](https://github.com/tindy2013/subconverter)
