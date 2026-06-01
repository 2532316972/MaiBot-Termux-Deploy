#!/usr/bin/env bash
# ============================================
# MaiBot + NapCat 全自动部署脚本 (最终修复版)
# 解决：容器内证书过期导致的 SSL 错误
# 所有下载均使用 curl -k 或 wget --no-check-certificate
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
# 1. 安装 NapCat（手动方式，绕过官方脚本的 SSL 问题）
# ------------------------------------------------------------
install_napcat() {
    step "安装 NapCat (手动修复 SSL)"

    # 删除旧容器
    proot-distro list 2>/dev/null | grep -q napcat && proot-distro remove napcat

    # 创建 Debian 容器
    proot-distro install debian --override-alias napcat

    # 初始化容器：更新证书 + 手动下载 QQ + 安装 NapCat
    step "初始化 NapCat 容器 (更新证书, 手动安装)"
    local init_script="
# 1. 基础更新和证书修复
apt update -y
apt install -y sudo curl wget xvfb screen
apt install --reinstall ca-certificates -y
update-ca-certificates -f

# 2. 下载 LinuxQQ (使用 wget 忽略证书检查，带重试)
echo '==> 下载 LinuxQQ arm64.deb'
for url in 'https://dldir1.qq.com/qqfile/qq/QQNT/7516007c/linuxqq_3.2.25-45758_arm64.deb' \
           'https://dldir1.qq.com/qqfile/qq/QQNT/005d58b8/linuxqq_3.2.13-25919_arm64.deb'; do
    wget --no-check-certificate -O /tmp/qq.deb \"\$url\" && break
    echo '下载失败，尝试下一个链接...'
done
if [ ! -f /tmp/qq.deb ]; then
    echo '错误：所有 QQ 下载链接均失败'
    exit 1
fi

# 3. 安装 QQ
dpkg -i /tmp/qq.deb || apt --fix-broken install -y

# 4. 下载并运行 NapCat 安装脚本 (使用 curl -k)
echo '==> 安装 NapCat'
curl -k -o /tmp/napcat_install.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh
bash /tmp/napcat_install.sh --docker n --cli n

# 5. 清理
apt autoremove -y && apt clean
rm -rf /tmp/*

echo 'NapCat 安装完成'
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
# 2. 安装 MaiBot (不变)
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
# 3. 配置 MaiBot
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
    echo "║   手动修复 SSL 证书问题               ║"
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
