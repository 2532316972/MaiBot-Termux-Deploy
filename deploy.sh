#!/bin/bash
# MaiBot Termux / Android One-Click Installer (Idempotent)
# 官方依赖，无镜像源，适用于已配置代理的环境
# 重复运行安全，不会报错

set -e

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}>>> $1${NC}"; }

# ==================== 环境检查 ====================
if [ -z "$TERMUX_VERSION" ] && [ ! -d "/data/data/com.termux/files/usr" ]; then
    error "This script must be run inside Termux!"
fi

TERMUX_ROOTFS="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs"

# ==================== Step 1: Termux 基础 ====================
step "Step 1/5: Updating Termux and installing base packages"
pkg update -y && pkg upgrade -y
pkg install -y proot-distro wget git curl

# ==================== Step 2: Ubuntu 容器 ====================
step "Step 2/5: Installing Ubuntu container (for MaiBot)"
if proot-distro list 2>/dev/null | grep -q "^ubuntu"; then
    warn "Ubuntu container already exists, skipping."
else
    proot-distro install ubuntu
    info "Ubuntu container installed."
fi

# ==================== Step 3: MaiBot 环境 ====================
step "Step 3/5: Setting up MaiBot inside Ubuntu"

UBUNTU_ROOTFS="$TERMUX_ROOTFS/ubuntu"

cat > "$UBUNTU_ROOTFS/root/setup-maibot.sh" << 'EOF'
#!/bin/bash
set -e

cd ~

# --- 基础工具 ---
apt-get update -y
apt-get install -y wget git curl build-essential

# --- Miniforge ---
if [ ! -d "$HOME/miniforge3" ]; then
    echo "[INFO] Downloading Miniforge..."
    wget -q --show-progress https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh
    bash Miniforge3-Linux-aarch64.sh -b -p "$HOME/miniforge3"
    rm -f Miniforge3-Linux-aarch64.sh
    "$HOME/miniforge3/bin/conda" init bash
fi

export PATH="$HOME/miniforge3/bin:$PATH"
eval "$("$HOME/miniforge3/bin/conda" shell.bash hook)"

# --- Conda 环境（幂等） ---
if ! conda env list 2>/dev/null | grep -q "^maibot "; then
    conda create -n maibot python=3.12 -y
fi
conda activate maibot

# --- faiss-cpu (核心依赖) ---
conda install -c conda-forge faiss-cpu -y

# --- MaiBot 主项目（幂等） ---
if [ -d "$HOME/MaiBot" ]; then
    echo "[WARN] MaiBot directory exists, skipping clone."
else
    git clone https://github.com/Mai-with-u/MaiBot.git
fi
cd MaiBot

# --- Python 依赖 ---
pip install --no-cache-dir \
    aiohttp fastapi uvicorn pydantic sqlalchemy sqlmodel \
    numpy pandas pillow matplotlib scipy jieba pypinyin \
    openai google-genai httpx mcp msgpack \
    python-dotenv python-multipart python-levenshtein \
    rich structlog tomlkit watchfiles colorama \
    certifi json-repair typing-extensions Babel

# --- MaiBot 自有包 ---
pip install maim-message==0.6.8 "maibot-plugin-sdk>=2.5.2" "maibot-dashboard>=1.3.0"

# --- A_Memorix 依赖 ---
pip install networkx nest-asyncio tenacity

# --- NapCat 适配器插件（幂等） ---
cd ~
if [ -d "$HOME/MaiBot-Napcat-Adapter" ]; then
    echo "[WARN] Adapter directory exists, skipping clone."
else
    git clone https://github.com/Mai-with-u/MaiBot-Napcat-Adapter.git
fi
mkdir -p ~/MaiBot/plugins
rm -rf ~/MaiBot/plugins/MaiBot-Napcat-Adapter 2>/dev/null || true
cp -r ~/MaiBot-Napcat-Adapter ~/MaiBot/plugins/

# --- 预配置 WebUI (允许局域网访问，幂等) ---
mkdir -p ~/MaiBot/config
if [ ! -f ~/MaiBot/config/bot_config.toml ]; then
    cat > ~/MaiBot/config/bot_config.toml << 'EOFCFG'
[webui]
enabled = true
host = "0.0.0.0"
port = 8001
EOFCFG
    echo "[INFO] Created bot_config.toml with LAN webui config."
else
    if ! grep -q "^\[webui\]" ~/MaiBot/config/bot_config.toml 2>/dev/null; then
        cat >> ~/MaiBot/config/bot_config.toml << 'EOFCFG'

[webui]
enabled = true
host = "0.0.0.0"
port = 8001
EOFCFG
        echo "[INFO] Appended [webui] section to existing config."
    else
        echo "[WARN] [webui] section already exists, skipping."
    fi
fi

