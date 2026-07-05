# Nginx + Tomcat 集群负载均衡部署项目

## 项目概述

本项目使用 Docker Compose 构建了一个包含 3 个 Tomcat 实例和 1 个 Nginx 反向代理的 Web 集群环境，演示了三种不同的负载均衡算法（轮询、最少连接、IP 哈希）在 Nginx 中的配置、使用和效果对比。

---

## 一、系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                       客户端 / 浏览器                            │
│              http://localhost:80 (宿主机端口 80)                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Nginx 反向代理                               │
│                    nginx-lb (172.28.0.10:80)                     │
│                                                                  │
│                   负载均衡算法 (可切换):                           │
│        ┌──────────────┬──────────────┬──────────────┐            │
│        │  Round Robin │  Least Conn  │   IP Hash    │            │
│        └──────┬───────┴──────┬───────┴──────┬───────┘            │
│               │              │              │                     │
│         ┌─────┴─────┐ ┌─────┴─────┐ ┌─────┴─────┐               │
│         │ 权重=1    │ │ 权重=1    │ │ 权重=1    │               │
└─────────┼───────────┼─┼───────────┼─┼───────────┼───────────────┘
          │           │ │           │ │           │
          ▼           ▼ ▼           ▼ ▼           ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Tomcat 实例1 │ │  Tomcat 实例2 │ │  Tomcat 实例3 │
│  tomcat1     │ │  tomcat2     │ │  tomcat3     │
│  172.28.0.11 │ │  172.28.0.12 │ │  172.28.0.13 │
│  端口: 8081  │ │  端口: 8082  │ │  端口: 8083  │
│  主机映射:    │ │  主机映射:    │ │  主机映射:    │
│  8081:8081   │ │  8082:8082   │ │  8083:8083   │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       └────────────────┴────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Docker 网络: cluster-net                      │
│                    子网: 172.28.0.0/16                          │
└─────────────────────────────────────────────────────────────────┘
```

### 网络端口规划

| 服务名称 | 容器名称 | 内部IP | 内部端口 | 宿主机映射 |
|---------|---------|--------|---------|-----------|
| Nginx   | nginx-lb | 172.28.0.10 | 80 | 80:80 |
| Tomcat 1 | tomcat1 | 172.28.0.11 | 8081 | 8081:8081 |
| Tomcat 2 | tomcat2 | 172.28.0.12 | 8082 | 8082:8082 |
| Tomcat 3 | tomcat3 | 172.28.0.13 | 8083 | 8083:8083 |

---

## 二、项目结构

```
task2-cluster/
├── docker-compose.yml           # Docker Compose 编排文件
├── nginx/
│   ├── nginx.conf               # Nginx 主配置（默认轮询算法）
│   ├── nginx-round-robin.conf   # 轮询算法 upstream 配置
│   ├── nginx-least-conn.conf    # 最少连接算法 upstream 配置
│   ├── nginx-ip-hash.conf       # IP 哈希算法 upstream 配置
│   └── switch-algorithm.sh      # 算法切换脚本
├── webapp/
│   ├── index.jsp                # 示例 Web 应用（显示服务器信息）
│   └── WEB-INF/
│       └── web.xml              # Web 应用配置文件
├── tomcat/
│   ├── server1.xml              # Tomcat 实例1 配置
│   ├── server2.xml              # Tomcat 实例2 配置
│   └── server3.xml              # Tomcat 实例3 配置
├── stress-test/
│   └── test.sh                  # 压力测试脚本
└── README.md                    # 本文档
```

---

## 三、快速部署

### 3.1 环境要求

- Linux 操作系统（已测试 Ubuntu 20.04+ / CentOS 7+）
- Docker Engine 20.10+ （用户需在 docker 用户组中）
- Docker Compose 2.0+

### 3.2 部署步骤

#### 步骤 1: 创建日志目录

```bash
cd /home/lk/服务器运维作业/task2-cluster
mkdir -p nginx/logs
```

#### 步骤 2: 添加脚本执行权限

```bash
chmod +x nginx/switch-algorithm.sh
chmod +x stress-test/test.sh
```

#### 步骤 3: 启动所有服务

```bash
# 在项目根目录执行
docker compose up -d

