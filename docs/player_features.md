# 播放器功能说明（Web 与 Android）

## 通用
- 单击视频：播放/暂停
- 进度条：支持拖动快进/快退（允许拖拽）
- 自动隐藏控制条：播放时 3 秒无操作隐藏；任意交互显示
- 键盘（如有）：
  - 左/右：快退/快进 10 秒
  - 空格 / K：播放/暂停
  - J / L：快退/快进 10 秒
  - M：静音/取消静音
  - 上/下（Web）：音量增加/减少
- 播放速度：0.5x / 0.75x / 1.0x / 1.25x / 1.5x / 2.0x

## Web（Chrome 等浏览器）
- 双击任意半区：切换全屏/退出全屏（整页全屏，保留控制条与快捷键）
- 音量条：底部控制条提供音量滑动调节
- 全屏按钮：控制条右侧提供显式全屏按钮
- CORS：如目标流无跨域头，建议开启“通过本地代理”或在服务端开启 CORS

## Android App
- 双击左半区：快退 10 秒
- 双击右半区：快进 10 秒
-（可选后续）沉浸式全屏按钮、系统返回退出全屏

## 实现与文件
- 主界面与交互逻辑：`app/lib/main.dart`
- Web 全屏（条件导入）：
  - `app/lib/platform/fullscreen.dart`
  - `app/lib/platform/fullscreen_web.dart`（优先整页全屏，保证控制条可见）
  - `app/lib/platform/fullscreen_stub.dart`

## 运行与调试（Web 8080）
- 启动：`flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080`
- VS Code：使用 `.vscode/launch.json` 的 “Launch Chrome” 配置访问 `http://localhost:8080`

