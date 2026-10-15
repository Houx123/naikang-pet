# 奶康 iOS

原生 SwiftUI iOS 17+ 客户端，包含：

- iPhone／iPad 主应用
- 主屏幕小组件（小号、中号）
- 锁屏矩形小组件
- 锁屏与灵动岛 Live Activity
- 在内嵌浏览器登录 ChatGPT，并从官方 Usage 页面读取可见额度
- 由 iPhone 直接获取公网 IP 与 IP 归属地

## 首次运行

1. 使用完整 Xcode 打开 `NaiKangIOS.xcodeproj`。
2. 在 `NaiKang` 和 `NaiKangWidget` 两个 Target 的 Signing & Capabilities 中选择同一个开发团队。
3. 确认两个 Target 都启用了同一个 App Group。
4. 连接 iPhone 并运行。
5. 在应用中点“登录并读取额度”，在 OpenAI 页面完成登录。
6. 登录后点“打开 Usage 页面”，再点“读取额度”。

同步成功后，可从主屏幕编辑模式添加“奶康”小组件；应用内按钮可启动锁屏／灵动岛状态。

## 浏览器读取机制

登录由 OpenAI 网页处理。奶康只在 `chatgpt.com/settings/usage` 页面读取 `document.body.innerText` 中已经显示给用户的额度文字，不读取密码、Cookie、访问令牌或聊天内容。解析后的额度快照写入 App Group，供 Widget 和 Live Activity 使用。

由于 iOS 不允许后台网页持续运行，额度需要在应用内重新打开 Usage 页面刷新。Widget 的刷新时间由 iOS 调度，不能保证每秒更新。

## 当前限制

- iOS 不允许跨应用永久悬浮窗口。
- iOS 不允许普通应用读取整个设备的实时上／下行速度；浏览器模式不显示伪造的实时网速。
- IP 归属地是公网 IP 数据库的近似值，使用 VPN 时通常显示 VPN 出口位置。
- ChatGPT 页面结构变化时，额度文字解析规则可能需要更新。
