# Hetzner Cloud Vertex

> 基于 Hetzner Cloud 的一键种子盒部署方案 —— qBittorrent 4.3.8 + Vertex + BBRx

## 📖 简介

本仓库提供了一套完整的 **cloud-init 自动化部署脚本**，用于在 Hetzner Cloud（或其他 VPS）上快速搭建高性能种子盒环境。脚本集成了 qBittorrent 高性能内核、Vertex 辅种/刷流工具、BBRx 网络优化，以及智能种子管理规则，实现开箱即用。

## ✨ 特性

- **一键部署**：通过 cloud-init 脚本自动完成全部环境搭建，无需手动干预
- **高性能内核**：使用 qBittorrent 4.3.8 + libtorrent v1.2.14 优化组合
- **Vertex 集成**：Docker host 网络模式 + privileged 权限运行，性能最大化
- **BBRx 网络优化**：内置 BBRx 拥塞控制算法，提升上传带宽利用率
- **智能删种规则**：多条件自动删种，保护磁盘空间
- **自动日志清理**：定时清理过期日志和临时文件
- **备份恢复**：支持从 GitHub 私有仓库恢复 Vertex 配置备份

## 📁 仓库结构

```
.
├── cloud-init-setup-enhanced.sh    # 主部署脚本（cloud-init）
├── rule/
│   └── delete/
│       └── 2c783f44.json           # Vertex 自动删种规则
├── script/
│   └── 05fa98a1.json               # Vertex 日志清理脚本
├── .gitignore                      # Git 忽略规则
└── README.md
```

## 🚀 快速开始

### 1. 配置参数

编辑 `cloud-init-setup-enhanced.sh` 中的全局变量：

```bash
# qBittorrent 用户名和密码
USER="admin"
PASSWORD="adminadmin"
# qBittorrent WebUI 端口和 BT 端口
PORT=8080
UP_PORT=23333
```

### 2. （可选）配置备份恢复

如需恢复之前的 Vertex 配置，填入私有仓库信息：

```bash
VERTEX_BACKUP_URL="https://raw.githubusercontent.com/<用户>/<仓库>/main/Vertex-backups.tar.gz"
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"   # GitHub Personal Access Token（repo 权限）
```

> ⚠️ **注意**：不要将包含 Token 的脚本提交到公开仓库！

### 3. 部署

在 Hetzner Cloud 创建服务器时，将脚本内容粘贴到 **Cloud-Init** 配置中，或通过 SSH 手动执行：

```bash
chmod +x cloud-init-setup-enhanced.sh
./cloud-init-setup-enhanced.sh
```

部署完成后系统会自动重启一次以应用 BBRx 优化。

### 4. 访问服务

| 服务 | 地址 | 默认端口 |
|------|------|----------|
| qBittorrent WebUI | `http://<服务器IP>:8080` | 8080 |
| Vertex WebUI | `http://<服务器IP>:3000` | 3000 |

## 📋 部署流程详解

脚本按以下 6 个阶段顺序执行：

| 阶段 | 描述 |
|------|------|
| **[1/6]** | 获取机器内存，动态计算 qBittorrent 缓存大小（内存 / 8） |
| **[2/6]** | 部署 Jerry048 主框架（qBittorrent + Vertex + BBRx） |
| **[3/6]** | 替换高性能 qBittorrent 内核（4.3.8 + libtorrent v1.2.14），修改配置 |
| **[4/6]** | 调整磁盘预留块为 1%，最大化可用空间 |
| **[5/6]** | 以 host 网络 + privileged 模式重建 Vertex Docker 容器 |
| **[6/6]** | 启用服务自启、配置定时任务（SSD TRIM + 系统清理）、安全重启 |

## 🗑️ 自动删种规则

文件：`rule/delete/2c783f44.json`

删种规则基于以下条件自动清理种子：

| 条件 | 说明 |
|------|------|
| **分享率 > 3** | 已下载的种子上传量超过下载量 3 倍时删除 |
| **磁盘空间不足** | 可用空间 < 4GB 时，删除上传速度最低的种子 |
| **保护机制** | 正在等待下载且进度为 0 的种子不会被删除 |
| **安全删除** | 保留上传速度最高的种子，只删除速度最低的 |

## 🧹 自动清理脚本

文件：`script/05fa98a1.json`

| 功能 | 说明 |
|------|------|
| 日志清理 | 自动删除 5 天前的 Vertex 日志文件 |
| 临时文件清理 | 清除 `/tmp/` 下的所有临时文件 |

## ⏰ 定时任务

脚本自动配置以下 crontab 任务：

| 时间 | 任务 |
|------|------|
| 每天凌晨 4:00 | SSD TRIM（`fstrim`），优化 SSD 性能 |
| 每周日凌晨 3:00 | 系统清理（apt clean + 日志压缩 + btmp 清空） |

## 🔧 技术栈

- **下载器**：qBittorrent 4.3.8 + libtorrent v1.2.14
- **辅种工具**：Vertex（Docker 部署）
- **网络优化**：BBRx 拥塞控制
- **系统**：Debian 10+ / Ubuntu 20.04+
- **架构支持**：x86_64 / ARM64

## 📝 日志

部署日志保存在 `/root/cloud-init-setup.log`，可通过以下命令查看：

```bash
tail -f /root/cloud-init-setup.log
```

## ⚠️ 注意事项

1. 脚本需要 **root 权限** 运行
2. 部署过程中系统会自动重启，请耐心等待（约 5-10 分钟）
3. **不要**将包含 GitHub Token 或密码的配置提交到公开仓库
4. 备份文件（`Vertex-backups-*.tar.gz`）已通过 `.gitignore` 排除
