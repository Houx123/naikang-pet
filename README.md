# 奶康 · 跨设备额度桌宠

<p align="center">
  <img src="macos/Assets/PetIcon.png" width="180" alt="奶康桌宠图标">
</p>

奶康是一套面向 macOS 与 iPhone 的轻量状态桌宠：在 Mac 上常驻显示 ChatGPT／Codex 额度、消耗速度和网络状态，并可通过局域网把只读状态同步给 iPhone。iOS 端还提供主屏幕小组件、锁屏小组件与 Live Activity。

## 功能亮点

### macOS 桌宠

- 5 小时与 7 天额度剩余百分比、重置倒计时
- 最近 1 小时／24 小时额度消耗速度
- 公网 IP、近似 IP 归属地与局域网 IPv4 地址
- 实时下载／上传速度，不执行主动测速
- 无边框、可拖动、始终置顶的原生 AppKit 小窗
- 菜单栏奶康头像，可快速显示、隐藏、刷新和退出
- 通过六位配对码向同一局域网内的 iPhone 提供只读状态

### iPhone / iPad

- 原生 SwiftUI 应用，支持 iOS 17+
- 主屏幕小号／中号小组件
- 锁屏矩形小组件
- 锁屏与灵动岛 Live Activity
- 可连接 Mac 奶康读取局域网状态
- 可在应用内登录 ChatGPT，并读取 Usage 页面中用户可见的额度信息

## 直接下载 macOS 版本

[下载奶康 macOS v1.3.0 Universal 2](dist/奶康-macOS-v1.3.0-universal.zip)

安装步骤：

1. 解压压缩包。
2. 把 `奶康.app` 拖入“应用程序”。
3. 首次运行时，在 Finder 中右键应用并选择“打开”。

要求 macOS 13 或更高版本，支持 Apple 芯片和 Intel Mac。额度读取功能需要安装并登录 ChatGPT Mac 应用。

## 从源码运行

### macOS

```sh
cd macos
./build.sh
open 奶康.app
```

### iOS

1. 使用完整 Xcode 打开 `ios/NaiKangIOS.xcodeproj`。
2. 为 `NaiKang` 与 `NaiKangWidget` Target 选择自己的开发团队。
3. 确认两个 Target 使用同一个 App Group。
4. 连接 iPhone 后运行。

更详细的 iOS 使用说明见 [`ios/README.md`](ios/README.md)。

## 项目结构

```text
naikang-pet/
├── macos/   # Objective-C / AppKit 桌宠、图标与构建脚本
├── ios/     # SwiftUI 主应用、Widget 与 Live Activity
└── dist/    # 可直接安装的 macOS Universal 2 压缩包
```

## 数据与隐私

- macOS 额度通过本机 ChatGPT 应用附带的 Codex 组件读取。
- iOS 浏览器模式仅解析 Usage 页面上已经显示给用户的额度文字，不读取密码、Cookie、访问令牌或聊天内容。
- 公网 IP 与近似归属地每 10 分钟通过 IPWhois HTTPS 接口查询一次。
- 网络速度来自本机网络接口字节计数，不会主动产生测速流量。
- Mac 与 iPhone 的同步仅提供只读快照，并使用本地六位配对码；建议仅在可信局域网中启用。

## 当前限制

- macOS 分发包采用临时签名，未经过 Apple 公证，首次运行需要右键“打开”。
- iOS 需要使用自己的 Apple 开发团队签名，系统不会允许普通应用永久悬浮在其他应用之上。
- IP 归属地是网络数据库的近似结果，使用 VPN 时通常显示 VPN 出口位置。
