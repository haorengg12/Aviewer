# Aviewer {VERSION}

多平台 MissAV 浏览/播放客户端。

本版本通过 GitHub Actions 自动构建，提供 Android、iOS 和 Windows 平台的安装包或可执行文件。

---

## 下载

请在当前 Release 页面右侧的「Assets」列表中，根据你的设备平台下载对应文件：

### Android

- Android APK 安装包：`*.apk`
- Android App Bundle：`*.aab`（例如用于商店上传）

> 适用于 Android 5.0 及以上系统。

### iOS

- iOS IPA 安装包：`*.ipa`

> 该 IPA 为未签名包，需要通过 Xcode、AltStore、Sideloadly 等方式安装到真机或模拟器中。

### Windows

- Windows 压缩包：`Aviewer-windows-{TAG}.zip`

> 解压后，进入解压目录，双击运行 `app.exe` 即可启动应用。

---

## 安装说明

### Android 安装

1. 在「Assets」中下载适合的 APK 文件到手机。
2. 在系统设置中开启「安装未知来源应用」权限（不同品牌路径略有差异）。
3. 点击 APK 文件，按照系统提示完成安装。
4. 首次启动时，根据提示授予网络访问等权限。

### iOS 安装

1. 在电脑上下载 `*.ipa` 文件。
2. 使用以下任一方式安装到设备：
   - Xcode：将项目添加到设备并部署 IPA；
   - AltStore / Sideloadly 等第三方工具：导入 IPA 并按工具提示安装；
3. 如出现「未受信任开发者」提示，在 iOS 设置中信任对应开发者后重新打开应用。

> 由于未集成自动签名，本项目提供的 IPA 主要用于测试与自签名安装。

### Windows 安装

1. 在「Assets」中下载 `Aviewer-windows-{TAG}.zip`。
2. 解压到任意目录（例如 `C:\Apps\Aviewer\`）。
3. 双击运行解压目录下的 `app.exe` 启动应用。
4. 如出现 SmartScreen 提示，可选择「更多信息」→「仍要运行」。

---

## 版本信息

- 版本号：`{VERSION}`
- 标签：`{TAG}`（对应本次 Release 的 Git 标签）
- 构建方式：GitHub Actions 自动构建（Android APK / AAB、iOS IPA、Windows ZIP）

如在安装或使用过程中遇到问题，欢迎在 Issues 中反馈，并附上：

- 使用的平台与架构（Android/iOS/Windows）
- 系统版本
- 使用的安装包文件名
- 复现问题的步骤说明

