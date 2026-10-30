# SingWallet

面向个人的手机记账 App：付款后主动导入支付截图，识别交易信息，确认后入账，并按分类、项目和标签整理。

SingWallet 采用 **轻量混合架构（WebView 离线前端 + Kotlin 原生宿主）**：
- **前端表现与交互层**：以标准 Web 技术栈（HTML5 / ES6+ JavaScript / CSS3）为单一数据源，零外部云端依赖，离线运行于 WebView 中，具备极速开发与毫秒级热重载能力。
- **原生宿主层**：基于 Android Kotlin 原生工程，负责系统级能力调度（MediaProjection 屏幕截取、系统相册 Picker、Google ML Kit 离线 OCR、安全密钥管理与原生桥接）。
- **数据与安全规范**：统一的 SQLite 本地存储架构、四层防重与状态机、跨端 SWBK v1 加密备份互通协议、CSV 公式注入防范机制。

---

## 工程目录结构

```text
singwallet/
├── web/                           # 现代标准前端工程结构（单一事实来源 Single Source of Truth）
│   ├── index.html                 # 单页面前端入口
│   ├── css/                       # 样式表（preview.css 等）
│   └── js/                        # 前端控制器与业务逻辑（app_controller.js, ocr_vlm_engine.js 等）
├── android/                       # Android Kotlin 原生宿主工程
│   ├── app/                       # Android 应用程序模块（含原生桥接、ML Kit OCR、WebView 容器）
│   ├── gradle/                    # Gradle Wrapper 运行时
│   ├── build.gradle.kts           # 顶级 Gradle 构建配置
│   └── settings.gradle.kts        # Gradle 工程设置
├── tools/                         # 自动化工具链、开发辅助与测试套件
│   ├── fixtures/                  # 测试用例样本资源（票据截图 user_bills 等）
│   ├── tests/                     # 自动化验证套件（文档契约、加密与坐标变换验证）
│   │   ├── test_coordinate_harness.py
│   │   └── test_docs_integrity.py
│   ├── preview_server.py          # 本地开发 HTTP 预览服务与 ADB 联动
│   ├── mobile_hot_reload.py       # USB 真机毫秒级热重载推送工具
│   └── run_browser_tests.py       # 无头浏览器自动化 UI/功能测试
├── docs/                          # 规范设计与多端技术方案
│   ├── Android实现方案.md
│   ├── iOS实现方案.md
│   └── 跨平台架构与数据规范.md
└── releases/                      # 版本发布与安装包归档目录
```

---

## 核心开发与构建命令

SingWallet 提供完整的 Python 本地工具链，支撑从开发预览、真机调试到自动化回归测试的全流程：

### 1. 本地预览与 ADB 截屏联动
启动本地 Web 服务，在桌面浏览器中实时预览 UI，并支持通过 ADB 自动拉取 Android 设备截屏进行 OCR 模拟测试：
```bash
python tools/preview_server.py
```

### 2. 真机 USB 毫秒级热重载
通过 USB ADB 监听本地前端代码变动，直接将修改推送至真机应用沙箱并触发 WebView 实时重载，无需重新编译 APK：
```bash
python tools/mobile_hot_reload.py
```

### 3. 前端单源同步至 Android Assets
将前端核心资产（`web/`）同步至 Android 原生工程的 `android/app/src/main/assets/`：
```bash
python tools/sync_web_assets.py
```
> **注**：在执行 Android Gradle 打包构建（如 `./gradlew assembleRelease`）时，构建脚本会自动执行同步任务，确保离线包始终包含最新前端资产。

### 4. 浏览器与契约自动化回归测试
- **无头浏览器端到端测试**：
  ```bash
  python tools/run_browser_tests.py
  ```
- **核心架构资产与文档契约完整性校验**（包含 SQLite DDL、SWBK v1 加解密、CSV 防注入及 OCR 坐标数学映射验证）：
  ```bash
  python tools/tests/test_docs_integrity.py
  ```
- **坐标变换极值与性能压测**：
  ```bash
  python tools/tests/test_coordinate_harness.py
  ```

---

## 方案文档索引

本项目包含详尽的系统设计与跨平台实现规范，请参阅：

- [Android 实现方案](docs/Android实现方案.md)：Android 产品流程、系统限制（沙箱 / MediaProjection / 16KB 内存页）、Kotlin 原生对接、ML Kit 离线 OCR、开发计划与验收标准。
- [iOS 实现方案](docs/iOS实现方案.md)：iOS 产品流程、系统限制（沙箱 / Extension 120MB 内存防爆 / App Groups）、Share Extension 与快捷指令、Apple Vision 离线 OCR、开发计划与验收标准。
- [跨平台架构与数据规范](docs/跨平台架构与数据规范.md)：统一 SQLite 12 张核心表完整 DDL、四层防重与状态机、跨端 SWBK v1 加密备份互通协议、CSV 公式注入防范规范。
