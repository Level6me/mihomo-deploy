#!/bin/bash
# Mihomo (Clash.Meta) 本地一键部署脚本
# 支持 Trojan 协议 + 大陆白名单 + Web 管理面板
# 适用于树莓派 (Raspbian/Debian armv7l)
# 日期: 2026-07-18

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 运行此脚本"
        echo "用法: sudo bash deploy.sh"
        exit 1
    fi
}

# 检查依赖
check_deps() {
    log_info "检查依赖..."
    
    # 更新包列表（静默）
    apt-get update -qq 2>/dev/null || true
    
    # 需要安装的包列表
    local packages=()
    
    # 检查各个命令
    if ! command -v curl &> /dev/null; then
        packages+=("curl")
    fi
    
    if ! command -v wget &> /dev/null; then
        packages+=("wget")
    fi
    
    if ! command -v unzip &> /dev/null; then
        packages+=("unzip")
    fi
    
    if ! command -v gunzip &> /dev/null; then
        packages+=("gzip")
    fi
    
    if ! command -v ip &> /dev/null; then
        packages+=("iproute2")
    fi
    
    if ! command -v hostname &> /dev/null; then
        packages+=("hostname")
    fi
    
    # 安装缺失的包
    if [ ${#packages[@]} -gt 0 ]; then
        log_info "安装依赖: ${packages[*]}"
        apt-get install -y -qq "${packages[@]}"
        log_success "依赖安装完成"
    else
        log_success "所有依赖已安装"
    fi
    
    # 检查 systemd
    if ! command -v systemctl &> /dev/null; then
        log_error "此系统不支持 systemd，无法部署"
        exit 1
    fi
}

# 交互式输入
input_config() {
    echo ""
    echo "=========================================="
    echo "  Mihomo 本地一键部署"
    echo "  Trojan + 大陆白名单 + Web 面板"
    echo "=========================================="
    echo ""
    
    echo -e "${YELLOW}=== Trojan 节点 ===${NC}"
    read -p "服务器地址: " TROJAN_SERVER
    [ -z "$TROJAN_SERVER" ] && { log_error "服务器地址不能为空"; exit 1; }
    
    read -p "端口: " TROJAN_PORT
    [ -z "$TROJAN_PORT" ] && { log_error "端口不能为空"; exit 1; }
    
    read -sp "密码: " TROJAN_PASS
    echo ""
    [ -z "$TROJAN_PASS" ] && { log_error "密码不能为空"; exit 1; }
    
    read -p "节点名称 [US-ABAB]: " NODE_NAME
    NODE_NAME=${NODE_NAME:-US-ABAB}
    
    echo ""
    echo -e "${YELLOW}=== 代理模式 ===${NC}"
    echo "1) 全局代理 - 所有流量走代理"
    echo "2) 大陆白名单 - 国内直连，国外走代理（推荐）"
    echo "3) 仅 HTTP/SOCKS 代理 - 不接管系统流量"
    read -p "选择 [2]: " PROXY_MODE
    PROXY_MODE=${PROXY_MODE:-2}
    
    echo ""
    echo "=========================================="
    echo "  配置确认"
    echo "=========================================="
    echo "Trojan: ${TROJAN_SERVER}:${TROJAN_PORT}"
    case $PROXY_MODE in
        1) echo "模式: 全局代理" ;;
        2) echo "模式: 大陆白名单（推荐）" ;;
        3) echo "模式: HTTP/SOCKS 代理" ;;
    esac
    echo "=========================================="
    read -p "确认? (y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_info "已取消"
        exit 0
    fi
}

# 获取本机 IP
get_local_ip() {
    ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}'
}

# 安装 Mihomo
install_mihomo() {
    log_info "安装 Mihomo..."
    
    local version="v1.19.28"
    local arch=$(uname -m)
    local mihomo_arch="armv7"
    
    case $arch in
        armv7l|armv7) mihomo_arch="armv7" ;;
        aarch64) mihomo_arch="arm64" ;;
        x86_64) mihomo_arch="amd64" ;;
        *) log_error "不支持的架构: $arch"; exit 1 ;;
    esac
    
    local url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/mihomo-linux-${mihomo_arch}-${version}.gz"
    
    log_info "下载 Mihomo ($mihomo_arch)..."
    cd /tmp
    curl -L -o mihomo.gz "$url"
    gunzip -f mihomo.gz
    chmod +x mihomo
    mv mihomo /usr/local/bin/
    
    local ver=$(/usr/local/bin/mihomo -v)
    log_success "安装完成: $ver"
}

