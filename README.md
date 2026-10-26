# SingWallet

面向个人的手机记账 App：付款后主动导入支付截图，识别交易信息，确认后入账，并按分类、项目和标签整理。

基于 Flutter 跨平台架构开发，核心记账与规则逻辑完全跨端复用，Android 与 iOS 原生分别对接系统级截屏与高精度离线 OCR 能力。

## 方案文档索引

本项目设计方案已完整落定，分为以下三个核心模块：

- [Android 实现方案](docs/Android实现方案.md)：Android 产品流程、系统限制（沙箱 / MediaProjection / 16KB 页）、Kotlin 原生对接、ML Kit 离线 OCR、开发计划与验收标准。
- [iOS 实现方案](docs/iOS实现方案.md)：iOS 产品流程、系统限制（沙箱 / Extension 120MB 内存防爆 / App Groups）、Share Extension 与快捷指令（App Intents / 轻点背面 / Action Button）、Apple Vision 离线 OCR、开发计划与验收标准。
- [跨平台架构与数据规范](docs/跨平台架构与数据规范.md)：统一 SQLite 12 张核心表完整 DDL、四层防重与状态机、跨端 SWBK v1 加密备份互通协议、CSV 公式注入防范规范。
- [Pigeon 跨端接口定义](pigeons/native_bridge.dart)：Flutter 与 Android (Kotlin) / iOS (Swift) 强类型通信契约 IDL。

当前目录包含完整的架构设计与技术方案文档，尚未创建应用工程。
