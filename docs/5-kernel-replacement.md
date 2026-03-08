# 内核更换指南

本文档介绍如何在 clash-for-linux 中更换 Clash 内核，以支持不同的功能需求。

---

## 1. 为什么需要更换内核？

项目默认使用 [Dreamacro/clash](https://github.com/Dreamacro/clash) 内核，但该内核已停止维护。常见需求：

| 内核 | 特点 |
|------|------|
| Dreamacro/clash | 原版，已停止维护 |
| MetaCubeX/mihomo | Clash.Meta，持续维护，支持更多协议 |
| 其他兼容内核 | 根据需求选择 |

---

## 2. 内核查找优先级

启动服务时，系统按以下顺序查找内核：

```
1. CLASH_BIN 环境变量指定的路径
       ↓
2. libs/clash/clash-{resolved_arch}  (按架构匹配)
       ↓
3. libs/clash/clash-{raw_arch}       (原始架构名)
       ↓
4. libs/clash/clash                  (通用命名)
       ↓
5. 自动下载 (如果启用 CLASH_AUTO_DOWNLOAD)
```

---

## 3. 更换方式

### 方式一：CLASH_BIN 环境变量（推荐）

在 `.env` 文件中指定内核路径：

```bash
# 编辑 .env
CLASH_BIN=/path/to/your/mihomo
```

**优点**：
- 不影响原有内核文件
- 可随时切换回默认内核
- 路径灵活

### 方式二：替换 libs/clash/ 下的文件

直接替换对应架构的二进制文件：

```
libs/clash/
├── clash-linux-amd64   # x86_64 架构
├── clash-linux-arm64   # aarch64 架构
└── clash-linux-armv7   # armv7 架构
```

**架构对应关系**：

| CPU 架构 | 文件名 |
|----------|--------|
| x86_64, amd64 | clash-linux-amd64 |
| aarch64, arm64 | clash-linux-arm64 |
| armv7, armv7l | clash-linux-armv7 |

### 方式三：自定义下载源

在 `.env` 中配置自动下载地址：

```bash
# 使用 Mihomo 内核
CLASH_DOWNLOAD_URL_TEMPLATE=https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-{arch}.gz

# 或禁用自动下载
CLASH_AUTO_DOWNLOAD=false
```

URL 模板中的 `{arch}` 会被替换为解析后的架构名（如 `linux-amd64`）。

---

## 4. 实际操作示例

### 更换为 Mihomo 内核

**步骤 1：下载内核**

```bash
# 确认当前架构
uname -m
# 输出示例: x86_64

# 下载对应架构的 Mihomo
cd /tmp
wget https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64.gz
gzip -d mihomo-linux-amd64.gz
chmod +x mihomo-linux-amd64
```

**步骤 2：配置使用（二选一）**

```bash
# 方法 A: 通过环境变量指定
echo 'CLASH_BIN=/tmp/mihomo-linux-amd64' >> /path/to/clash-for-linux/.env

# 方法 B: 替换内置文件
cp /tmp/mihomo-linux-amd64 /path/to/clash-for-linux/libs/clash/clash-linux-amd64
```

**步骤 3：重启服务**

```bash
just restart
# 或
clashctl restart
```

**步骤 4：验证**

```bash
# 查看内核版本
just status
# 或检查日志
tail -f logs/clash.log
```

---

## 5. 注意事项

### 兼容性

- 确保内核与系统架构匹配
- Mihomo 兼容原版 Clash 配置，但部分高级功能需要更新配置格式

### 权限

```bash
# 确保内核可执行
chmod +x /path/to/clash-binary
```

### 版本检查

```bash
# 直接运行内核查看版本
./libs/clash/clash-linux-amd64 -v
```

---

## 6. 常见问题

### Q: 启动失败提示 "未找到可用的 Clash 二进制"

检查：
1. 内核文件是否存在且可执行
2. 架构是否匹配 (`uname -m`)
3. `.env` 中的 `CLASH_BIN` 路径是否正确

### Q: 如何恢复默认内核？

```bash
# 删除自定义配置
sed -i '/^CLASH_BIN=/d' .env

# 或恢复原始内核文件
# 从项目仓库重新下载
```

### Q: Mihomo 与原版 Clash 配置有区别吗？

Mihomo 兼容原版配置，但新增了：
- 更多协议支持（VLESS, Hysteria 等）
- 规则集扩展
- Script 支持

详见 [Mihomo Wiki](https://wiki.metacubex.one/)