# 下载 GeoIP 数据
download_geodata() {
    log_info "下载 GeoIP 数据..."
    
    mkdir -p /etc/mihomo
    local base="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"
    
    cd /etc/mihomo
    curl -L -o geoip.dat "$base/geoip-lite.dat"
    curl -L -o geosite.dat "$base/geosite-lite.dat"
    curl -L -o country.mmdb "$base/country-lite.mmdb"
    
    log_success "GeoIP 数据下载完成"
}

# 下载 Web 面板
download_webui() {
    log_info "下载 Web 管理面板..."
    
    cd /tmp
    if [ -f metacubexd.zip ]; then
        rm -rf metacubexd-gh-pages
    fi
    
    curl -L -o metacubexd.zip "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
    unzip -q metacubexd.zip
    
    mkdir -p /etc/mihomo/ui
    cp -r metacubexd-gh-pages/* /etc/mihomo/ui/
    chmod -R 755 /etc/mihomo/ui
    
    log_success "面板下载完成"
}

# 写入配置
write_config() {
    log_info "写入配置文件..."
    
    local mode="rule"
    case $PROXY_MODE in
        1) mode="global" ;;
        2) mode="rule" ;;
        3) mode="rule" ;;
    esac
    
    local local_ip=$(get_local_ip)
    
    cat > /etc/mihomo/config.yaml << CONF
# Mihomo 配置 - Trojan 大陆白名单模式
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: $mode
log-level: info
external-controller: 0.0.0.0:9090
external-ui: /etc/mihomo/ui

unified-delay: true
tcp-concurrent: true

geodata-mode: true
geox-url:
  geoip: "file:///etc/mihomo/geoip.dat"
  geosite: "file:///etc/mihomo/geosite.dat"
  mmdb: "file:///etc/mihomo/country.mmdb"

find-process-mode: strict

profile:
  store-selected: true
  store-fake-ip: true

sniffer:
  enable: true
  sniff:
    TLS:
      ports: [443, 8443]
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true

dns:
  enable: true
  ipv6: false
  prefer-h3: true
  listen: "0.0.0.0:1053"
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - "*.lan"
    - "*.local"
    - "*.localhost"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "dns.msftncsi.com"
    - "time.*.com"
    - "time.*.gov"
    - "time.*.edu.cn"
    - "ntp.*.com"
    - "+.pool.ntp.org"
    - "time1.cloud.tencent.com"
    - "localhost.ptlogin2.qq.com"
    - "localhost.sec.qq.com"
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - "https://dns.alidns.com/dns-query"
    - "https://doh.pub/dns-query"

proxies:
  - name: "$NODE_NAME"
    type: trojan
    server: $TROJAN_SERVER
    port: $TROJAN_PORT
    password: $TROJAN_PASS
    sni: $TROJAN_SERVER
    skip-cert-verify: true
    udp: true
    client-fingerprint: chrome

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - "$NODE_NAME"
      - DIRECT

  - name: "Streaming"
    type: select
    proxies:
      - "Proxy"
      - "$NODE_NAME"

  - name: "AI"
    type: select
    proxies:
      - "Proxy"
      - "$NODE_NAME"

rules:
  # 本地/局域网直连
  - DOMAIN-SUFFIX,local,DIRECT
  - DOMAIN-SUFFIX,localhost,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT

  # AI 服务
  - DOMAIN-SUFFIX,openai.com,Proxy
  - DOMAIN-SUFFIX,ai.com,Proxy
  - DOMAIN-SUFFIX,chatgpt.com,Proxy
  - DOMAIN-SUFFIX,oaistatic.com,Proxy
  - DOMAIN-SUFFIX,oaiusercontent.com,Proxy
  - DOMAIN-SUFFIX,anthropic.com,Proxy
  - DOMAIN-SUFFIX,claude.ai,Proxy

  # 流媒体
  - DOMAIN-SUFFIX,youtube.com,Streaming
  - DOMAIN-SUFFIX,googlevideo.com,Streaming
  - DOMAIN-SUFFIX,ytimg.com,Streaming
  - DOMAIN-SUFFIX,netflix.com,Streaming
  - DOMAIN-SUFFIX,nflxvideo.net,Streaming
  - DOMAIN-SUFFIX,twitchcdn.net,Streaming
  - DOMAIN-SUFFIX,twitch.tv,Streaming

  # 国外服务
  - DOMAIN-SUFFIX,google.com,Proxy
  - DOMAIN-SUFFIX,google.com.hk,Proxy
  - DOMAIN-SUFFIX,gstatic.com,Proxy
  - DOMAIN-SUFFIX,googleapis.com,Proxy
  - DOMAIN-SUFFIX,github.com,Proxy
  - DOMAIN-SUFFIX,githubusercontent.com,Proxy
  - DOMAIN-SUFFIX,github.io,Proxy
  - DOMAIN-SUFFIX,twitter.com,Proxy
  - DOMAIN-SUFFIX,x.com,Proxy
  - DOMAIN-SUFFIX,twimg.com,Proxy
  - DOMAIN-SUFFIX,telegram.org,Proxy
  - DOMAIN-SUFFIX,t.me,Proxy
  - DOMAIN-SUFFIX,wikipedia.org,Proxy
  - DOMAIN-SUFFIX,wikimedia.org,Proxy
  - DOMAIN-SUFFIX,facebook.com,Proxy
  - DOMAIN-SUFFIX,instagram.com,Proxy
  - DOMAIN-SUFFIX,whatsapp.com,Proxy
  - DOMAIN-SUFFIX,amazon.com,Proxy
  - DOMAIN-SUFFIX,amazonaws.com,Proxy
  - DOMAIN-SUFFIX,cloudfront.net,Proxy
  - DOMAIN-SUFFIX,spotify.com,Proxy
  - DOMAIN-SUFFIX,redd.it,Proxy
  - DOMAIN-SUFFIX,reddit.com,Proxy
  - DOMAIN-SUFFIX,redditstatic.com,Proxy
  - DOMAIN-SUFFIX,discord.com,Proxy
  - DOMAIN-SUFFIX,discordapp.com,Proxy

  # 国内直连
  - DOMAIN-SUFFIX,cn,DIRECT
  - DOMAIN-SUFFIX,baidu.com,DIRECT
  - DOMAIN-SUFFIX,bdstatic.com,DIRECT
  - DOMAIN-SUFFIX,bdimg.com,DIRECT
  - DOMAIN-SUFFIX,qq.com,DIRECT
  - DOMAIN-SUFFIX,weixin.qq.com,DIRECT
  - DOMAIN-SUFFIX,wechat.com,DIRECT
  - DOMAIN-SUFFIX,tencent.com,DIRECT
  - DOMAIN-SUFFIX,taobao.com,DIRECT
  - DOMAIN-SUFFIX,tmall.com,DIRECT
  - DOMAIN-SUFFIX,alicdn.com,DIRECT
  - DOMAIN-SUFFIX,alibaba.com,DIRECT
  - DOMAIN-SUFFIX,aliyun.com,DIRECT
  - DOMAIN-SUFFIX,jd.com,DIRECT
  - DOMAIN-SUFFIX,360buyimg.com,DIRECT
  - DOMAIN-SUFFIX,bilibili.com,DIRECT
  - DOMAIN-SUFFIX,bilivideo.com,DIRECT
  - DOMAIN-SUFFIX,hdslb.com,DIRECT
  - DOMAIN-SUFFIX,zhihu.com,DIRECT
  - DOMAIN-SUFFIX,douyin.com,DIRECT
  - DOMAIN-SUFFIX,tiktokv.com,DIRECT
  - DOMAIN-SUFFIX,bytedance.com,DIRECT
  - DOMAIN-SUFFIX,pstatp.com,DIRECT
  - DOMAIN-SUFFIX,snssdk.com,DIRECT
  - DOMAIN-SUFFIX,weibo.com,DIRECT
  - DOMAIN-SUFFIX,sinaimg.cn,DIRECT
  - DOMAIN-SUFFIX,xiaomi.com,DIRECT
  - DOMAIN-SUFFIX,mi.com,DIRECT
  - DOMAIN-SUFFIX,163.com,DIRECT
  - DOMAIN-SUFFIX,126.com,DIRECT
  - DOMAIN-SUFFIX,meituan.com,DIRECT
  - DOMAIN-SUFFIX,dianping.com,DIRECT
  - DOMAIN-SUFFIX,pinduoduo.com,DIRECT
  - DOMAIN-SUFFIX,apple.com,DIRECT
  - DOMAIN-SUFFIX,icloud.com,DIRECT
  - DOMAIN-SUFFIX,microsoft.com,DIRECT
  - DOMAIN-SUFFIX,windows.com,DIRECT
  - DOMAIN-SUFFIX,office.com,DIRECT

  # GeoIP 大陆直连
  - GEOIP,CN,DIRECT

  # 兜底走代理
  - MATCH,Proxy
CONF
    log_success "配置写入完成"
}

# 写入 Web 面板配置
write_webui_config() {
    log_info "配置 Web 面板..."
    
    local local_ip=$(get_local_ip)
    
    cat > /etc/mihomo/ui/config.js << CONF
window.__METACUBEXD_CONFIG__ = {
  defaultBackendURL: "http://$local_ip:9090",
  githubToken: "",
}
CONF
    log_success "面板配置完成"
}

# 创建 systemd 服务
create_service() {
    log_info "创建 systemd 服务..."
    
    cat > /etc/systemd/system/mihomo.service << 'SERVICE'
[Unit]
Description=Mihomo Proxy Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
SERVICE
    
    systemctl daemon-reload
    systemctl enable mihomo
    log_success "服务创建完成"
}

# 启动服务
start_service() {
    log_info "启动服务..."
    systemctl restart mihomo
    sleep 3
    
    if systemctl is-active mihomo &> /dev/null; then
        log_success "服务启动成功"
    else
        log_error "启动失败"
        journalctl -u mihomo --no-pager -n 10
        exit 1
    fi
}

# 测试代理
test_proxy() {
    log_info "测试代理..."
    
    # 测试 Google
    local code=$(curl -x http://127.0.0.1:7890 -s -o /dev/null -w '%{http_code}' --connect-timeout 10 https://www.google.com 2>&1 || echo "000")
    if [ "$code" = "200" ]; then
        log_success "Google 访问正常"
    else
        log_warn "Google 测试: $code"
    fi
    
    # 测试百度
    local cn_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://www.baidu.com 2>&1 || echo "000")
    if [ "$cn_code" = "200" ]; then
        log_success "百度访问正常（直连）"
    else
        log_warn "百度测试: $cn_code"
    fi
}

# 显示使用说明
show_usage() {
    local local_ip=$(get_local_ip)
    
    echo ""
    echo "=========================================="
    echo -e "  ${GREEN}部署完成!${NC}"
    echo "=========================================="
    echo ""
    echo "代理信息:"
    echo "  HTTP/SOCKS5: $local_ip:7890"
    echo "  Web 面板:    http://$local_ip:9090/ui"
    echo "  API:         http://$local_ip:9090"
    echo ""
    case $PROXY_MODE in
        1) echo "  模式: 全局代理" ;;
        2) echo "  模式: 大陆白名单（国内直连，国外走代理）" ;;
        3) echo "  模式: HTTP/SOCKS 代理" ;;
    esac
    echo ""
    echo "使用方法:"
    echo "  # 本机代理"
    echo "  export http_proxy=http://127.0.0.1:7890"
    echo "  export https_proxy=http://127.0.0.1:7890"
    echo ""
    echo "  # 其他设备"
    echo "  export ALL_PROXY=socks5h://$local_ip:7890"
    echo ""
    echo "管理命令:"
    echo "  sudo systemctl status mihomo    # 查看状态"
    echo "  sudo systemctl restart mihomo   # 重启"
    echo "  sudo journalctl -u mihomo -f    # 日志"
    echo ""
    echo "配置文件: /etc/mihomo/config.yaml"
    echo "=========================================="
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -rf /tmp/metacubexd.zip /tmp/metacubexd-gh-pages /tmp/mihomo.gz
}

# 主流程
main() {
    check_root
    check_deps
    input_config
    install_mihomo
    download_geodata
    download_webui
    write_config
    write_webui_config
    create_service
    start_service
    test_proxy
    cleanup
    show_usage
}

main
