#!/usr/bin/env bash
# ============================================
# MaiBot + NapCat 全自动部署脚本 (Termux/Android)
# 适配架构: aarch64 (ARM64)
# 修正: 解决容器内证书过期、curl 下载失败问题
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}" "$1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}" "$1"; }
error() { echo -e "${RED}[ERROR]${NC}" "$1"; exit 1; }
step()  { echo -e "\n${CYAN}${BOLD}=====> $1${NC}"; }

# ============================================
# 阶段 1: Termux 基础环境
# ============================================
phase1_termux() {
    step "更新 Termux 包"
    pkg update -y && pkg upgrade -y

    step "安装必要工具 (proot-distro, screen)"
    pkg install proot-distro screen -y
}

# ============================================
# 阶段 2: 安装 NapCat (官方 Termux 方式，修复证书问题)
# ============================================
phase2_napcat() {
    step "安装 NapCat (Debian 容器)"

    # 如果容器已存在，先删除
    if proot-distro list 2>/dev/null | grep -q "napcat.*installed"; then
        warn "NapCat 容器已存在，正在删除旧容器..."
        proot-distro remove napcat
    fi

    # 安装 debian 容器并重命名为 napcat
    proot-distro install debian --override-alias napcat

    step "初始化 NapCat 容器 (安装 QQ + NapCat)"
    info "这一步会下载 NapCat Linux 安装脚本，耗时约 3-5 分钟"
    info "已包含证书修复步骤，确保 curl 下载成功"

    # 关键修正：先安装/更新 ca-certificates，然后使用 -k 备用
    local init_cmd="apt update -y && \
apt install -y sudo curl libgcrypt20 ca-certificates --reinstall && \
update-ca-certificates -f && \
curl -k -o napcat.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh && \
bash napcat.sh --docker n --cli n && \
apt autoremove -y && \
apt clean && \
rm -rf /tmp/* /var/lib/apt/lists /root/napcat.sh"

    proot-distro sh napcat -- bash -c "$init_cmd"
    if [ $? -ne 0 ]; then
        proot-distro remove napcat
        error "NapCat 容器初始化失败"
    fi

    info "NapCat 安装完成"
    echo ""
    echo -e "${GREEN}启动 NapCat (前台):${NC}"
    echo -e "  proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox\""
    echo -e "${GREEN}后台启动 NapCat:${NC}"
    echo -e "  screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox\"'"
    echo -e "${GREEN}后台快速登录 (指定 QQ 号):${NC}"
    echo -e "  screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox -q 你的QQ号\"'"
    echo -e "${GREEN}进入容器内部:${NC} proot-distro login napcat"
    echo -e "${MAGENTA}Napcat 真实路径(容器外): /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/napcat/root/Napcat${NC}"
    echo -e "${MAGENTA}WebUI 密钥文件: 安装位置/config/webui.json${NC}"
    echo ""
}

# ============================================
# 阶段 3: 安装 Ubuntu + MaiBot
# ============================================
phase3_maibot() {
    step "安装 Ubuntu 容器"
    # 如果容器已存在，先删除
    if proot-distro list 2>/dev/null | grep -q "ubuntu.*installed"; then
        warn "Ubuntu 容器已存在，正在删除旧容器..."
        proot-distro remove ubuntu
    fi

    proot-distro install ubuntu

    step "在 Ubuntu 容器中安装 MaiBot 环境"
    info "conda 安装 faiss-cpu 耗时较长 (10-20 分钟)，请耐心等待"

    proot-distro login ubuntu -- bash -c '
set -e
DEBIAN_FRONTEND=noninteractive

echo "=====> 更新系统包"
apt update -qq && apt upgrade -y -qq && apt install -y -qq wget git

echo "=====> 安装 Miniforge (conda)"
wget -qO $HOME/Miniforge.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh
bash $HOME/Miniforge.sh -b -p $HOME/miniforge3
rm -f $HOME/Miniforge.sh

echo "=====> 创建 conda 环境 (python 3.12)"
$HOME/miniforge3/bin/conda create -n maibot python=3.12 -y -q

echo "=====> 安装 faiss-cpu (via conda-forge, 这步最慢)"
$HOME/miniforge3/bin/conda install -n maibot -c conda-forge faiss-cpu -y -q

echo "=====> 克隆 MaiBot"
rm -rf $HOME/MaiBot
git clone --depth 1 https://github.com/Mai-with-u/MaiBot.git $HOME/MaiBot

echo "=====> 安装 Python 依赖 (跳过 playwright)"
cd $HOME/MaiBot
grep -v playwright requirements.txt > /tmp/req.txt
$HOME/miniforge3/envs/maibot/bin/pip install -q -r /tmp/req.txt

echo "=== INSTALL DONE ==="
'

    info "MaiBot 环境安装完成"
}