echo ""
echo "=========================================="
echo "  MaiBot environment setup complete"
echo "=========================================="
EOF

chmod +x "$UBUNTU_ROOTFS/root/setup-maibot.sh"
proot-distro login ubuntu -- bash /root/setup-maibot.sh

# ==================== Step 4: NapCat 容器 ====================
step "Step 4/5: Installing NapCat container (for QQ protocol)"

if proot-distro list 2>/dev/null | grep -q "^napcat"; then
    warn "NapCat container already exists, skipping."
else
    curl -fsSL -o napcat.termux.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.termux.sh
    bash napcat.termux.sh
    rm -f napcat.termux.sh
    info "NapCat installed."
fi

# ==================== Step 5: 启动脚本 ====================
step "Step 5/5: Creating launcher commands"

# --- 启动 MaiBot ---
cat > "$PREFIX/bin/start-maibot" << 'EOF'
#!/bin/bash
echo -e "\033[36m[MaiBot Launcher]\033[0m Starting MaiBot..."
proot-distro login ubuntu -- bash -c '
    export PATH="$HOME/miniforge3/bin:$PATH"
    eval "$($HOME/miniforge3/bin/conda shell.bash hook)"
    conda activate maibot
    cd ~/MaiBot
    python bot.py
'
EOF
chmod +x "$PREFIX/bin/start-maibot"

# --- 启动 NapCat ---
cat > "$PREFIX/bin/start-napcat" << 'EOF'
#!/bin/bash
echo -e "\033[36m[NapCat Launcher]\033[0m Starting NapCat..."
proot-distro login napcat -- bash -c '
    if command -v napcat >/dev/null 2>&1; then
        napcat
    elif [ -f ~/napcat.sh ]; then
        bash ~/napcat.sh
    elif [ -f /opt/napcat/napcat ]; then
        /opt/napcat/napcat
    else
        echo "NapCat start command not found. Please check your NapCat installation."
        exit 1
    fi
'
EOF
chmod +x "$PREFIX/bin/start-napcat"

# --- 一键启动两者 ---
cat > "$PREFIX/bin/start-all" << 'EOF'
#!/bin/bash
echo -e "\033[36m[All Services]\033[0m Starting NapCat + MaiBot..."

# 后台启动 NapCat
echo "[1/2] Starting NapCat in background..."
proot-distro login napcat -- bash -c '
    if command -v napcat >/dev/null 2>&1; then
        napcat
    elif [ -f ~/napcat.sh ]; then
        bash ~/napcat.sh
    elif [ -f /opt/napcat/napcat ]; then
        /opt/napcat/napcat
    fi
' &
NAPCAT_PID=$!
sleep 3

# 前台启动 MaiBot
echo "[2/2] Starting MaiBot..."
echo "Press Ctrl+C to stop MaiBot. NapCat will keep running in background."
proot-distro login ubuntu -- bash -c '
    export PATH="$HOME/miniforge3/bin:$PATH"
    eval "$($HOME/miniforge3/bin/conda shell.bash hook)"
    conda activate maibot
    cd ~/MaiBot
    python bot.py
'
EOF
chmod +x "$PREFIX/bin/start-all"

# --- 停止脚本 ---
cat > "$PREFIX/bin/stop-maibot" << 'EOF'
#!/bin/bash
echo "Stopping MaiBot and NapCat..."
pkill -f "python bot.py" 2>/dev/null || true
pkill -f "napcat" 2>/dev/null || true
echo "Done."
EOF
chmod +x "$PREFIX/bin/stop-maibot"

# ==================== 完成提示 ====================
echo ""
echo "=========================================="
echo -e "  ${GREEN}Installation Complete!${NC}"
echo "=========================================="
echo ""
echo -e "  ${CYAN}可用命令:${NC}"
echo "    start-all      一键启动 NapCat + MaiBot"
echo "    start-napcat   仅启动 NapCat (QQ协议端)"
echo "    start-maibot   仅启动 MaiBot"
echo "    stop-maibot    停止所有服务"
echo ""
echo -e "  ${YELLOW}首次使用必读:${NC}"
echo "    1. 运行 start-all 或 start-maibot"
echo "    2. 首次启动会要求输入 [同意] 接受 EULA"
echo "    3. 然后配置 LLM API Key:"
echo "       proot-distro login ubuntu -- nano /root/MaiBot/config/model_config.toml"
echo ""
echo -e "  ${CYAN}局域网访问:${NC}"
echo "    手机IP查看: ip addr show wlan0"
echo "    电脑浏览器: http://<<手机IP>:8001"
echo ""
echo -e "  ${YELLOW}后台保活设置:${NC}"
echo "    Android 设置 → 应用 → Termux → 电池 → 无限制"
echo "    Android 设置 → 应用 → Termux → 自启动 → 允许"
echo ""