# 等待所有服务健康检查通过（可能需要 30-60 秒）
docker compose ps -a
```

**预期输出:**
```
NAME                IMAGE               COMMAND                  SERVICE             STATUS              PORTS
nginx-lb            nginx:1.25          "/docker-entrypoint.…"   nginx               running (healthy)   0.0.0.0:80->80/tcp
tomcat1             tomcat:9-jdk11      "catalina.sh run"        tomcat1             running (healthy)   0.0.0.0:8081->8081/tcp
tomcat2             tomcat:9-jdk11      "catalina.sh run"        tomcat2             running (healthy)   0.0.0.0:8082->8082/tcp
tomcat3             tomcat:9-jdk11      "catalina.sh run"        tomcat3             running (healthy)   0.0.0.0:8083->8083/tcp
```

#### 步骤 4: 验证部署

```bash
# 访问 Nginx 反向代理（负载均衡入口）
curl http://localhost:80/

# 直接访问各 Tomcat 实例（验证每个实例独立可用）
curl http://localhost:8081/
curl http://localhost:8082/
curl http://localhost:8083/
```

**验证方法:** 多次访问 `http://localhost:80/`，观察返回页面中的服务器名称是否为 tomcat1、tomcat2、tomcat3 交替出现。

#### 步骤 5: 停止服务

```bash
docker compose down
```

如需同时删除数据卷：

```bash
docker compose down -v
```

---

## 四、负载均衡算法详解

### 4.1 轮询（Round Robin）

**配置位置:** `nginx/nginx-round-robin.conf`

```
upstream tomcat_cluster {
    server 172.28.0.11:8081 weight=1 max_fails=3 fail_timeout=30s;
    server 172.28.0.12:8082 weight=1 max_fails=3 fail_timeout=30s;
    server 172.28.0.13:8083 weight=1 max_fails=3 fail_timeout=30s;
}
```

**算法原理:**
- 请求按照顺序依次分配给每个后端服务器
- 当所有权重相等时，请求完全均匀分布（1-2-3-1-2-3... 循环）
- 支持权重设置（weight 参数），权重越高的服务器分配到更多请求

**适用场景:**
- 所有后端服务器配置相同（CPU、内存、网络）
- 每个请求处理时间相近
- 无状态应用（不需要会话保持）

**优点:**
- 实现简单，无额外计算开销
- 权重相同时分发最均匀
- 不需要考虑服务器状态

**缺点:**
- 不考虑服务器当前负载
- 如果某台服务器处理请求较慢，会导致请求堆积
- 不支持会话保持

**[截图占位: 放置轮询算法下 20 次请求的分发统计截图]**

---

### 4.2 最少连接（Least Connections）

**配置位置:** `nginx/nginx-least-conn.conf`

```
upstream tomcat_cluster {
    least_conn;
    server 172.28.0.11:8081 weight=1 max_fails=3 fail_timeout=30s;
    server 172.28.0.12:8082 weight=1 max_fails=3 fail_timeout=30s;
    server 172.28.0.13:8083 weight=1 max_fails=3 fail_timeout=30s;
}
```

**算法原理:**
- Nginx 跟踪每台后端服务器的当前活跃连接数
- 新请求被分配给当前活跃连接数最少的服务器
- 能动态响应服务器负载变化

**适用场景:**
- 请求处理时间差异较大（如一些请求快、一些请求慢）
- 服务器性能不完全相同
- 长连接或 WebSocket 场景

**优点:**
- 考虑服务器当前负载状态
- 更智能地分配请求，避免过载
- 适合处理时间不均的场景

