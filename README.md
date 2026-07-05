# 服务器运维与性能优化 - 课程大作业

> **课程**: 服务器运维与性能优化 | **学期**: 2025-2026-2 | **姓名**: lk

## 任务概览（总分 100 分）

| 任务 | 内容 | 分值 | 目录 |
|------|------|------|------|
| 任务一 | 服务器运维核心理论知识 | 20 分 | [task1-theory/](task1-theory/) |
| 任务二 | Nginx+Tomcat 集群部署 | 20 分 | [task2-cluster/](task2-cluster/) |
| 任务三 | 基于 eBPF 的性能观测工具 | 40 分 | [task3-ebpf-monitor/](task3-ebpf-monitor/) |
| 任务四 | 课程大作业报告 | 20 分 | [task4-report/](task4-report/) |

## 项目统计

- **总代码量**: 6851 行（手写代码 + 文档）
- **eBPF 源代码**: 3703 行
- **监测模块**: 5 个（CPU / 内存 / 磁盘 / 文件 / 网络）
- **关键指标**: 20+ 个
- **技术栈**: eBPF + libbpf + C + Python + Docker + Prometheus + Grafana

## 代码仓库

https://github.com/lankunGitHub/-

## 快速开始

### 任务二 - 集群部署
```bash
cd task2-cluster
docker compose up -d
curl http://localhost/
```

### 任务三 - eBPF 监测工具
```bash
cd task3-ebpf-monitor
bash setup.sh          # 一键配置环境
make all               # 构建所有模块
python3 ui/monitor_ui.py  # 启动交互界面
```

## 项目结构

```
服务器运维作业/
├── task1-theory/              # 理论作答 (368 行)
│   └── 理论作答.md
├── task2-cluster/             # 集群部署 (13 文件)
│   ├── docker-compose.yml
│   ├── nginx/                 # 3种负载均衡算法配置
│   ├── webapp/                # 校园实训管理系统
│   └── stress-test/           # 压力测试脚本
├── task3-ebpf-monitor/        # eBPF监测工具 (19 源文件)
│   ├── cpu_monitor/           # CPU: 利用率/运行队列/上下文切换/频率
│   ├── mem_monitor/           # 内存: 使用率/页面错误/Swap/OOM/分配率
│   ├── disk_monitor/          # 磁盘: 读写字节/IOPS/延迟/利用率
│   ├── file_monitor/          # 文件: 打开关闭/VFS读写/缓存
│   ├── net_monitor/           # 网络: 收发字节/数据包/TCP/错误/重传
│   ├── ui/monitor_ui.py      # Python 交互界面
│   └── grafana/               # Prometheus + Grafana 配置
└── task4-report/              # 大作业报告 (606 行)
    └── 服务器运维与性能优化学习报告.md
```
