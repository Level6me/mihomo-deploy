# Mihomo 一键部署脚本

适用于树莓派 (Raspbian/Debian) 的 Mihomo (Clash.Meta) 代理一键部署工具。

## 功能特性

- **Trojan 协议支持** - 支持 Trojan 节点配置
- **大陆白名单模式** - 国内直连，国外走代理
- **Web 管理面板** - 内置 MetaCubeXD 面板，打开即连接
- **GeoIP 规则** - 自动下载并配置 GeoIP 数据
- **systemd 服务** - 开机自启，自动重启
- **本地缓存** - 解决 GitHub 下载慢的问题

## 使用方法

### 一键部署（推荐）

```bash
curl -sSL -o /tmp/deploy.sh https://raw.githubusercontent.com/Level6me/mihomo-deploy/main/deploy.sh && sudo bash /tmp/deploy.sh
```

或者：

```bash
wget -qO /tmp/deploy.sh https://raw.githubusercontent.com/Level6me/mihomo-deploy/main/deploy.sh && sudo bash /tmp/deploy.sh
```

### 本地运行

```bash
./deploy.sh
```

脚本会交互式询问：
- 树莓派 IP、用户名、密码
- Trojan 节点信息（服务器、端口、密码）
- 代理模式（全局/白名单/仅代理）

## 部署完成后

- **代理端口**: `7890` (HTTP/SOCKS5)
- **Web 面板**: `http://<树莓派IP>:9090/ui`
- **API 端口**: `9090`

## 代理模式

1. **全局代理** - 所有流量走代理
2. **大陆白名单** - 国内直连，国外走代理（推荐）
3. **仅 HTTP/SOCKS 代理** - 不接管系统流量

## 管理命令

```bash
# 查看状态
sudo systemctl status mihomo

# 重启服务
sudo systemctl restart mihomo

# 查看日志
sudo journalctl -u mihomo -f
```

## 配置文件

- 主配置: `/etc/mihomo/config.yaml`
- Web 面板: `/etc/mihomo/ui/`

## 依赖

- `sshpass` - SSH 密码登录
- `curl` - 下载文件
- `scp` - 传输文件

## 注意事项

- 脚本会在本地下载 Mihomo 和 GeoIP 数据，然后传输到树莓派
- 首次运行需要一些时间下载依赖
- Web 面板已配置默认后端地址，打开即自动连接
