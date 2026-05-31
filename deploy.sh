#!/usr/bin/env bash
# ============================================
# MaiBot + NapCat 全自动部署脚本 (Termux/Android)
# 适配架构: aarch64 (ARM64)
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC}" "$1"; exit 1; }
step()  { echo -e "\n${CYAN}${BOLD}=====> $1${NC}"; }

# ============================================
# 阶段 1: Termux 基础环境 + NapCat
# ============================================
phase1_termux() {
    step "更新 Termux 包"
    pkg update -y && pkg upgrade -y

    step "安装必要工具"
    pkg install proot-distro git -y

    step "安装 Ubuntu 容器"
    proot-distro install ubuntu

    step "安装 NapCat (自动应答)"
    curl -sL https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.termux.sh -o $HOME/napcat.sh
    # 自动对所有提示回答 yes
    yes | bash $HOME/napcat.sh || true
    rm -f $HOME/napcat.sh

    info "NapCat 安装完成"
}

# ============================================
# 阶段 2: Ubuntu 容器内安装 MaiBot
# ============================================
phase2_maibot() {
    step "在 Ubuntu 容器中安装 MaiBot 环境"
    info "conda 安装 faiss-cpu 耗时较长 (10-20分钟)，请耐心等待"

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
# 阶段 3: 自动生成配置 + 开启局域网访问
# ============================================
phase3_config() {
    step "首次启动 MaiBot 生成配置文件 (自动确认 EULA)"

    # 自动输入"同意"确认 EULA，启动后等配置文件生成，然后自动退出
    proot-distro login ubuntu -- bash -c '
source ~/miniforge3/bin/activate maibot
cd ~/MaiBot

# 用 expect 替代方案: 管道输入"同意"，超时 120 秒自动退出
timeout 120 bash -c "echo 同意 | python bot.py" || true

# 检查配置文件是否生成
if [ ! -f config/bot_config.toml ]; then
    echo "ERROR: 配置文件未生成，请手动运行 python bot.py 检查"
    exit 1
fi
'

    step "修改 WebUI 监听地址为 0.0.0.0 (局域网可访问)"
    proot-distro login ubuntu -- bash -c '
CONFIG=~/MaiBot/config/bot_config.toml
sed -i "/^\[webui\]/,/^\[/{s/host = \"127.0.0.1\"/host = \"0.0.0.0\"/}" "$CONFIG"

# 验证修改
if grep -q "host = \"0.0.0.0\"" "$CONFIG"; then
    echo "=== CONFIG OK: WebUI 局域网访问已开启 ==="
else
    echo "WARN: 未能自动修改 host，请手动编辑 config/bot_config.toml"
fi
'

    info "配置完成"
}

# ============================================
# 一键全自动部署
# ============================================
cmd_auto() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════╗"
    echo "║  MaiBot + NapCat 全自动部署              ║"
    echo "║  目标: Termux / Android (aarch64)        ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    warn "整个流程约需 30-60 分钟，期间请保持 Termux 在前台"
    warn "NapCat 安装时可能需要你手动确认部分选项"
    echo ""
    read -p "按回车开始部署，Ctrl+C 取消..." _

    # 阶段 1 + 2
    phase1_termux
    phase2_maibot

    # 阶段 3
    phase3_config

    # 获取局域网 IP
    IP=$(ip addr show wlan0 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
    echo "║          🎉 部署完成！                   ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║  启动 MaiBot:  bash deploy.sh start      ║"
    echo "║  启动 NapCat:  bash deploy.sh napcat     ║"
    echo "╠══════════════════════════════════════════╣${NC}"
    if [ -n "$IP" ]; then
        echo -e "${GREEN}${BOLD}║  WebUI: http://${IP}:8001${NC}${GREEN}${BOLD}              ║"
        echo -e "${GREEN}${BOLD}║  NapCat: http://${IP}:6099${NC}${GREEN}${BOLD}              ║"
    else
        echo -e "${GREEN}${BOLD}║  WebUI: http://手机IP:8001               ║"
        echo -e "${GREEN}${BOLD}║  NapCat: http://手机IP:6099              ║"
    fi
    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════╣"
    echo "║  下一步:                                 ║"
    echo "║  1. 启动 MaiBot 配置 API Key            ║"
    echo "║  2. 启动 NapCat 扫码登录 QQ             ║"
    echo "║  3. 在 WebUI 插件市场装 NapCat 适配器    ║"
    echo "╚══════════════════════════════════════════╝${NC}"
}

# ============================================
# 其他命令
# ============================================
cmd_start() {
    info "启动 MaiBot (Ctrl+C 停止)..."
    proot-distro login ubuntu -- bash -c 'source ~/miniforge3/bin/activate maibot && cd ~/MaiBot && python bot.py'
}

cmd_napcat() {
    info "启动 NapCat..."
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
    rm -rf $HOME/napcat.sh $HOME/Miniforge.sh $HOME/miniforge3 $HOME/MaiBot $HOME/MaiBot-Napcat-Adapter $HOME/.conda
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

    if proot-distro list 2>/dev/null | grep -q "napcat.*installed"; then
        echo -e "  NapCat 容器:  ${GREEN}已安装${NC}"
    else
        echo -e "  NapCat 容器:  ${RED}未安装${NC}"
    fi

    IP=$(ip addr show wlan0 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    if [ -n "$IP" ]; then
        echo ""
        echo -e "  手机 IP:  ${GREEN}$IP${NC}"
        echo -e "  WebUI:    ${GREEN}http://$IP:8001${NC}"
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

show_help() {
    echo ""
    echo -e "${CYAN}${BOLD}MaiBot + NapCat 全自动部署脚本${NC}"
    echo ""
    echo "用法: bash deploy.sh [命令]"
    echo ""
    echo -e "${BOLD}命令:${NC}"
    echo "  auto      全自动部署（推荐，一条命令搞定）"
    echo "  install   仅安装环境 (阶段 1+2，不含配置)"
    echo "  config    仅配置 (首次启动 + 局域网访问)"
    echo "  start     启动 MaiBot"
    echo "  napcat    启动 NapCat"
    echo "  status    查看环境状态"
    echo "  update    更新 MaiBot 到最新版"
    echo "  clean     清除所有环境 (不可逆)"
    echo "  help      显示此帮助"
    echo ""
    echo -e "${BOLD}推荐用法:${NC}"
    echo "  bash deploy.sh auto    # 全自动，坐着等就行"
    echo ""
}

# ============================================
# 入口
# ============================================
case "${1:-help}" in
    auto)    cmd_auto ;;
    install) phase1_termux && phase2_maibot && info "安装完成，运行 bash deploy.sh config 继续" ;;
    config)  phase3_config ;;
    start)   cmd_start ;;
    napcat)  cmd_napcat ;;
    clean)   cmd_clean ;;
    status)  cmd_status ;;
    update)  cmd_update ;;
    help)    show_help ;;
    *)
        echo -e "${RED}[ERROR]${NC} 未知命令: $1"
        echo "运行 bash deploy.sh help 查看帮助"
        exit 1
        ;;
esac
