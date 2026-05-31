MaiBot + NapCat Termux 一键部署脚本

在 Android 手机上通过 Termux 一键部署 MaiBot 和 NapCat，让麦麦跑进 QQ 群。

前置要求

Android 手机（aarch64 / ARM64）
Termux（从 F-Droid 下载，不要用 Google Play 版）
手机内存 ≥ 6GB，存储空间 ≥ 10GB
一个 QQ 号

快速开始

# 1. 下载脚本
git clone https://github.com/2532316972/MaiBot-Termux-Deploy.git

cd MaiBot-Termux-Deploy


# 2. 完整安装（装环境 + NapCat + MaiBot）
bash deploy.sh install


# 3. 首次启动生成配置 + 开启局域网访问
bash deploy.sh config


# 4. 启动 MaiBot
bash deploy.sh start



命令列表

表格
命令	说明
bash deploy.sh install	完整安装（环境 + NapCat + MaiBot）
bash deploy.sh config	首次启动生成配置 + 开启局域网访问
bash deploy.sh start	启动 MaiBot
bash deploy.sh napcat	启动 NapCat
bash deploy.sh status	查看环境状态
bash deploy.sh clean	清除所有环境（不可逆）
bash deploy.sh help	显示帮助

部署架构

plaintext
1
2
3
4
5
6
7
8
9
10
11
12
13
14
┌──────────────────────────────────────────┐
│           Android 手机                    │
│  ┌────────────────────────────────────┐  │
│  │  Termux 原生环境 (bionic)           │  │
│  │  └─ NapCat (QQ 协议端)              │  │
│  │       WebUI: http://手机IP:6099     │  │
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │  proot-distro Ubuntu (glibc)        │  │
│  │  └─ MaiBot (conda 环境)             │  │
│  │       WebUI: http://手机IP:8001     │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘



部署后配置

MaiBot WebUI（http://手机IP:8001）

配置 LLM API Key 和模型
在插件市场安装 NapCat 适配器

NapCat WebUI（http://手机IP:6099）

扫码登录 QQ
添加 WebSocket 反向代理指向 ws://127.0.0.1:8095

防止后台被杀

Android 设置 → 应用 → Termux → 电池 → 无限制

已知限制

playwright 不可用：Android 不支持，已自动过滤。仅影响插件 HTML 渲染，核心功能不受影响
faiss-cpu：通过 conda-forge 安装（PyPI 无 aarch64 wheel）
后台存活：受 Android 电池优化限制，建议设置电池无限制

清除重装

bash
1
2
3
4
bash deploy.sh clean
# 然后重新安装
bash deploy.sh install



参考

MaiBot 官方文档
NapCat 官方文档
NapCat 适配器文档

License

MIT