# ============================================
# 阶段 4: 自动生成配置 + 开启局域网访问
# ============================================
phase4_config() {
    step "首次启动 MaiBot 生成配置文件 (自动确认 EULA)"

    proot-distro login ubuntu -- bash -c '
source ~/miniforge3/bin/activate maibot
cd ~/MaiBot
timeout 120 bash -c "echo 同意 | python bot.py" || true

if [ ! -f config/bot_config.toml ]; then
    echo "ERROR: 配置文件未生成"
    exit 1
fi
'

    step "修改 WebUI 监听地址为 0.0.0.0 (局域网可访问)"
    proot-distro login ubuntu -- bash -c '
CONFIG=~/MaiBot/config/bot_config.toml
# 如果 [webui] 段存在则修改 host，否则追加
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

    info "配置完成"
}

# ============================================
# 日常命令
# ============================================
cmd_start() {
    info "启动 MaiBot (Ctrl+C 停止)..."
    proot-distro login ubuntu -- bash -c 'source ~/miniforge3/bin/activate maibot && cd ~/MaiBot && python bot.py'
}

cmd_napcat() {
    info "启动 NapCat (前台, Ctrl+C 停止)..."
    proot-distro sh napcat -- bash -c "xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox"
}

cmd_napcat_bg() {
    info "后台启动 NapCat (screen -r napcat 查看, Ctrl+A+D 离开)..."
    screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c "xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox"'
    info "NapCat 已在后台运行"
}

cmd_napcat_bg_qq() {
    if [ -z "$1" ]; then
        error "请提供 QQ 号，用法: bash deploy.sh napcat-bg-qq 123456789"
    fi
    info "后台启动 NapCat 并快速登录 QQ $1 ..."
    screen -dmS napcat bash -c "proot-distro sh napcat -- bash -c 'xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox -q $1'"
    info "NapCat 已在后台运行，请用 screen -r napcat 查看二维码或确认登录"
}

cmd_napcat_login() {
    info "进入 NapCat 容器内部 (可手动操作)..."
    proot-distro login napcat
}

cmd_clean() {
    warn "这将删除所有环境 (Ubuntu、NapCat 容器、MaiBot 文件)，不可逆！"
    read -p "输入 YES 确认: " confirm
    if [ "$confirm" != "YES" ]; then
        info "已取消"
        exit 0
    fi
    step "清除环境..."
    proot-distro remove ubuntu 2>/dev/null || true
    proot-distro remove napcat 2>/dev/null || true
    rm -rf $HOME/miniforge3 $HOME/MaiBot $HOME/MaiBot-Napcat-Adapter $HOME/.conda
    info "环境已清除"
}

cmd_status() {
    echo ""
    echo -e "${CYAN}环境状态:${NC}"

    if ! command -v proot-distro &>/dev/null; then
        echo -e "  proot-distro: ${RED}未安装${NC}"
        return
    fi
    echo -e "  proot-distro: ${GREEN}已安装${NC}"

    if proot-distro list 2>/dev/null | grep -q "napcat.*installed"; then
        echo -e "  NapCat 容器:  ${GREEN}已安装${NC}"
    else
        echo -e "  NapCat 容器:  ${RED}未安装${NC}"
    fi

    if proot-distro list 2>/dev/null | grep -q "ubuntu.*installed"; then
        echo -e "  Ubuntu 容器:  ${GREEN}已安装${NC}"
        if proot-distro login ubuntu -- bash -c 'test -d ~/miniforge3' 2>/dev/null; then
            echo -e "  Miniforge:    ${GREEN}已安装${NC}"
        else
            echo -e "  Miniforge:    ${RED}未安装${NC}"
        fi
        if proot-distro login ubuntu -- bash -c 'test -d ~/MaiBot' 2>/dev/null; then
            echo -e "  MaiBot:       ${GREEN}已安装${NC}"
            if proot-distro login ubuntu -- bash -c 'test -f ~/MaiBot/config/bot_config.toml' 2>/dev/null; then
                echo -e "  配置文件:     ${GREEN}已生成${NC}"
            else
                echo -e "  配置文件:     ${YELLOW}未生成${NC}"
            fi
        else
            echo -e "  MaiBot:       ${RED}未安装${NC}"
        fi
    else
        echo -e "  Ubuntu 容器:  ${RED}未安装${NC}"
    fi

    # 获取手机局域网 IP（更通用的方法）
    IP=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    if [ -n "$IP" ]; then
        echo ""
        echo -e "  手机 IP:  ${GREEN}$IP${NC}"
        echo -e "  MaiBot WebUI:  ${GREEN}http://$IP:8001${NC}"
    else
        echo ""
        warn "未能自动获取 IP，请手动输入 ifconfig 查看"
    fi
    echo ""
}