**缺点:**
- 需要维护连接计数，有轻微额外开销
- 仍然不支持会话保持
- 在请求处理时间非常均匀的场景下与轮询差异不大

**[截图占位: 放置最少连接算法下 20 次请求的分发统计截图]**

---

### 4.3 IP 哈希（IP Hash）

**配置位置:** `nginx/nginx-ip-hash.conf`

```
upstream tomcat_cluster {
    ip_hash;
    server 172.28.0.11:8081 weight=1 max_fails=3 fail_timeout=30s;
    server 172.28.0.12:8082 weight=1 max_fails=3 fail_timeout=30s;
    server 172.28.0.13:8083 weight=1 max_fails=3 fail_timeout=30s;
}
```

**算法原理:**
- 根据客户端 IP 地址的前三个八位组计算哈希值
- 同一客户端 IP 的请求始终被发送到同一台后端服务器
- 实现了天然的会话保持（Session Stickiness）

**适用场景:**
- 需要会话保持的应用（如购物车、登录状态）
- 后端没有共享会话存储
- 客户端 IP 相对分散

**优点:**
- 天然实现会话保持，无需应用层改造
- 同一客户端请求始终路由到同一服务器
- 对客户端透明

**缺点:**
- 负载可能不均衡（某些网段集中到同一服务器）
- 添加或移除后端服务器会重新哈希，影响大量会话
- 如果客户端通过代理访问，所有用户 IP 相同，会集中到一台服务器

**[截图占位: 放置 IP 哈希算法下 20 次请求的分发统计截图]**

---

## 五、切换负载均衡算法

### 方法一：使用切换脚本（推荐）

```bash
# 查看当前状态
cd /home/lk/服务器运维作业/task2-cluster
./nginx/switch-algorithm.sh status

# 切换到轮询算法
./nginx/switch-algorithm.sh round-robin

# 切换到最少连接算法
./nginx/switch-algorithm.sh least-conn

# 切换到 IP 哈希算法
./nginx/switch-algorithm.sh ip-hash
```

脚本会自动执行以下操作：
1. 备份当前 nginx.conf
2. 使用对应算法的 upstream 配置替换原有配置
3. 执行 `nginx -t` 测试配置语法
4. 执行 `nginx -s reload` 热重载配置（无需重启容器）

### 方法二：手动切换

```bash
# 1. 复制对应算法的 upstream 配置替换 nginx.conf
cp nginx/nginx-round-robin.conf nginx/nginx.conf

# 2. 测试配置语法
docker exec nginx-lb nginx -t

# 3. 热重载配置
docker exec nginx-lb nginx -s reload
```

---

## 六、观察负载均衡效果

### 6.1 通过 Web 页面观察

访问 `http://localhost:80/`，页面会显示处理当前请求的 Tomcat 服务器信息：

| 显示字段 | 说明 |
|---------|------|
| 当前服务器 | tomcat1 / tomcat2 / tomcat3 |
| 服务器主机名 | 容器 hostname |
| 服务器 IP 地址 | 容器内部 IP（172.28.0.11/12/13） |
| 服务器端口 | 8081 / 8082 / 8083 |
| 当前时间 | 精确到毫秒的服务器时间 |
| 会话 ID | 当前会话的唯一标识 |
| 请求方式 | GET/POST 等 |
| 客户端 IP | 真实客户端 IP（通过 X-Forwarded-For 获取）|

多次刷新页面即可直观看到请求被分发到不同的 Tomcat 实例。

### 6.2 通过 Nginx 日志观察

