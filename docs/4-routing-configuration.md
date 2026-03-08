# 分流配置指南

实现特定流量走指定代理，如公司内网走公司代理、其他流量走个人订阅。

## 快速配置

### 1. 环境变量

编辑 `.env`：

```bash
export WORK_PROXY_HOST='代理服务器地址'
export WORK_PROXY_PORT='代理端口'
export WORK_PROXY_USER='用户名'
export WORK_PROXY_PASS='密码'
```

### 2. 分流配置

创建 `conf/routing-config.yaml`：

```yaml
port: 7890
socks-port: 7891
mixed-port: 7892
allow-lan: false
mode: rule
log-level: info

dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 119.29.29.29

proxies:
  - name: work-proxy
    type: socks5
    server: ${WORK_PROXY_HOST}
    port: ${WORK_PROXY_PORT}
    username: ${WORK_PROXY_USER}
    password: ${WORK_PROXY_PASS}

proxy-providers:
  personal:
    type: http
    url: https://your-subscription-url&flag=clash
    interval: 3600
    path: ./proxy-providers/personal.yaml

proxy-groups:
  - name: work
    type: select
    proxies:
      - work-proxy

  - name: personal
    type: select
    use:
      - personal

rules:
  - IP-CIDR,10.200.0.0/16,work
  - DOMAIN-SUFFIX,company.com,work
  - MATCH,personal
```

### 3. 添加订阅

```bash
just add routing local:/path/to/routing-config.yaml
just use routing
```

---

## 规则类型

### IP-CIDR

```yaml
rules:
  - IP-CIDR,192.168.1.100/32,work    # 单个 IP
  - IP-CIDR,10.0.0.0/8,work          # IP 段
```

### DOMAIN

```yaml
rules:
  - DOMAIN,gitlab.company.com,work       # 精确匹配
  - DOMAIN-SUFFIX,company.com,work       # 后缀匹配
  - DOMAIN-KEYWORD,analytics,REJECT      # 关键字
```

### GEOIP

```yaml
rules:
  - GEOIP,CN,direct
  - GEOIP,US,personal
```

### 最终规则

`MATCH` 必须放最后：

```yaml
rules:
  - MATCH,personal
```

---

## 代理组类型

| 类型 | 说明 |
|------|------|
| `select` | 手动选择 |
| `url-test` | 自动选最低延迟 |
| `fallback` | 按顺序尝试 |
| `load-balance` | 负载均衡 |

```yaml
proxy-groups:
  - name: auto
    type: url-test
    use:
      - personal
    url: http://www.gstatic.com/generate_204
    interval: 300
```

---

## SSH 代理配置

SSH 不走 HTTP 代理，需配置 SOCKS5。

### 安装依赖

```bash
apt-get install -y connect-proxy  # Debian/Ubuntu
yum install -y connect-proxy      # CentOS/RHEL
```

### SSH Config

编辑 `~/.ssh/config`：

```
# 公司内网（走代理）
Host gitlab.company.com
    HostName gitlab.company.com
    User git
    ProxyCommand connect -S 127.0.0.1:7890 %h %p

# 直连
Host github.com
    HostName github.com
    User git
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `-S 127.0.0.1:7890` | SOCKS5 代理地址 |
| `%h` | 目标主机 |
| `%p` | 目标端口 |

### 临时使用

```bash
ssh -o ProxyCommand="connect -S 127.0.0.1:7890 %h %p" user@10.200.1.100
```

---

## 调试

```bash
# 查看规则
grep -A 20 "^rules:" conf/config.yaml

# API 查询
curl -s http://127.0.0.1:9090/rules \
  -H "Authorization: Bearer <secret>"
```

---

## 注意事项

1. 规则从上到下匹配，第一个匹配生效
2. `MATCH` 必须放最后
3. 敏感信息用环境变量，不要硬编码
4. 配置文件不要提交 git（已在 `.gitignore`）
