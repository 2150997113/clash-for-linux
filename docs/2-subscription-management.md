# 多订阅管理

## 1. 功能概述

维护多个订阅地址，快速切换，适用于工作/个人订阅分离、主备切换等场景。

### 命令

```bash
clashctl sub add <name> <url> [headers]   # 添加
clashctl sub del <name>                   # 删除
clashctl sub use <name>                   # 切换
clashctl sub update [name]                # 更新
clashctl sub list                         # 列出
clashctl sub log                          # 更新日志
```

---

## 2. 数据结构

### subscriptions.list

路径: `conf/subscriptions.list`

```
name|url|headers|updated
office|https://sub1.example.com|User-Agent: Clash|2025-01-15T10:00:00Z
personal|https://sub2.example.com|-|-
```

| 字段 | 说明 |
|------|------|
| name | 订阅名称（唯一标识） |
| url | 订阅地址 |
| headers | 请求头（可选，`-` 表示无） |
| updated | 最后更新时间 |

### .env 环境变量

| 变量 | 说明 |
|------|------|
| `CLASH_URL` | 当前激活的订阅地址 |
| `CLASH_HEADERS` | 当前订阅请求头 |
| `CLASH_SUBSCRIPTION` | 当前订阅名称 |

---

## 3. 命令详解

### sub add

```bash
clashctl sub add office "https://sub.example.com" "User-Agent: Clash"
```

- 检查名称是否重复
- 追加写入 `subscriptions.list`

### sub use

```bash
clashctl sub use office
```

- 查找订阅记录
- 更新 `.env` 中的 `CLASH_URL`、`CLASH_HEADERS`、`CLASH_SUBSCRIPTION`
- **不会自动更新配置**，需执行 `restart` 或 `update`

### sub update

```bash
clashctl sub update office
# 或更新当前订阅
clashctl sub update
```

- 切换到指定订阅
- 下载最新配置
- 更新时间戳

### sub list

```bash
clashctl sub list
# NAME       ACTIVE  URL
# office     yes     https://sub1.example.com
# personal   no      https://sub2.example.com
```

---

## 4. 流程

### 切换订阅

```
sub use office
    │
    ▼
查找订阅记录 ──→ 未找到，退出
    │
    ▼
更新 .env (CLASH_URL, CLASH_HEADERS, CLASH_SUBSCRIPTION)
    │
    ▼
提示执行 restart 或 update
```

### 更新订阅

```
sub update office
    │
    ▼
sub use office (切换)
    │
    ▼
执行 update.sh (下载配置)
    │
    ▼
更新时间戳
```

---

## 5. 使用示例

```bash
# 添加订阅
clashctl sub add office "https://sub1.example.com" "User-Agent: Clash"
clashctl sub add personal "https://sub2.example.com"

# 查看列表
clashctl sub list

# 切换并更新
clashctl sub use office
clashctl sub update
clashctl restart

# 查看更新日志
clashctl sub log
```

---

## 6. 错误处理

| 错误 | 原因 | 解决 |
|------|------|------|
| `未找到订阅: xxx` | 名称不存在 | `sub list` 查看 |
| `订阅已存在: xxx` | 重复添加 | 使用其他名称 |
| `未指定订阅名称` | 更新时无激活订阅 | 指定名称或先切换 |

---

## 7. 设计说明

### 为何用纯文本？

无依赖、易读、易备份、版本控制友好。订阅数量少时查询效率可忽略。

### 为何切换后不自动更新？

- 避免意外切换导致服务中断
- 用户可能只想切换但不立即应用
- 与 `set-url` 行为一致
