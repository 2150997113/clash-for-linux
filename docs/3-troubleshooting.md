# 故障排查指南

## 1. 服务启动

### 服务立即退出

```bash
# 查看日志
journalctl -u clash-for-linux.service -n 100

# 检查配置
ls -la /opt/clash-for-linux/conf/config.yaml
```

| 原因 | 解决 |
|------|------|
| `CLASH_URL` 未配置 | 编辑 `.env` |
| 订阅不可访问 | 检查网络 |
| 配置语法错误 | `clash -t -f config.yaml` |
| 二进制无权限 | `chmod +x libs/clash/clash-linux-*` |

### 订阅下载失败

```bash
# 测试订阅
curl -I "https://your-subscription-url"

# 特定 User-Agent
curl -H "User-Agent: Clash" "https://your-subscription-url"
```

在 `.env` 中设置：
```bash
export CLASH_HEADERS='User-Agent: ClashforWindows/0.20.39'
```

### 端口被占用

```bash
ss -tlnp | grep 7890
lsof -i :7890
```

解决：
```bash
# 修改端口
export CLASH_HTTP_PORT=17890

# 或自动分配
export CLASH_HTTP_PORT=auto
```

---

## 2. API 问题

### 无法访问

```bash
curl http://127.0.0.1:9090/api/version
ss -tlnp | grep 9090
```

| 原因 | 解决 |
|------|------|
| 服务未运行 | `make start` |
| external-controller 配置错误 | 检查 `conf/config.yaml` |

### 认证失败 (403)

```bash
# 查看 secret
grep secret /opt/clash-for-linux/conf/config.yaml

# 测试认证
curl -H "Authorization: Bearer YOUR_SECRET" http://127.0.0.1:9090/api/proxies
```

重新生成：
```bash
openssl rand -hex 32
# 更新 config.yaml 中的 secret
```

---

## 3. 代理问题

### 代理不生效

```bash
# 检查环境变量
env | grep -i proxy

# 检查端口
ss -tlnp | grep 7890

# 测试代理
curl -x http://127.0.0.1:7890 https://google.com -I
```

确保已加载环境变量：
```bash
source /etc/profile.d/clash-for-linux.sh
proxy_on
```

### 节点超时

```bash
tail -f /opt/clash-for-linux/logs/clash.log
curl -x socks5://127.0.0.1:7891 https://api.ipify.org
```

| 原因 | 解决 |
|------|------|
| 节点失效 | `make update` |
| 协议不支持 | 确认使用 Mihomo |

---

## 4. GeoIP/GeoSite

### GeoSite.dat 损坏

```bash
rm -f /opt/clash-for-linux/conf/GeoSite.dat
wget -O /opt/clash-for-linux/conf/GeoSite.dat \
  "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
make restart
```

### Country.mmdb 缺失

```bash
wget -O /opt/clash-for-linux/volumes/geoip/Country.mmdb \
  "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
```

---

## 5. 调试

### 前台运行

```bash
SAFE_PATHS=/opt/clash-for-linux \
  ./libs/clash/clash-linux-amd64 \
  -f conf/config.yaml -d conf
```

### 测试配置

```bash
SAFE_PATHS=/opt/clash-for-linux \
  ./libs/clash/clash-linux-amd64 -t -f conf/config.yaml
```

### 查看日志

```bash
journalctl -u clash-for-linux.service -f
tail -f /opt/clash-for-linux/logs/clash.log
```

---

## 6. 恢复

### 重置配置

```bash
cp /opt/clash-for-linux/conf/config.yaml /opt/clash-for-linux/conf/config.yaml.bak
make update
make restart
```

### 完全重装

```bash
sudo make uninstall
rm -rf /opt/clash-for-linux/{conf,logs,temp}/*
sudo make install
```

---

## 7. 获取帮助

1. 查看文档：`docs/` 目录
2. 提交 Issue：https://github.com/wnlen/clash-for-linux/issues
3. 提供信息：系统版本、CPU 架构、错误日志、配置文件（脱敏）
