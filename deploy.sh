#!/usr/bin/env bash
# ============================================
# MaiBot + NapCat 全自动部署脚本 (最终版)
# 解决：强制 NapCat 安装脚本内所有 curl/wget 忽略 SSL 证书
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}${BOLD}=====> $1${NC}"; }

# ------------------------------------------------------------
# 1. 安装 NapCat（强制所有 curl/wget 忽略证书）
# ------------------------------------------------------------
install_napcat() {
    step "安装 NapCat (全局禁用 SSL 验证)"

    # 删除旧容器
    proot-distro list 2>/dev/null | grep -q napcat && proot-distro remove napcat

    # 创建 Debian 容器
    proot-distro install debian --override-alias napcat

    # 初始化脚本：更新证书 + 下载官方脚本 + 替换命令 + 执行
    local init_script="
apt update -y
apt install -y sudo curl wget xvfb screen
apt install --reinstall ca-certificates -y
update-ca-certificates -f

# 下载官方安装脚本
curl -k -o /tmp/install.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh

# 关键修复：将脚本内所有的 curl 替换为 curl -k，所有的 wget 替换为 wget --no-check-certificate
sed -i 's/curl /curl -k /g' /tmp/install.sh
sed -i 's/wget /wget --no-check-certificate /g' /tmp/install.sh

# 执行修改后的安装脚本
bash /tmp/install.sh --docker n --cli n

# 清理
apt autoremove -y && apt clean
rm -rf /tmp/*
"

    proot-distro sh napcat -- bash -c "$init_script"
    if [ $? -ne 0 ]; then
        proot-distro remove napcat
        error "NapCat 安装失败"
    fi

    info "NapCat 安装成功"
    echo -e "${GREEN}启动 NapCat: proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox\"${NC}"
    echo -e "${GREEN}后台启动: screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox\"'${NC}"
}

# ------------------------------------------------------------
# 2. 安装 MaiBot (与之前相同，无改动)
# ------------------------------------------------------------
install_maibot() {
    step "安装 Ubuntu 容器"
    proot-distro install ubuntu

    step "在 Ubuntu 中安装 MaiBot 环境"
    proot-distro login ubuntu -- bash -c '
set -e
DEBIAN_FRONTEND=noninteractive
apt update -qq && apt upgrade -y -qq && apt install -y -qq wget git

# 安装 Miniforge
wget -qO ~/Miniforge.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh
bash ~/Miniforge.sh -b -p ~/miniforge3
rm ~/Miniforge.sh

# 创建 conda 环境
~/miniforge3/bin/conda create -n maibot python=3.12 -y -q
~/miniforge3/bin/conda install -n maibot -c conda-forge faiss-cpu -y -q

# 克隆 MaiBot 并安装依赖
git clone --depth 1 https://github.com/Mai-with-u/MaiBot.git ~/MaiBot
cd ~/MaiBot
grep -v playwright requirements.txt > /tmp/req.txt
~/miniforge3/envs/maibot/bin/pip install -q -r /tmp/req.txt
'
    info "MaiBot 环境安装完成"
}

# ------------------------------------------------------------
# 3. 配置 MaiBot (首次启动 + 局域网访问)
# ------------------------------------------------------------
configure_maibot() {
    step "首次启动 MaiBot 生成配置 (自动确认 EULA)"
    proot-distro login ubuntu -- bash -c '
source ~/miniforge3/bin/activate maibot
cd ~/MaiBot
timeout 120 bash -c "echo 同意 | python bot.py" || true
'

    step "开启 WebUI 局域网访问"
    proot-distro login ubuntu -- bash -c '
CONFIG=~/MaiBot/config/bot_config.toml
if grep -q "^\[webui\]" "$CONFIG"; then
    sed -i "/^\[webui\]/,/^\[/{s/host = \"127.0.0.1\"/host = \"0.0.0.0\"/}" "$CONFIG"
else
    cat >> "$CONFIG" <<EOF

[webui]
enabled = true
host = "0.0.0.0"
port = 8001
EOF
fi
'
    info "MaiBot 配置完成"
}

# ------------------------------------------------------------
# 辅助命令
# ------------------------------------------------------------
show_status() {
    echo ""
    echo -e "${CYAN}当前状态:${NC}"
    proot-distro list
    IP=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    if [ -n "$IP" ]; then
        echo -e "手机 IP: ${GREEN}$IP${NC}"
        echo -e "MaiBot WebUI: ${GREEN}http://$IP:8001${NC}"
    else
        warn "无法获取手机 IP，请手动输入 ifconfig 查看"
    fi
    echo ""
}

start_maibot() {
    proot-distro login ubuntu -- bash -c 'source ~/miniforge3/bin/activate maibot && cd ~/MaiBot && python bot.py'
}
start_napcat() {
    proot-distro sh napcat -- bash -c "xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox"
}
start_napcat_bg() {
    screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c "xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox"'
    info "NapCat 已在后台运行，使用 screen -r napcat 查看"
}
clean_all() {
    warn "将删除所有环境 (Ubuntu、NapCat 容器、MaiBot 文件)，不可逆！"
    read -p "输入 YES 确认: " confirm
    [ "$confirm" != "YES" ] && exit 0
    proot-distro remove ubuntu 2>/dev/null || true
    proot-distro remove napcat 2>/dev/null || true
    rm -rf ~/miniforge3 ~/MaiBot
    info "清理完成"
}

# ------------------------------------------------------------
# 一键部署
# ------------------------------------------------------------
auto_deploy() {
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗"
    echo "║   MaiBot + NapCat 全自动部署         ║"
    echo "║   全局强制 curl/wget 忽略 SSL        ║"
    echo "╚════════════════════════════════════════╝${NC}"
    warn "全程约 30-60 分钟，请保持 Termux 前台"
    read -p "按回车开始..."

    step "阶段 1/3: 安装 NapCat"
    install_napcat

    step "阶段 2/3: 安装 MaiBot"
    install_maibot

    step "阶段 3/3: 配置 MaiBot"
    configure_maibot

    echo -e "${GREEN}${BOLD}部署完成！${NC}"
    show_status
    echo -e "启动 MaiBot:   bash deploy.sh start"
    echo -e "启动 NapCat:   bash deploy.sh napcat (前台)"
    echo -e "后台 NapCat:   bash deploy.sh napcat-bg"
    echo -e "查看状态:      bash deploy.sh status"
}

show_help() {
    cat <<EOF
用法: bash deploy.sh [命令]

命令:
  auto         一键全自动部署 (推荐)
  start        启动 MaiBot
  napcat       前台启动 NapCat
  napcat-bg    后台启动 NapCat
  status       查看状态
  clean        清除所有环境
  help         显示帮助

示例:
  bash deploy.sh auto
  bash deploy.sh start
  bash deploy.sh napcat-bg
EOF
}

# ------------------------------------------------------------
# 入口
# ------------------------------------------------------------
case "${1:-help}" in
    auto)       auto_deploy ;;
    start)      start_maibot ;;
    napcat)     start_napcat ;;
    napcat-bg)  start_napcat_bg ;;
    status)     show_status ;;
    clean)      clean_all ;;
    help)       show_help ;;
    *)          echo "未知命令: $1" && show_help ;;
esac
