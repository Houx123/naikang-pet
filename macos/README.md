# 奶康桌宠额度条

一个位于桌宠旁边、使用 AppKit 编写的原生 macOS 置顶小窗，显示：

- 5 小时额度剩余百分比与重置倒计时
- 7 天额度剩余百分比
- 最近 1 小时（不足时回退到最近 24 小时）的额度消耗速度
- 当前公网 IP 与局域网 IPv4 地址
- 公网 IP 的国家／省市归属地
- 当前网络下载／上传速度（每秒更新，不会主动测速）
- “奶康”应用图标与菜单栏头像，并快速显示当前 5 小时剩余百分比

额度条通过本机 ChatGPT 应用附带的 Codex app-server 读取当前已登录账号的只读额度快照，每 2 分钟自动刷新。历史采样保存在 `~/Library/Application Support/QuotaPet/history.json`，仅用于计算消耗速度。

网络速度读取当前 Wi-Fi／以太网接口的本机字节计数，每秒更新；公网 IP 与归属地通过 IPWhois 的 HTTPS 接口低频查询，启动时获取一次，之后每 10 分钟刷新。IP 归属地是网络数据库的近似结果，不是设备的精确位置。

## 使用

直接下载已经编译好的 Apple 芯片／Intel 通用版本：

[下载奶康 macOS v1.3.0](../dist/奶康-macOS-v1.3.0-universal.zip)

解压后把 `奶康.app` 拖入“应用程序”。第一次启动时，在 Finder 中右键应用并选择“打开”。

运行本地编译版本：

```sh
./build.sh
open 奶康.app
```

窗口可拖动并始终置顶。菜单栏的“奶康”头像可以显示／隐藏、刷新或退出额度条。

窗口的“局域网”一行还会显示 iPhone 配对码。iOS 客户端使用该局域网地址和配对码，从 TCP `48765` 端口读取只读状态。配套工程位于 [`../ios/NaiKangIOS.xcodeproj`](../ios/NaiKangIOS.xcodeproj)。

## 重新编译

```sh
./build.sh
```

编译产物为支持 Apple 芯片与 Intel Mac 的 Universal 2 应用，需要 macOS 13 或更高版本。

## 项目结构

- `Sources/main.m`：AppKit 桌宠与额度、网络状态逻辑
- `Assets/`：应用与菜单栏图标
- `Info.plist`：macOS 应用信息
- `build.sh`：Universal 2 编译与临时签名脚本
- `dist/`：可直接分发的安装压缩包