```bash
# 查看负载均衡访问日志（包含上游服务器信息）
docker exec nginx-lb cat /var/log/nginx/loadbalance.log

# 日志格式示例:
# 2026-07-05T10:30:15+08:00 | 172.28.0.1 | 172.28.0.11:8081 | 200 | GET / HTTP/1.1 | 200 | 2345 | 0.032
# 2026-07-05T10:30:15+08:00 | 172.28.0.1 | 172.28.0.12:8082 | 200 | GET / HTTP/1.1 | 200 | 2345 | 0.028
# 2026-07-05T10:30:16+08:00 | 172.28.0.1 | 172.28.0.13:8083 | 200 | GET / HTTP/1.1 | 200 | 2345 | 0.031
```

字段说明：`时间 | 客户端IP | 上游服务器 | 上游状态 | 请求 | 响应状态 | 响应大小 | 响应时间`

### 6.3 通过 HTTP 响应头观察

```bash
# 查看响应头中的 X-Upstream-Server 字段
curl -I http://localhost:80/
```

响应头示例：
```
HTTP/1.1 200 OK
X-Upstream-Server: 172.28.0.11:8081
X-Upstream-Status: 200
```

### 6.4 通过 curl 循环快速测试

```bash
# 连续访问 20 次，提取上游服务器信息
for i in $(seq 1 20); do
  curl -s -I http://localhost:80/ | grep -i "x-upstream-server"
done
```

---

## 七、运行压力测试

### 7.1 使用内置测试脚本

```bash
cd /home/lk/服务器运维作业/task2-cluster

# 运行完整测试（交互式菜单）
./stress-test/test.sh
```

测试脚本提供以下选项：

1. **完整测试** - 执行所有 4 项测试并生成报告
2. **仅测试顺序请求分发** - 测试负载均衡是否均匀分发
3. **仅测试并发请求** - 模拟多用户并发访问
4. **仅测试会话保持** - 验证会话保持效果
5. **仅测试响应时间** - 测量响应时间统计特征
6. **一键测试所有三种算法** - 自动切换算法并分别测试对比

### 7.2 使用手动测试命令

```bash
# 快速测试 - 连续 20 次请求查看分布
# 轮询算法下，3台Tomcat应均匀分布

# 测试 IP Hash 的会话保持
for i in $(seq 1 10); do
  curl -s http://localhost:80/ | grep -o "tomcat[0-9]"
done
# 同一客户端应该始终返回同一台服务器

# 测试并发性能 (需安装 apache2-utils)
# sudo apt install -y apache2-utils   # Debian/Ubuntu
# sudo yum install -y httpd-tools     # CentOS/RHEL
ab -n 1000 -c 50 http://localhost:80/
```

### 7.3 测试结果分析

测试结果保存在 `stress-test/results/` 目录下，包含以下文件：

| 文件 | 说明 |
|------|------|
| `seq_detail_算法_时间.txt` | 顺序请求的详细分发记录 |
| `con_detail_算法_时间.txt` | 并发请求的详细记录 |
| `session_detail_算法_时间.txt` | 会话保持测试记录 |
| `算法_时间.txt` | 汇总分析报告 |

**[截图占位: 放置测试脚本运行结果截图]**

---

## 八、三种算法对比分析

| 对比维度 | 轮询 (Round Robin) | 最少连接 (Least Conn) | IP 哈希 (IP Hash) |
|---------|-------------------|---------------------|------------------|
| **请求分发均匀度** | 高（权重相同时完全均匀） | 中（受当前连接数影响） | 低（依赖 IP 分布） |
| **考虑服务器负载** | 否 | 是 | 否 |
| **会话保持** | 不支持 | 不支持 | 支持 |
| **实现复杂度** | 低（默认算法） | 中 | 低 |
| **计算开销** | 无 | 低 | 中（需哈希计算） |
| **适用场景** | 同等性能服务器，请求处理时间相近 | 性能不均，请求处理时间差异大 | 需要会话粘性，无共享会话存储 |
| **动态扩缩容影响** | 低 | 低 | 高（重新哈希） |
| **最佳实践建议** | 入门首选，通用场景 | 推荐用于生产环境 | 特定场景（需会话保持） |

