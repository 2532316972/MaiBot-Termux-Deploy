# 📱 MaiBot & NapCat Android (Termux) 全前台部署指南

> **架构说明**：本方案采用 `Termux + proot-distro (Debian)` 架构。NapCat 与 MaiBot 均统一部署在 Debian 容器内，通过 `127.0.0.1` 本地回环网络进行 WebSocket 通信。本指南专为**全前台双窗口**运行模式设计，方便实时查看双端日志。

---

## 📋 前置要求
- **硬件要求**：Android 手机（建议运行内存 ≥ 8GB，存储空间预留 10GB+）。
- **软件要求**：从 [F-Droid](https://f-droid.org/packages/com.termux/) 下载并安装最新版 Termux（请勿使用 Play Store 版本）。
- **网络要求**：手机与电脑需处于同一局域网（Wi-Fi）下。

---

## 🚀 一、 环境初始化 (一键部署)

### 1. Termux 原生准备
在 Termux 原生界面执行，安装基础工具并创建 Debian 容器：
```bash
pkg update -y && pkg upgrade -y && pkg install proot-distro -y && proot-distro install debian
```

### 2. 部署 NapCat (QQ 协议端)
在 Termux 原生界面执行，进入 Debian 容器并一键安装 NapCat：
```bash
proot-distro login debian -- bash -c "apt update -y && apt install -y curl xvfb && curl -o napcat.termux.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.termux.sh && bash napcat.termux.sh"
```
*(注：安装完成后，请留意终端输出的 NapCat WebUI Token 及端口信息。)*

### 3. 部署 MaiBot (核心服务端)
在 Termux 原生界面执行，自动完成 Conda 环境创建、依赖安装（已跳过 playwright）、首次协议确认及局域网 WebUI 配置：
```bash
proot-distro login debian -- bash -c "apt install -y wget git ca-certificates && wget -O ~/Miniforge.sh 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh' && bash ~/Miniforge.sh -b -p ~/miniforge3 && ~/miniforge3/bin/conda create -n maibot python=3.12 -y && ~/miniforge3/bin/conda run -n maibot conda install -c conda-forge faiss-cpu -y && cd ~ && git clone https://github.com/Mai-with-u/MaiBot.git && cd MaiBot && ~/miniforge3/bin/conda run -n maibot pip install \$(grep -v playwright requirements.txt | tr '\n' ' ') && ~/miniforge3/bin/conda run -n maibot pip install maim-message==0.6.8 'maibot-plugin-sdk>=2.5.2' 'maibot-dashboard>=1.3.0' networkx nest-asyncio tenacity && echo '同意' | ~/miniforge3/bin/conda run -n maibot python bot.py ; sed -i 's/host = \"127.0.0.1\"/host = \"0.0.0.0\"/g' ~/MaiBot/config/bot_config.toml"
```

---

## 🖥️ 二、 全前台双窗口启动方案

Termux 支持多会话（Multi-Window）功能，您可以同时开启两个前台窗口，分别监控 NapCat 和 MaiBot 的实时日志。

**操作步骤**：
1. 在 Termux 界面**左滑屏幕边缘**，呼出侧边栏。
2. 点击 **"New Session"** 打开第二个终端窗口。

### 🟢 窗口 1：启动 NapCat
在第一个窗口中执行以下命令：
```bash
proot-distro login napcat -- bash -c "xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox"
```
> 💡 **提示**：当日志输出 `not mini app.` 时，说明 NapCat 已成功启动。请保持此窗口开启，**不要关闭或按 Ctrl+C**。

### 🔵 窗口 2：启动 MaiBot
滑动切换到第二个窗口，执行以下命令：
```bash
proot-distro login debian -- bash -c "~/miniforge3/bin/conda run -n maibot python ~/MaiBot/bot.py"
```
> 💡 **提示**：此时 MaiBot 开始加载核心模块与插件。左右滑动屏幕即可在两个服务的日志之间自由切换。

---

## ⚙️ 三、 WebUI 联动配置

无需在命令行中手动修改配置文件，所有进阶配置均在浏览器中完成。

### 1. 获取访问信息
- **获取手机 IP**：在任意 Termux 窗口执行 `ifconfig`，找到 `wlan0` 下的 `inet` 地址（如 `192.168.x.x`）。
- **获取 NapCat WebUI 凭证**：在 Termux 中执行 `cat /root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config/webui.json` 获取 Token 与端口（默认通常为 `6099`）。

### 2. NapCat 扫码与 WebSocket 配置
1. 电脑浏览器访问 `http://手机IP:6099`，输入 Token 登录 NapCat WebUI。
2. 扫码登录 QQ 账号。
3. 进入 **网络配置** -> **正向 WebSocket**，启用服务并将监听端口设置为 `3001`（若设置了访问 Token 请复制备用）。

### 3. MaiBot 插件与模型配置
1. 电脑浏览器访问 `http://手机IP:8001` 进入 MaiBot WebUI。
2. **安装适配器**：进入 **插件商店**，搜索并安装 `NapCat Adapter`，随后在 **插件管理** 中手动**启用**它。
3. **配置连接**：进入 NapCat Adapter 插件设置，将 WebSocket 地址填写为 `ws://127.0.0.1:3001`（若 NapCat 设置了 Token 请一并填入）。
4. **配置模型**：在 **模型配置** 中填入您的 LLM API 密钥。
5. **群聊白名单**：若群内 @ 机器人无响应，请在插件的 **聊天过滤** 设置中，将目标群号加入白名单，或临时关闭名单过滤进行测试。

---

## 🛡️ 四、 防杀后台设置 (至关重要)

Android 系统的省电策略会强制清理后台进程，导致 Termux 闪退。请务必进行以下设置：
1. **系统设置**：进入 `设置 -> 应用 -> Termux -> 电池`，设置为 **“无限制”** 或 **“允许后台高耗电”**。
2. **自启动权限**：在应用管理中允许 Termux **自启动** 和 **关联启动**。
3. **锁定后台**：在多任务切换界面，将 Termux 卡片**加锁**（通常是下拉卡片或点击锁形图标），防止一键清理内存时误杀。

---

## ❓ 五、 常见问题 (Troubleshooting)

| 现象 | 原因与解决方案 |
| :--- | :--- |
| **NapCat 提示 `not mini app.`** | 这是 NTQQ 启动时的正常底层日志，并非报错，忽略即可。 |
| **电脑无法访问 WebUI** | 确认手机与电脑在同一 Wi-Fi 下；检查手机是否开启了“局域网隔离”或“AP隔离”；确认 MaiBot 配置文件中的 `host` 已改为 `0.0.0.0`。 |
| **群聊 @ 机器人无反应** | NapCat 适配器默认开启群聊白名单。请检查 WebUI 中的 `plugins/MaiBot-Napcat-Adapter/config.toml` 聊天过滤配置，确保群号在白名单内。 |
| **Termux 闪退/断开连接** | 触发了 Android 杀后台机制。请严格执行“第四节”的防杀后台设置，并尽量保持手机充电状态。 |
