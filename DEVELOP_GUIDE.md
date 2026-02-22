# Flutter 视频抓取与播放项目综合开发规范 (V1.2)

## 1. 核心架构设计 (Architecture)
采用 **MVVM + Repository + Local Source** 的分层模式，确保业务逻辑与 UI 分离。

*   **View (UI层)**: 仅负责 Widget 构建。使用 **Riverpod** 监听状态。严禁在 Widget 内部执行正则表达式解析或直接调用数据库。
*   **ViewModel (状态管理层)**: 使用 Riverpod 的 `AsyncNotifier` 管理页面状态（加载中、播放器实例、错误反馈）。负责 `FlickManager` 的生命周期。
*   **Repository (仓库层)**: 数据的“指挥官”。负责判断是从 **Remote** (爬虫抓取) 还是 **Local** (数据库历史记录) 获取数据。
*   **Data Source (数据源层)**:
    *   **Remote**: 基于 [Dio](https://pub.dev) 模拟请求。
    *   **Parser**: 独立 HTML 解析类（使用 `beautiful_soup_dart`），禁止与 UI 耦合。
    *   **Local**: 基于 [Drift](https://drift.simonbinder.eu) 的响应式 SQL 存储。

---

## 2. 技术栈选型 (Technology Stack)


| 维度              | 推荐工具                                             | 理由                                                       |
| :---------------- | :--------------------------------------------------- | :--------------------------------------------------------- |
| **状态管理**      | [Riverpod](https://riverpod.dev)                     | 异步状态处理能力强，自动处理 Provider 销毁，避免内存泄漏。 |
| **视频播放**      | [flick_video_player](https://pub.dev)                | 提供成熟的 UI 皮肤，支持手势控制、全屏适配，体验接近原生。 |
| **网络请求**      | [Dio](https://pub.dev)                               | 支持拦截器、Cookie 自动化管理，爬虫模拟请求首选。          |
| **HTML 解析**     | [beautiful_soup_dart](https://pub.dev)               | 语法接近 Python BeautifulSoup，解析 DOM 节点最高效。       |
| **本地数据库**    | [Drift (Moor)](https://drift.simonbinder.eu)         | 类型安全，支持 Stream 监听，历史记录更新时 UI 自动同步。   |
| **Cookie 持久化** | [dio_cookie_manager](https://pub.dev_cookie_manager) | 配合 `PersistedCookieJar` 实现跨会话登录态自动保持。       |

---

## 3. 代码编写规范 (Coding Standards)

### 3.1 命名与风格
*   **类名**: `UpperCamelCase` (如 `VideoDetailScreen`)。
*   **变量/方法**: `lowerCamelCase` (如 `fetchVideoList()`)。
*   **常量**: 以小写 `k` 开头 (如 `kDefaultPadding`)。
*   **文件组织**: 单个 Widget 文件不建议超过 200 行，复杂组件需拆分为独立类。

### 3.2 异步与容错
*   **空安全**: 严格执行 Dart Null Safety。
*   **异常拦截**: 所有的爬虫逻辑必须包裹 `try-catch`。针对网站改版导致的解析失败，需展示明确的 `ErrorWidget` 而非直接 Crash。
*   **性能优化**: 静态 Widget 必须加 `const`。长列表必须使用 `ListView.builder` 实现懒加载。

---

## 4. 视频播放与 UI 规范 (Player & UI)

### 4.1 播放器控制 (Flick Video Player)
*   **生命周期**: 必须在 ViewModel/Provider 中初始化 `FlickManager`，并在页面 `dispose` 时确保调用其 `dispose()` 方法。
*   **布局适配**: 播放器容器必须包裹在 `AspectRatio(aspectRatio: 16/9)` 中，防止加载前后页面抖动。
*   **状态保持**: 在数据库中存储 `last_position`（播放进度），再次打开时通过 `seekTo` 续播。

### 4.2 交互体验
*   **加载反馈**: 网络抓取阶段必须展示 **骨架屏 (Skeleton Screen)**，禁止长时间白屏。
*   **响应式布局**: 使用 `LayoutBuilder` 适配移动端（竖屏）与桌面端（横屏/多窗体）。

---

## 5. 多平台适配要求 (Android, Windows, Linux)

### 5.1 环境与依赖
*   **路径安全**: 必须使用 [path_provider](https://pub.dev) 获取目录，禁止在 Windows/Linux 下硬编码 `C:\` 或 `/root`。
*   **网络权限**: 
    *   Android: `AndroidManifest.xml` 需开启 `INTERNET` 与 `WAKE_LOCK`。
    *   桌面端: 需确保安装了对应的 C++ 编译环境（Visual Studio 或 CMake/Ninja）。

### 5.2 窗口管理
*   针对 Windows/Linux，建议集成 [window_manager](https://pub.dev) 处理窗口最小尺寸限制及全屏时的状态栏隐藏。

---

## 6. Trae/AI 协作指令 (AI Instructions)
1.  **架构遵守**: 编写功能前，先定义 `Model` 和 `Repository`。
2.  **Lint 约束**: 开启 `analysis_options.yaml` 中的严格模式。
3.  **UI 生成**: 要求 Trae 生成的 Widget 必须是功能单一的子组件（Sub-widgets）。
4.  **爬虫测试**: 要求 Trae 在编写解析逻辑后提供对应的 Mock 测试用例。