cmd_update() {
    step "更新 MaiBot 到最新版"
    proot-distro login ubuntu -- bash -c '
source ~/miniforge3/bin/activate maibot
cd ~/MaiBot
git pull
grep -v playwright requirements.txt > /tmp/req.txt
pip install -q -r /tmp/req.txt
echo "=== UPDATE DONE ==="
'
}

cmd_auto() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║   MaiBot + NapCat 全自动部署                 ║"
    echo "║   目标: Termux / Android (aarch64)           ║"
    echo "║   已修复证书过期问题                         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"

    warn "整个流程约需 30-60 分钟，请保持 Termux 在前台"
    echo ""
    read -p "按回车开始部署，Ctrl+C 取消..." _

    phase1_termux
    phase2_napcat
    phase3_maibot
    phase4_config

    IP=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗"
    echo "║            🎉 部署完成！                     ║"
    echo "╠══════════════════════════════════════════════╣"
    echo "║  启动 MaiBot:   bash deploy.sh start         ║"
    echo "║  启动 NapCat:   bash deploy.sh napcat        ║"
    echo "║  后台 NapCat:   bash deploy.sh napcat-bg     ║"
    echo "║  指定QQ后台:    bash deploy.sh napcat-bg-qq QQ号 ║"
    echo "╠══════════════════════════════════════════════╣${NC}"
    if [ -n "$IP" ]; then
        echo -e "${GREEN}${BOLD}║  MaiBot WebUI:  http://${IP}:8001${NC}"
    else
        echo -e "${GREEN}${BOLD}║  MaiBot WebUI:  http://手机IP:8001           ║"
    fi
    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════╣"
    echo "║  下一步:                                     ║"
    echo "║  1. bash deploy.sh start  配置 API Key      ║"
    echo "║  2. bash deploy.sh napcat 扫码登录 QQ       ║"
    echo "║  3. 在 WebUI 插件市场装 NapCat 适配器        ║"
    echo "╚══════════════════════════════════════════════╝${NC}"
}

show_help() {
    echo ""
    echo -e "${CYAN}${BOLD}MaiBot + NapCat 全自动部署脚本 (修正版)${NC}"
    echo ""
    echo "用法: bash deploy.sh [命令]"
    echo ""
    echo -e "${BOLD}部署命令:${NC}"
    echo "  auto         全自动部署（推荐）"
    echo "  install      仅安装环境 (阶段 1+2+3，不含配置)"
    echo "  config       仅配置 (首次启动 + 局域网访问)"
    echo ""
    echo -e "${BOLD}运行命令:${NC}"
    echo "  start        启动 MaiBot (前台)"
    echo "  napcat       启动 NapCat (前台)"
    echo "  napcat-bg    后台启动 NapCat"
    echo "  napcat-bg-qq QQ号   后台启动 NapCat 并快速登录指定 QQ"
    echo "  napcat-login 进入 NapCat 容器内部"
    echo ""
    echo -e "${BOLD}管理命令:${NC}"
    echo "  status       查看环境状态"
    echo "  update       更新 MaiBot"
    echo "  clean        清除所有环境 (不可逆)"
    echo "  help         显示此帮助"
    echo ""
    echo -e "${BOLD}示例:${NC}"
    echo "  bash deploy.sh auto"
    echo "  bash deploy.sh start"
    echo "  bash deploy.sh napcat-bg-qq 123456789"
    echo ""
}

# ============================================
# 入口
# ============================================
case "${1:-help}" in
    auto)            cmd_auto ;;
    install)         phase1_termux && phase2_napcat && phase3_maibot && info "安装完成，运行 bash deploy.sh config 继续" ;;
    config)          phase4_config ;;
    start)           cmd_start ;;
    napcat)          cmd_napcat ;;
    napcat-bg)       cmd_napcat_bg ;;
    napcat-bg-qq)    cmd_napcat_bg_qq "$2" ;;
    napcat-login)    cmd_napcat_login ;;
    clean)           cmd_clean ;;
    status)          cmd_status ;;
    update)          cmd_update ;;
    help)            show_help ;;
    *)
        echo -e "${RED}[ERROR]${NC} 未知命令: $1"
        echo "运行 bash deploy.sh help 查看帮助"
        exit 1
        ;;
esac
