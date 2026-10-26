# Original User Request

## 2026-10-22T09:06:30Z

SingWallet 核心工程阶段性落地（M0 基础框架与 Pigeon 通信桥接 + M1 SQLite 核心数据层与交易解析引擎），以生产就绪规范（分层架构、类型安全、边界防护与自动化测试）完成核心构建。

Working directory: c:\Other\Projects\singwallet
Integrity mode: development

参考规范与已有方案：
- 跨平台架构与数据规范：docs/跨平台架构与数据规范.md
- Android 实现方案：docs/Android实现方案.md
- iOS 实现方案：docs/iOS实现方案.md
- 跨端通信契约 IDL：pigeons/native_bridge.dart
- 既有校验参考套件：test_docs_integrity.py

## Requirements

### R1. Flutter 项目脚手架与原生桥接契约（M0）
初始化 Flutter 工程结构，配置 Pigeon 依赖并执行代码生成。确保 Dart、Android (Kotlin) 与 iOS (Swift) 的双向强类型通信代码成功生成并无缝对接，通信数据结构严格符合 pigeons/native_bridge.dart 规范。

### R2. 统一 SQLite 数据层与事务管理（M1）
依据 docs/跨平台架构与数据规范.md 建立完整的 12 张核心数据表、外键级联与 11 项性能索引。实现安全的数据库初始化、事务管理、数据迁移机制以及四层防重与状态机流转逻辑。所有货币金额字段以最小货币单位整数存储。

### R3. 交易识别解析与分类规则引擎（M1）
基于 OCR 数据模型实现账单文本字段提取流水线（金额解析、单号去重校验、商户名提取）与分类规则自动匹配引擎。

### R4. 自动化测试套件与持续验证（M1）
建立可自动化运行的测试套件，全面覆盖数据库 DDL 与级联约束、Pigeon 编解码契约、金额精度、四层防重与状态机流转等核心逻辑。

## Acceptance Criteria

### 代码生成与静态检查
- [ ] dart run pigeon --input pigeons/native_bridge.dart 执行成功，生成 Dart、Kotlin 和 Swift 桥接文件，且无静态检查错误
- [ ] Flutter 项目依赖安装完整，项目可通过静态分析检查（flutter analyze 无致命错误）

### 数据库与核心数据层
- [ ] 12 张数据表、外键级联（如 refund_links ON DELETE CASCADE 原消费彻底删除解绑）与 11 项索引在 SQLite 引擎中验证通过
- [ ] 金额以最小货币单位整数（cents/分）存储，无浮点数精度截断问题

### 自动化测试与验证
- [ ] 核心模型层、数据层与解析引擎的自动化单元测试/集成测试全部执行并通过（Exit code 0）


## 2026-10-23T01:15:17Z

SingWallet Milestone M2 核心业务 UI 与交互全量落地：基于已验证的 M0/M1 核心引擎与数据层，构建生产级 Flutter Material 3 界面体系，包含 Riverpod 状态总线、流水明细看板、截图草稿箱 OCR 视觉证据高亮确认页、分类规则中心与账户项目管理，并编写配套的 Widget 测试与交互验证套件。

Working directory: c:\Other\Projects\singwallet
Integrity mode: development

参考既有规范与引擎：
- 统一数据层与事务底座：lib/data/database/app_database.dart 与 lib/data/database/transaction_manager.dart
- 四层防重引擎：lib/data/deduplication/deduplication_engine.dart
- 8 阶段 OCR 解析流水线：lib/recognition/ocr_pipeline.dart
- 6 级分类决策链：lib/classification/rule_engine.dart
- 既有单元与对抗测试套件（297 项测试通过）：test/

## Requirements

### R1. Riverpod 状态管理层与视图模型（Providers & ViewModels）
建立干净的 Presentation 状态层，将已有的 AppDatabase、TransactionManager、OcrPipeline 与 ClassificationRuleEngine 注入全局依赖。提供响应式的流水列表 Stream/Notifier、草稿箱队列、分类/账户/项目字典及全局筛选状态。

### R2. 流水明细主屏与资产大盘（Transactions Screen）
实现首页核心流水主视图：
- 顶部动态收支结余看板（本月总支出、总收入、净结余）；
- 按日期聚合的流水列表（包含每日小计、商户名、分类图标、支付账户胶囊、项目标签、退款标记）；
- 多维筛选面板（按账户、项目、分类、日期范围与关键字）；
- 账目软删除、撤回与回收站彻底清理交互。

### R3. 截图草稿箱与 OCR 视觉证据高亮确认页（Draft Confirmation Screen）
实现记账核心交互：
- 截图展示区与 OCR 文本包围盒高亮覆盖层：基于归一化坐标 OcrBoundingBox（原点在左上角 [0.0, 1.0]）绘制半透明高亮线框，支持点击文本框将识别内容快速回填至商户名或金额；
- 智能表单：大字展示实付金额、支付渠道与交易状态选择、商户名修正、建议分类高亮卡片（展示匹配置信度）；
- 四层防重提示拦截：Tier 3 订单号冲突强制阻断提示，Tier 4 启发式疑似重复交易弹出二次确认对话框；
- 一键事务入账与草稿状态流转（IDENTIFIED -> CONFIRMED）。

### R4. 分类规则管理与账户/项目配置中心（Rules & Accounts Screen）
- 规则中心：展示 6 级规则列表，支持关键字/通配符规则的添加、修改、启用/停用、匹配优先级拖拽调整与一键重新匹配；
- 账户与项目管理：账户列表（现金、微信、支付宝、银行卡等）与余额概览；项目管理（差旅、装修等）；
- 退款关联弹窗：支持在支出账目中检索并关联已有退款记录（符合 refund_links ON DELETE CASCADE 规范）。

### R5. Widget 测试与端到端交互验证套件
为上述核心页面与关键组件编写 Flutter Widget 测试套件（流水看板渲染、OCR 包围盒坐标映射与点击回填、四层防重弹窗交互拦截、规则启停切换），确保测试全绿且 flutter analyze 零缺陷。

## Acceptance Criteria

### 代码质量与静态分析
- [ ] flutter analyze 保持 0 issues found（零错误、零警告、零 lints 违规，退出码 0）
- [ ] 架构分层严谨清晰，UI 逻辑与领域/数据层解耦

### 交互与业务完整性
- [ ] OCR 证据高亮层在不同屏幕比例下准确映射归一化坐标 [0.0, 1.0]，无越界变形
- [ ] 重复订单号与 24h 启发式防重在 UI 层触发正确的阻断与确认对话框
- [ ] 账目确认入账后，主屏流水列表与看板结余能即时响应式刷新
- [ ] 退款关联操作符合外键完整性约束

### 自动化测试覆盖
- [ ] 新增的 UI Widget 测试与已有 297 项后端测试共同组成全量测试套件，flutter test 全部执行通过（100% Pass，退出码 0）