### 推荐策略

1. **通用场景:** 使用最少连接（least_conn）算法，兼顾负载均衡与性能
2. **简单场景:** 使用轮询（round-robin），配置简单，行为可预测
3. **需要会话保持:** 使用 IP 哈希（ip_hash），但注意负载不均的风险
4. **生产环境最佳实践:** 最少连接 + 应用层共享 Session（如 Redis）

---

## 九、运维命令参考

### 常用 Docker Compose 命令

```bash
# 启动所有服务
docker compose up -d

# 停止所有服务
docker compose down

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f nginx
docker compose logs -f tomcat1
docker compose logs -f

# 重启特定服务（不中断其他服务）
docker compose restart nginx

# 重新构建并启动（修改配置后使用）
docker compose up -d --force-recreate

# 查看容器资源使用
docker stats
```

### Nginx 调试命令

```bash
# 测试配置语法
docker exec nginx-lb nginx -t

# 热重载配置（不中断服务）
docker exec nginx-lb nginx -s reload

# 查看连接状态
curl http://localhost:80/nginx_status

# 查看健康检查状态
curl http://localhost:80/health
```

---

## 十、常见问题排查

### Q1: 启动后服务状态不健康

**原因:** Tomcat 启动需要时间，健康检查可能在应用完全就绪前触发。

**解决:** 等待 60 秒后再次检查：
```bash
sleep 60 && docker compose ps
```

### Q2: 修改配置后不生效

**原因:** Nginx 配置缓存，需要重新加载。

**解决:**
```bash
docker exec nginx-lb nginx -s reload
```

### Q3: 端口被占用

**原因:** 宿主机上已有服务占用了 80/8081/8082/8083 端口。

**解决:** 修改 `docker-compose.yml` 中的端口映射，或停止占用端口的服务。

### Q4: 容器无法访问网络

**原因:** Docker 网络未正确创建。

**解决:**
```bash
# 清理并重建网络
docker compose down
docker network rm task2-cluster_cluster-net 2>/dev/null || true
docker compose up -d
```

### Q5: 找不到 docker compose 命令

**原因:** 旧版本 Docker 使用 `docker-compose`（带横线）。

**解决:**
```bash
# 尝试旧版命令
docker-compose up -d

# 或安装 Docker Compose 插件
sudo apt install docker-compose-plugin  # Debian/Ubuntu
```

---

## 十一、需要截图记录的内容

建议在实验报告中包含以下截图：

1. **部署完成截图:** `docker compose ps` 命令输出，显示所有服务健康运行
2. **Web 页面截图:** 浏览器访问 `http://localhost:80/` 显示 Tomcat 服务器信息
3. **轮询算法测试截图:** 轮询算法下连续 20 次请求的分发结果
4. **最少连接算法测试截图:** 最少连接算法下连续 20 次请求的分发结果
5. **IP 哈希算法测试截图:** IP 哈希算法下连续 20 次请求的分发结果（同一客户端 IP）
6. **会话保持测试截图:** IP 哈希算法下连续请求均指向同一台服务器
7. **测试脚本运行截图:** 压力测试脚本运行过程和结果输出
8. **Nginx 日志截图:** 负载均衡日志文件内容，显示请求分发到不同 Tomcat
9. **Nginx 状态页面截图:** `/nginx_status` 页面显示的活跃连接信息

---

## 十二、参考资源

- [Nginx 负载均衡官方文档](https://nginx.org/en/docs/http/load_balancing.html)
- [Tomcat 9 配置文档](https://tomcat.apache.org/tomcat-9.0-doc/)
- [Docker Compose 官方文档](https://docs.docker.com/compose/)
- Nginx Upstream 模块指令说明
- Apache Bench 压力测试工具

---

## 版权信息

本项目为服务器运维课程作业 Task 2，用于教学演示 Nginx 反向代理与 Tomcat 集群的负载均衡技术。
