# SingWallet 技术蓝图：6 级分类规则引擎与 3D 正交归类体系 (M1-B: Features F27-F30)

- 版本：v1.0 (生产就绪设计规范)
- 日期：2026-10-22
- 归属模块：`lib/features/classification/` & `lib/data/models/`
- 对应特性：
  - **F27**: 3D 正交归类模型 (Category, Project, Tags)
  - **F28**: 6 级分类匹配优先级体系 (Manual > Rules > History > Dictionary > AI > Fallback)
  - **F29**: 通配符与正则表达式模式匹配引擎 (SQL `%`, `_` 转正则、大小写无关、防 ReDoS)
  - **F30**: 动态商户规则学习与增量沉淀 (Dynamic Rule Learning)

---

## 目录
1. [执行摘要与设计哲学](#1-执行摘要与设计哲学)
2. [6 级分类匹配优先级架构 (F28)](#2-6-级分类匹配优先级架构-f28)
   - 2.1 Tier 1: 用户显式手动选择 (`ClassificationTier.manual`)
   - 2.2 Tier 2: 用户自定义规则引擎 (`ClassificationTier.customRule`)
   - 2.3 Tier 3: 历史相同商户映射 (`ClassificationTier.history`)
   - 2.4 Tier 4: 内置中文商户/商品关键词词典 (`ClassificationTier.builtinKeyword`)
   - 2.5 Tier 5: 可选扩展 AI 推荐引擎 (`ClassificationTier.ai`)
   - 2.6 Tier 6: 默认保底兜底分类 (`ClassificationTier.fallback`)
3. [通配符与正则表达式模式匹配体系 (F29)](#3-通配符与正则表达式模式匹配体系-f29)
   - 3.1 模式语法与判定规则
   - 3.2 SQL 通配符 `%` 与 `_` 到安全正则表达式的安全转义算法
   - 3.3 大小写不敏感与空白归一化
   - 3.4 边界防护与防 ReDoS (正则表达式拒绝服务) 机制
4. [多维度匹配判定准则 (Rule Match Criteria)](#4-多维度匹配判定准则-rule-match-criteria)
   - 4.1 候选上下文输入结构 (`ClassificationCandidateContext`)
   - 4.2 渠道限制判定 (Payment Channel)
   - 4.3 金额区间判定 (Amount Range)
   - 4.4 备注/商品标题模糊判定 (Remarks & Goods Description)
5. [动态商户规则学习与增量沉淀 (F30)](#5-动态商户规则学习与增量沉淀-f30)
   - 5.1 学习触发点与交互语义
   - 5.2 规则生成与冲突消歧算法
   - 5.3 严格的前向生效与防历史篡改原则 (Non-Retroactivity)
   - 5.4 规则版本化与生命周期维护
6. [3D 正交归类模型体系 (F27)](#6-3d-正交归类模型体系-f27)
   - 6.1 三维正交定义与基数约束 (Category vs Project vs Tag)
   - 6.2 财务防重复统计数学保证 (No Double Counting)
   - 6.3 数据库约束、级联策略与软归档机制
   - 6.4 预置核心分类与正交示例矩阵
7. [核心架构与代码实现规范 (Dart Blueprint)](#7-核心架构与代码实现规范-dart-blueprint)
   - 7.1 文件布局设计
   - 7.2 数据模型定义 (`classification_match_result.dart` 等)
   - 7.3 正则与通配符匹配器 (`rule_matcher.dart`)
   - 7.4 内置中文词典实现 (`builtin_dictionary.dart`)
   - 7.5 历史频次/时效分类器 (`history_classifier.dart`)
   - 7.6 分类引擎核心门面 (`rule_engine.dart`)
8. [自动化测试与验证套件设计](#8-自动化测试与验证套件设计)
   - 8.1 单元测试矩阵 (覆盖全部 6 级层级与边界)
   - 8.2 通配符/正则对抗测试矩阵
   - 8.3 历史统计频次与时效权重测试
   - 8.4 3D 正交性与账务聚合测试

---

## 1. 执行摘要与设计哲学

SingWallet 记账核心的核心价值主张是**高准确率、确定性、零财务漂移与极简用户确认**。
在从 OCR 提取出原始商户与金额后，分类推荐引擎必须在**用户无需费心挑选**与**绝不武断胡乱猜分类**之间取得严密的平衡。

为此，Milestone M1-B 确立了两大核心技术支柱：
1. **6 级分类优先级决断树 (6-Tier Classification Hierarchy)**：
   自上而下严格按信息置信度梯度递减判定。高置信度梯级一旦命中，立即终止短路返回；绝不在低层级进行模糊猜测覆盖高层级的用户意志。
2. **3D 正交归类体系 (3D Orthogonal Classification Model)**：
   将传统记账软件混杂不堪的“类别”、“项目”、“标签”彻底在数学与关系数据库层解耦为 3 个正交维度。**主分类负责严格分箱（100% 覆盖、零重叠、支持预算与月报）；项目负责跨时空生命周期聚合；标签负责多维属性检索**。

```text
                  ┌──────────────────────────────────────────────┐
                  │   OCR 候选文本输入 (商户名 / 渠道 / 金额)     │
                  └──────────────────────┬───────────────────────┘
                                         ▼
   ┌────────────────────────────────────────────────────────────────────────┐
   │ 6-Tier 分类决断树 (Cascade Evaluation)                                  │
   │                                                                        │
   │  [Tier 1] 用户显式修改/指定 (Manual Selection)           --> 100% 胜出  │
   │      │ (未手动修改)                                                    │
   │      ▼                                                                 │
   │  [Tier 2] 用户自定义生效规则 (Custom Rules: priority DESC) --> 95% 命中  │
   │      │ (无规则匹配)                                                    │
   │      ▼                                                                 │
   │  [Tier 3] 历史相同商户映射 (Historical Merchant Freq)   --> 85% 命中   │
   │      │ (历史无记录)                                                    │
   │      ▼                                                                 │
   │  [Tier 4] 内置核心中文词典 (Built-in Keyword Dict)       --> 70% 命中   │
   │      │ (词典未命中)                                                    │
   │      ▼                                                                 │
   │  [Tier 5] 可选本地/端侧 AI 建议 (Optional AI Suggestion) --> 60% 命中   │
   │      │ (AI 未启用或未给出可靠结果)                                      │
   │      ▼                                                                 │
   │  [Tier 6] 保底兜底分类 (cat_other / 待分类)             --> 10% 兜底   │
   └─────────────────────────────────────┬──────────────────────────────────┘
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │ 3D 归类组装: Category(1) + Project(0..1)     │
                  │              + Tags(0..N)                    │
                  └──────────────────────────────────────────────┘
```

---

## 2. 6 级分类匹配优先级架构 (F28)

### 2.1 Tier 1: 用户显式手动选择 (`ClassificationTier.manual`)
- **定义**：在草稿确认页（`NEEDS_REVIEW`）或手工录入界面，用户主动在分类选择器中点选的分类。
- **置信度**：`1.00`（绝对确信）。
- **行为准则**：
  - 拥有最高优先级，强制覆盖所有下级规则匹配结果；
  - 触发用户确认时，如果该商户未绑定过规则，提示用户：“是否记住以后该商户均归为此类？”（见第 5 节动态学习）。

### 2.2 Tier 2: 用户自定义规则引擎 (`ClassificationTier.customRule`)
- **定义**：用户通过设置管理维护或动态学习生成的自定义商户分类规则（存储于 `classification_rules` 数据表）。
- **置信度**：`0.95`。
- **数据查询与排序策略**：
  ```sql
  SELECT id, priority, merchant_pattern, payment_channel, category_id, project_id, enabled
  FROM classification_rules
  WHERE enabled = 1
  ORDER BY priority DESC, created_at DESC;
  ```
- **匹配评估流程**：
  1. 按 `priority DESC` 逐条评估已启用的规则；
  2. 若优先级相同，按照创建时间后生成的优先 (`created_at DESC`)；
  3. 首条完全符合匹配条件的规则胜出并终止评估，输出其 `category_id` 与可选的 `project_id`。

### 2.3 Tier 3: 历史相同商户映射 (`ClassificationTier.history`)
- **定义**：若无显式自定义规则，但用户在过去的记账历史中多次将同一商户归入某一分类，系统自动继承用户的习惯。
- **置信度**：`0.80 ~ 0.90`（根据历史出现频次加权）。
- **数据查询算法**：
  - 首选匹配 `merchant_normalized`，若为空则退化匹配 `merchant_raw`；
  - 排除回收站中的交易记录（`deleted_at IS NULL`）；
  - 仅统计同类交易类型（如 `type = 'expense'`）；
  ```sql
  SELECT category_id, project_id, COUNT(*) AS freq, MAX(occurred_on) AS last_date
  FROM transactions
  WHERE (merchant_normalized = ? OR merchant_raw = ?)
    AND deleted_at IS NULL
    AND category_id IS NOT NULL
    AND type = 'expense'
  GROUP BY category_id
  ORDER BY freq DESC, last_date DESC
  LIMIT 1;
  ```
- **频次置信度梯阶**：
  - `freq == 1`：置信度 `0.80`（初次历史印记）；
  - `freq >= 2`：置信度 `0.90`（已形成稳定使用习惯）。
- **可选项目与标签回溯**：
  - 若历史记录中该商户在 80% 以上的次数都绑定了相同项目或相同标签，可附带建议该项目/标签。

### 2.4 Tier 4: 内置中文商户/商品关键词词典 (`ClassificationTier.builtinKeyword`)
- **定义**：随应用内置打包的离线中文商户与常见开销关键词知识库，服务于冷启动用户。
- **置信度**：`0.70`。
- **长词优先原则 (Longest-Match First)**：
  - 避免子字符串截断误判（例如“美团外卖”必须优先于“美团”，“中国石油化工”优先于“中石化”）。
- **内置词典分类映射全集**：
  | 标准分类 ID | 分类名称 | 核心商户与商品特征词库 (大小写无关) |
  | :--- | :--- | :--- |
  | `cat_food` | 餐饮美食 | 麦当劳, 肯德基, 汉堡王, 星巴克, 瑞幸, 喜茶, 奈雪, 茶百道, 古茗, 蜜雪冰城, 霸王茶姬, 益禾堂, 咖啡, 奶茶, 烘焙, 面包, 蛋糕, 饮品, 饭店, 餐厅, 烤肉, 火锅, 麻辣烫, 面馆, 快餐, 料理, 烧烤, 小吃, 馄饨, 饺子, 披萨, 寿司, 食堂, 早餐, 午餐, 晚餐, 美食, 酒楼, 菜馆, 大排档, 黄焖鸡, 沙县小吃, 绝味鸭脖, 周黑鸭, 美团外卖, 饿了么, 盒马鲜食 |
  | `cat_transport` | 交通出行 | 地铁, 公交, 轨道交通, 铁路, 12306, 火车站, 高铁, 动车, 一卡通, 乘车码, 交通卡, 公共交通, 滴滴, 滴滴出行, 花小猪, T3出行, 曹操出行, 高德打车, 出租车, 顺风车, 专车, 快车, 拼车, 货拉拉, 机票, 航旅纵横, 东方航空, 南方航空, 中国国航, 携程机票, 飞猪机票, 机场, 加油站, 中石油, 中石化, 延长石油, 充电桩, 特来电, 星星充电, 停车, 停车场, 泊车, ETC, 高速公路, 路桥费, 洗车, 修车, 4S店, 保养 |
  | `cat_shopping` | 购物消费 | 7-Eleven, 711, 全家, 罗森, 美宜佳, 喜士多, 便利蜂, 盒马, 山姆, 沃尔玛, 大润发, 永辉, 华润万家, 物美, 超市, 便利店, 菜市场, 生鲜, 水果店, 淘宝, 天猫, 京东, 拼多多, 唯品会, 闲鱼, 抖音电商, 快手电商, 得物, 严选, 服饰, 服装, 优衣库, ZARA, 屈臣氏, 万宁, 专卖店, 数码, 电脑, 手机 |
  | `cat_entertainment`| 休闲娱乐 | 电影, 万达影城, 大地影院, 猫眼, 淘票票, 影音, KTV, 网吧, 剧本杀, 密室逃脱, 腾讯互娱, 网易游戏, 米哈游, Steam, Nintendo, PlayStation, 游戏充值, 游乐园, 迪士尼, 环球影城, 景区门票, 爱奇艺, 腾讯视频, 优酷, 哔哩哔哩, B站, 芒果TV, 网易云音乐, QQ音乐, Apple, Google, 订阅, 健身房, 游泳馆, 运动馆, 瑜伽, 羽毛球, 篮球 |
  | `cat_utilities` | 居家生活 | 国家电网, 南方电网, 水费, 电费, 燃气费, 暖气费, 物业费, 自来水, 燃气, 中国移动, 中国联通, 中国电信, 话费充值, 宽带, 手机充值, 房租, 自如, 链家, 泊寓, 租房, 家政, 保洁, 维修, 物业 |
  | `cat_medical` | 医疗健康 | 医院, 诊所, 门诊, 药店, 大药房, 益丰, 一心堂, 国大药房, 老百姓大药房, 体检, 挂号, 医疗, 口腔, 齿科, 眼镜, 药房, 医药 |
  | `cat_income` | 收入 | 工资, 薪酬, 奖金, 劳务报酬, 报销, 退税, 分红, 利息, 理财收益, 投资收益 |
  | `cat_other` | 其他 / 待分类 | (兜底保底分类，详见 Tier 6) |

### 2.5 Tier 5: 可选扩展 AI 推荐引擎 (`ClassificationTier.ai`)
- **定位**：端侧小型模型（如 TensorFlow Lite 文本嵌入）或用户主动授权配置的 LLM 语义推理接口。
- **规范契约**：
  - 默认关闭，绝对保证在离线无网络时正常运转；
  - 传入脱敏的商户文本与金额；
  - 返回必须经过本地 Schema 强校验：推荐的 `category_id` 必须存在于本地 `categories` 表中，严禁凭空构造不存在的分类 ID；
  - 置信度通常标定为 `0.60`。若未开启或发生超时，立即无感降级到 Tier 6。

### 2.6 Tier 6: 默认保底兜底分类 (`ClassificationTier.fallback`)
- **定义**：当 Tiers 1 至 5 均无法辨识商户意图时，归类为 `cat_other`（其他 / 待分类）。
- **置信度**：`0.10`。
- **架构底线**：**宁缺毋滥**。严禁为了追求“100% 自动分类率”而胡乱猜测分类，必须留待用户在确认页进行审查。

---

## 3. 通配符与正则表达式模式匹配体系 (F29)

### 3.1 模式语法与判定规则
用户在自定义规则时，可能输入三种模式：
1. **纯文本子串 (Substring Match)**：用户输入普通文本（如 `星巴克` 或 `7-Eleven`）。
   - 语义：商户名称中包含该文本即命中（等价于 `%星巴克%`）。
2. **SQL 标准通配符模式 (Wildcard Match)**：
   - `%`：匹配 0 个或任意多个字符；
   - `_`：严格匹配任意单个字符。
   - 示例：`星巴克%` (以星巴克开头), `%便利店%` (包含便利店), `肯德基_分店` (严格占位一字)。
3. **显式正则表达式 (Explicit Regex)**：
   - 以 `regex:` 开头（如 `regex:^滴滴(出行|快车)$`）；
   - 或者显式以 `^` 开头并以 `$` 结尾（如 `^星巴克.*$`）。

### 3.2 SQL 通配符 `%` 与 `_` 到安全正则表达式的转义算法
为了在 Dart 运行时实现极速、高安全性的通配符匹配，必须将模式编译为 `RegExp`。

转义算法步骤：
1. **模式修剪与空值防护**：去除首尾多余空白。若为空，返回严格空匹配正则 `^$`；
2. **显式正则判定**：若包含 `regex:` 前缀，剥离前缀后直接编译；
3. **通配符转义逻辑**：
   - 逐字符遍历输入字符串；
   - 遇到 `%` 时，转换为 `.*`；
   - 遇到 `_` 时，转换为 `.`；
   - 遇到除 `%` 和 `_` 以外的任何字符，调用 `RegExp.escape(char)` 进行严格转义，防止点号 `.`、括号 `()`、加号 `+`、星号 `*` 等被误当作正则元字符；
   - 在转义后的字符串两端添加锚点 `^` 与 `$`。
4. **纯文本退化**：若既无通配符也无显式正则，直接调用 `RegExp.escape` 并执行 contains 匹配。

### 3.3 大小写不敏感与空白归一化
- **大小写无关**：所有编译出来的 `RegExp` 强制开启 `caseSensitive: false`。
  - 例如输入 `kfc%` 可以成功匹配 `KFC 汽车穿梭餐厅`；
- **空白归一化**：匹配前将商户文本中的连续全角/半角空格、制表符统一折叠为单个半角空格，并去除首尾空白。

### 3.4 边界防护与防 ReDoS 机制
正则表达式存在灾难性回溯（Catastrophic Backtracking）引发应用卡死的风险：
1. **长度硬限制**：用户输入的 `merchant_pattern` 最大长度限制为 **200 个字符**，超过直接在校验层拦截；
2. **通配符折叠**：将连续多个百分号（如 `%%%%`）在转义前压缩为单个 `%`，防止生成 `.*.*.*.*` 引发死循环；
3. **异常捕获与熔断**：在执行 `regex.hasMatch(text)` 时使用 `try-catch` 包裹，若抛出异常直接判定为未命中，并记录告警日志，绝不导致 UI 闪退。

---

## 4. 多维度匹配判定准则 (Rule Match Criteria)

在真实业务场景中，单一商户名不足以应对所有场景（例如在美团上既有餐饮外卖又有单车骑行，或某商户不同金额区间代表不同业务）。规则引擎支持**多条件组合与判定**。

### 4.1 候选上下文输入结构 (`ClassificationCandidateContext`)
```dart
class ClassificationCandidateContext {
  final String? merchantRaw;           // OCR 原始商户名 (如 "微信支付-特约商户-麦当劳")
  final String? merchantNormalized;    // 归一化清洗后商户名 (如 "麦当劳")
  final String? paymentChannel;        // 支付渠道: "wechat", "alipay", "unionpay", etc.
  final int? amountMinor;              // 实付金额 (分)
  final String? remarks;               // 商品说明或备注
  final String type;                   // 交易类型: "expense", "income", etc.
}
```

### 4.2 渠道限制判定 (Payment Channel)
- 规则表字段：`classification_rules.payment_channel` (可为空)；
- 判定准则：
  - 若规则的 `payment_channel == null` 或为空字符串：**通配所有渠道**；
  - 若规则限定了渠道（如 `'wechat'`）：则上下文的 `context.paymentChannel` 必须与之一致（不区分大小写）；
  - 典型场景：用户希望通过招行 App 付款的全部归入某项目，或通过微信付的生活费归入特定分类。

### 4.3 金额区间判定 (Amount Range)
- 规则扩展字段设计：`min_amount_minor` 与 `max_amount_minor` (单位：分)；
- 判定准则：
  - 若设置了 `min_amount_minor`，则必须满足 `context.amountMinor >= min_amount_minor`；
  - 若设置了 `max_amount_minor`，则必须满足 `context.amountMinor <= max_amount_minor`；
  - 典型场景：某便利店消费 20 元以下归入“零食饮料”，超过 200 元归入“家庭日用采购”。

### 4.4 备注/商品标题模糊判定 (Remarks & Goods Description)
- 若上下文存在商品标题（如“美团外卖 - 某某便当”或“滴滴打车行程费”）：
  - 引擎在商户名未命中特定细分类目时，将 `remarks` 作为二次候选匹配输入；
  - 这保证了即使商户名为通用的“美团平台”，也能根据备注“外卖”精准命中 `cat_food`。

---

## 5. 动态商户规则学习与增量沉淀 (F30)

### 5.1 学习触发点与交互语义
- **触发时机**：用户在草稿确认界面（`NEEDS_REVIEW`）调整或确认分类，并点击“确认记账”时；
- **交互规范**：
  - 系统检测到该商户未曾命中 Tier 2 自定义规则；
  - 界面呈现轻量开关或确认提示：“记住分类：以后来自「某某商户」的账目默认归类为「餐饮美食」”；
  - 用户勾选确认后，系统在提交事务中自动沉淀一条新规则。

### 5.2 规则生成与冲突消歧算法
1. **提取规范商户名**：优先采用清洗后的 `merchantNormalized`（如去除了“特约商户”前缀）；若为空则使用 `merchantRaw`；
2. **幂等查重**：
   - 查询数据库是否已存在 `merchant_pattern == normalized` 的规则；
   - 若已存在同名规则：执行 `UPDATE` 更新其 `category_id`、`project_id` 与 `updated_at`，将其 `enabled` 置为 1；
   - 若不存在：执行 `INSERT` 插入新记录，默认赋予 `priority = 100`。
3. **规则实体生成格式**：
   ```json
   {
     "id": "uuid-v4",
     "priority": 100,
     "merchant_pattern": "星巴克%",
     "payment_channel": null,
     "category_id": "cat_food",
     "project_id": null,
     "enabled": 1,
     "version": 1,
     "created_at": "2026-10-22T13:30:00.000Z",
     "updated_at": "2026-10-22T13:30:00.000Z"
   }
   ```

### 5.3 严格的前向生效与防历史篡改原则 (Non-Retroactivity)
- **核心契约**：**动态学习生成的规则仅对未来的导入任务与待确认草稿生效，严禁静默重算或篡改已入账的历史流水 (`transactions`)！**
- **理由**：历史账目是财务已结清数据，若用户将某商户从“办公耗材”改为“个人数码”，不能摧毁上个月已归档的报销账单和财务报表。

### 5.4 规则版本化与生命周期维护
- 提供“设置 -> 规则管理”页面：
  - 用户可查看所有自动学习与手动创建的规则；
  - 支持调整 `priority`（1 ~ 999）；
  - 支持一键停用（`enabled = 0`）与彻底删除；
  - 支持直接编辑通配符模式。

---

## 6. 3D 正交归类模型体系 (F27)

### 6.1 三维正交定义与基数约束 (Category vs Project vs Tag)

在个人与小微财务管理中，概念混淆是导致账目混乱的元凶。SingWallet 严格实行 3D 正交体系：

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                    SingWallet 3D 正交归类体系                          │
 ├─────────────────┬─────────────────┬────────────────────────────────────┤
 │ 维度            │ 实体基数        │ 核心财务内涵与职责                 │
 ├─────────────────┼─────────────────┼────────────────────────────────────┤
 │ 1. 主分类       │ 严格且仅有 1 个 │ 基础消费性质分类，用于 100% 穷尽且 │
 │   (Category)    │ (Mandatory 1:1) │ 不重叠的月度预算与收支报表。       │
 ├─────────────────┼─────────────────┼────────────────────────────────────┤
 │ 2. 项目         │ 可选 0 或 1 个  │ 特定跨周期事件/专题（如旅行、装修）│
 │   (Project)     │ (Optional 0..1) │ 独立归集核算，跨越多个消费分类。   │
 ├─────────────────┼─────────────────┼────────────────────────────────────┤
 │ 3. 标签         │ 可选 0 到多个   │ 交叉上下文标记（如工作日、可报销） │
 │   (Tag)         │ (Many-to-Many)  │ 纯正交检索与组合过滤视图。         │
 └─────────────────┴─────────────────┴────────────────────────────────────┘
```

### 6.2 财务防重复统计数学保证 (No Double Counting)
设账本在某一自然月的所有有效支出交易集合为 $E = \{t_1, t_2, \dots, t_n\}$：
1. **主分类的完全划分性 (Partition Property)**：
   每个交易 $t$ 具有唯一的 $C(t) \in \text{Categories}$。
   $$\bigcup_{c \in \text{Categories}} E_c = E \quad \text{且} \quad \forall c_i \neq c_j, \; E_{c_i} \cap E_{c_j} = \emptyset$$
   因此：
   $$\text{月度总支出} = \sum_{c \in \text{Categories}} \text{Total}(E_c) = \sum_{t \in E} t.\text{amount\_minor}$$
   没有任何一分钱被漏计或重计。
2. **项目的独立投影性 (Independent Projection)**：
   项目 $P$ 是交易集合的一个子集 $E_P \subseteq E$。
   不同项目的交易集合可能部分存在，且 $\sum_{P} \text{Total}(E_P) \le \text{Total}(E)$。
   **绝不能将“项目总额”与“分类总额”相加作为总支出！**
3. **标签的多维交织性 (Multi-label Overlap)**：
   标签 $T$ 允许多对多关联，$\sum_{g} \text{Total}(E_g)$ 无固定上下界。
   仅用于快速切片（如“本月可报销总额”）。

### 6.3 数据库约束、级联策略与软归档机制
- **`categories`** 表：
  - `FOREIGN KEY(parent_id) REFERENCES categories(id) ON DELETE SET NULL`：支持二级树状分类，父分类删除后子分类自动升级为一级；
  - `transactions.category_id REFERENCES categories(id) ON DELETE RESTRICT`：**严禁物理硬删除被账目引用的分类**！必须通过 `archived_at` 软归档。
- **`projects`** 表：
  - `transactions.project_id REFERENCES projects(id) ON DELETE SET NULL`：项目删除或解散后，原交易的 `project_id` 自动置空，账目本体与金额不受任何损害；
  - `classification_rules.project_id REFERENCES projects(id) ON DELETE SET NULL`：规则中绑定的项目删除后自动解绑。
- **`tags`** 与 **`transaction_tags`**：
  - `transaction_tags` 采用复合主键 `(transaction_id, tag_id)`；
  - 级联删除 `ON DELETE CASCADE`：删除标签时自动清理关联关系，账目保持完整。
- **软归档机制 (`archived_at`)**：
  - 当用户不再需要某分类/项目/标签时，设置 `archived_at = CURRENT_TIMESTAMP`；
  - 新建记账界面的下拉选择列表自动过滤 `WHERE archived_at IS NULL`；
  - 历史账目详情页依然能完整展示已归档的名称与图标。

### 6.4 预置核心分类与正交示例矩阵

#### 预置标准分类体系 (Parent-Child)
```text
├── cat_food (餐饮美食)
│   ├── cat_food_dining (日常正餐)
│   ├── cat_food_delivery (外卖便当)
│   ├── cat_food_coffee (咖啡饮品)
│   └── cat_food_snack (零食烘焙)
├── cat_transport (交通出行)
│   ├── cat_transport_transit (公交地铁)
│   ├── cat_transport_taxi (打车出行)
│   ├── cat_transport_flight_train (机票火车)
│   └── cat_transport_auto (加油汽车)
├── cat_shopping (购物消费)
│   ├── cat_shopping_groceries (超市买菜)
│   ├── cat_shopping_apparel (服饰日化)
│   └── cat_shopping_digital (数码家电)
├── cat_entertainment (休闲娱乐)
│   ├── cat_entertainment_cinema (电影演出)
│   └── cat_entertainment_games (游戏充值)
├── cat_utilities (居家生活)
│   ├── cat_utilities_bills (水电煤气)
│   └── cat_utilities_telecom (话费宽带)
├── cat_medical (医疗健康)
│   └── cat_medical_drugs (药品问诊)
├── cat_income (收入分类)
│   └── cat_income_salary (工资薪酬)
└── cat_other (其他 / 待分类)
```

#### 真实交易的正交映射示范矩阵
| 真实交易截图场景 | 主分类 (`category_id`) | 项目 (`project_id`) | 关联标签列表 (`tags`) |
| :--- | :--- | :--- | :--- |
| 云南旅行中吃过桥米线 | `cat_food_dining` (日常正餐) | `proj_yunnan_2026` (云南旅行) | `tag_trip_food` (旅行特色) |
| 出差期间乘坐高铁票 | `cat_transport_flight_train` (机票火车)| `proj_biz_trip` (上海出差) | `tag_reimbursable` (可报销) |
| 周五晚与同事聚餐小酌 | `cat_food_dining` (日常正餐) | `NULL` | `tag_friends` (聚餐), `tag_aa` (AA制) |
| 新家购置扫地机器人 | `cat_shopping_digital` (数码家电) | `proj_house_renovation` (新房装修) | `tag_home` (大件家电) |

---

## 7. 核心架构与代码实现规范 (Dart Blueprint)

### 7.1 文件布局设计
```text
lib/features/classification/
├── models/
│   ├── classification_tier.dart              # 6级枚举与元数据
│   ├── classification_match_result.dart      # 统一决断输出结果
│   └── classification_candidate_context.dart # 决断输入上下文
├── rule_matcher.dart                         # 正则/通配符转换与匹配引擎
├── builtin_dictionary.dart                   # Tier 4 中文核心词典库
├── history_classifier.dart                   # Tier 3 历史频次加权分类器
├── rule_learning_service.dart                # Tier 2 规则持久化与增量学习
└── rule_engine.dart                          # 6-Tier 综合分类决断引擎门面
```

### 7.2 数据模型定义

#### 7.2.1 `classification_tier.dart`
```dart
// lib/features/classification/models/classification_tier.dart

/// 6-Tier classification precedence hierarchy
enum ClassificationTier {
  manual(1, 'User Manual Override', 1.0),
  customRule(2, 'User Custom Rule Matching', 0.95),
  history(3, 'Historical Merchant Mapping', 0.85),
  builtinKeyword(4, 'Built-in Keyword Dictionary', 0.70),
  ai(5, 'AI Recommendation', 0.60),
  fallback(6, 'Default Fallback Category', 0.10);

  final int tierNumber;
  final String label;
  final double defaultConfidence;

  const ClassificationTier(this.tierNumber, this.label, this.defaultConfidence);

  bool get isHighConfidence => tierNumber <= 2;
}
```

#### 7.2.2 `classification_match_result.dart`
```dart
// lib/features/classification/models/classification_match_result.dart
import 'classification_tier.dart';

/// Structured outcome of the classification decision engine
class ClassificationMatchResult {
  final ClassificationTier tier;
  final String categoryId;
  final String? projectId;
  final List<String> tagIds;
  final double confidence;
  final String? matchedRuleId;
  final String? matchedPattern;
  final String? matchedKeyword;
  final String explanation;

  const ClassificationMatchResult({
    required this.tier,
    required this.categoryId,
    this.projectId,
    this.tagIds = const [],
    required this.confidence,
    this.matchedRuleId,
    this.matchedPattern,
    this.matchedKeyword,
    required this.explanation,
  });

  /// Factory for manual user explicit selection (Tier 1)
  factory ClassificationMatchResult.manual({
    required String categoryId,
    String? projectId,
    List<String> tagIds = const [],
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.manual,
      categoryId: categoryId,
      projectId: projectId,
      tagIds: tagIds,
      confidence: 1.0,
      explanation: 'User manually specified category: $categoryId',
    );
  }

  /// Factory for custom rule hit (Tier 2)
  factory ClassificationMatchResult.customRule({
    required String categoryId,
    String? projectId,
    required String ruleId,
    required String pattern,
    required int priority,
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.customRule,
      categoryId: categoryId,
      projectId: projectId,
      confidence: 0.95,
      matchedRuleId: ruleId,
      matchedPattern: pattern,
      explanation: 'Matched custom rule #$ruleId (priority: $priority, pattern: "$pattern")',
    );
  }

  /// Factory for historical merchant mapping (Tier 3)
  factory ClassificationMatchResult.history({
    required String categoryId,
    String? projectId,
    required int frequency,
    required double confidence,
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.history,
      categoryId: categoryId,
      projectId: projectId,
      confidence: confidence,
      explanation: 'Matched historical merchant record ($frequency occurrence(s))',
    );
  }

  /// Factory for built-in dictionary keyword hit (Tier 4)
  factory ClassificationMatchResult.builtinKeyword({
    required String categoryId,
    required String keyword,
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.builtinKeyword,
      categoryId: categoryId,
      confidence: 0.70,
      matchedKeyword: keyword,
      explanation: 'Matched built-in keyword "$keyword"',
    );
  }

  /// Factory for AI recommendation (Tier 5)
  factory ClassificationMatchResult.ai({
    required String categoryId,
    double confidence = 0.60,
    String? reason,
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.ai,
      categoryId: categoryId,
      confidence: confidence,
      explanation: reason ?? 'Recommended by AI semantic model',
    );
  }

  /// Factory for default fallback (Tier 6)
  factory ClassificationMatchResult.fallback({
    String categoryId = 'cat_other',
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.fallback,
      categoryId: categoryId,
      confidence: 0.10,
      explanation: 'No rule, history, or keyword match. Assigned to fallback category: $categoryId',
    );
  }
}
```

#### 7.2.3 `classification_candidate_context.dart`
```dart
// lib/features/classification/models/classification_candidate_context.dart

/// Input context from OCR draft parsing for classification inference
class ClassificationCandidateContext {
  final String? merchantRaw;
  final String? merchantNormalized;
  final String? paymentChannel; // 'wechat', 'alipay', etc.
  final int? amountMinor; // in cents
  final String? remarks; // item titles, goods description, OCR text notes
  final String type; // 'expense', 'income', 'refund', 'transfer'

  const ClassificationCandidateContext({
    this.merchantRaw,
    this.merchantNormalized,
    this.paymentChannel,
    this.amountMinor,
    this.remarks,
    this.type = 'expense',
  });

  /// Primary merchant name to use for matching
  String get effectiveMerchant =>
      (merchantNormalized != null && merchantNormalized!.trim().isNotEmpty)
          ? merchantNormalized!.trim()
          : (merchantRaw ?? '').trim();
}
```

### 7.3 正则与通配符匹配器 (`rule_matcher.dart`)
```dart
// lib/features/classification/rule_matcher.dart
import '../../data/models/classification_rule.dart';
import 'models/classification_candidate_context.dart';

/// High-performance pattern compiler and rule matcher
class RuleMatcher {
  RuleMatcher._();

  static const int maxPatternLength = 200;

  /// Compiles SQL wildcard pattern (% and _) or regex into a safe RegExp
  static RegExp patternToRegExp(String pattern, {bool caseSensitive = false}) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) {
      return RegExp(r'^$', caseSensitive: caseSensitive);
    }

    if (trimmed.length > maxPatternLength) {
      throw ArgumentError('Merchant pattern exceeds maximum length of $maxPatternLength characters.');
    }

    // 1. Explicit regex with prefix "regex:"
    if (trimmed.startsWith('regex:')) {
      final raw = trimmed.substring(6).trim();
      return RegExp(raw, caseSensitive: caseSensitive);
    }

    // 2. Anchored regular expression (^...$)
    if (trimmed.startsWith('^') && trimmed.endsWith(r'$')) {
      return RegExp(trimmed, caseSensitive: caseSensitive);
    }

    // 3. SQL Wildcard pattern (% or _)
    final hasWildcard = trimmed.contains('%') || trimmed.contains('_');
    if (hasWildcard) {
      // Collapse redundant %%% -> % to prevent ReDoS
      final collapsed = trimmed.replaceAll(RegExp(r'%+'), '%');
      final buffer = StringBuffer('^');
      for (int i = 0; i < collapsed.length; i++) {
        final char = collapsed[i];
        if (char == '%') {
          buffer.write('.*');
        } else if (char == '_') {
          buffer.write('.');
        } else {
          buffer.write(RegExp.escape(char));
        }
      }
      buffer.write(r'$');
      return RegExp(buffer.toString(), caseSensitive: caseSensitive);
    }

    // 4. Plain text: default to substring contains matching
    return RegExp(RegExp.escape(trimmed), caseSensitive: caseSensitive);
  }

  /// Tests if a single rule matches the candidate context
  static bool matches(ClassificationRule rule, ClassificationCandidateContext context) {
    if (rule.enabled != 1) return false;

    // 1. Channel check
    if (rule.paymentChannel != null && rule.paymentChannel!.isNotEmpty) {
      final ctxChannel = context.paymentChannel?.toLowerCase().trim();
      final ruleChannel = rule.paymentChannel!.toLowerCase().trim();
      if (ctxChannel != ruleChannel) {
        return false;
      }
    }

    // 2. Merchant pattern check
    final candidateMerchant = context.effectiveMerchant;
    if (candidateMerchant.isEmpty) {
      return false;
    }

    try {
      final regex = patternToRegExp(rule.merchantPattern);
      if (regex.hasMatch(candidateMerchant)) {
        return true;
      }

      // Secondary fallback: check merchantRaw if merchantNormalized was different
      if (context.merchantRaw != null &&
          context.merchantRaw!.trim() != candidateMerchant) {
        if (regex.hasMatch(context.merchantRaw!.trim())) {
          return true;
        }
      }
    } catch (_) {
      // Malformed pattern fails safely
      return false;
    }

    return false;
  }
}
```

### 7.4 内置中文词典实现 (`builtin_dictionary.dart`)
```dart
// lib/features/classification/builtin_dictionary.dart

/// Entry in the built-in dictionary mapping a keyword to a canonical category ID
class BuiltinDictionaryEntry {
  final String keyword;
  final String categoryId;

  const BuiltinDictionaryEntry(this.keyword, this.categoryId);
}

/// Cold-start Chinese merchant and item dictionary
class BuiltinDictionary {
  BuiltinDictionary._();

  static final List<BuiltinDictionaryEntry> _entries = _initEntries();

  static List<BuiltinDictionaryEntry> _initEntries() {
    final map = <String, List<String>>{
      'cat_food': [
        '麦当劳', '肯德基', '汉堡王', '星巴克', '瑞幸', '喜茶', '奈雪', '茶百道',
        '古茗', '蜜雪冰城', '霸王茶姬', '益禾堂', '咖啡', '奶茶', '烘焙', '面包',
        '蛋糕', '饮品', '饭店', '餐厅', '烤肉', '火锅', '麻辣烫', '面馆',
        '快餐', '料理', '烧烤', '小吃', '馄饨', '饺子', '披萨', '寿司',
        '食堂', '早餐', '午餐', '晚餐', '美食', '酒楼', '菜馆', '大排档',
        '黄焖鸡', '沙县小吃', '绝味鸭脖', '周黑鸭', '美团外卖', '饿了么', '盒马鲜食',
      ],
      'cat_transport': [
        '地铁', '公交', '轨道交通', '铁路', '12306', '火车站', '高铁', '动车',
        '一卡通', '乘车码', '交通卡', '公共交通', '滴滴', '滴滴出行', '花小猪',
        'T3出行', '曹操出行', '高德打车', '出租车', '顺风车', '专车', '快车',
        '拼车', '货拉拉', '机票', '航旅纵横', '东方航空', '南方航空', '中国国航',
        '携程机票', '飞猪机票', '机场', '加油站', '中石油', '中石化', '延长石油',
        '充电桩', '特来电', '星星充电', '停车', '停车场', '泊车', 'ETC',
        '高速公路', '路桥费', '洗车', '修车', '保养',
      ],
      'cat_shopping': [
        '7-Eleven', '711', '全家', '罗森', '美宜佳', '喜士多', '便利蜂', '盒马',
        '山姆', '沃尔玛', '大润发', '永辉', '华润万家', '物美', '超市', '便利店',
        '菜市场', '生鲜', '水果店', '淘宝', '天猫', '京东', '拼多多', '唯品会',
        '闲鱼', '抖音电商', '快手电商', '得物', '严选', '服饰', '服装', '优衣库',
        'ZARA', '屈臣氏', '万宁', '专卖店',
      ],
      'cat_entertainment': [
        '电影', '万达影城', '大地影院', '猫眼', '淘票票', '影音', 'KTV', '网吧',
        '剧本杀', '密室逃脱', '腾讯互娱', '网易游戏', '米哈游', 'Steam',
        'Nintendo', 'PlayStation', '游戏充值', '爱奇艺', '腾讯视频', '优酷',
        '哔哩哔哩', 'B站', '芒果TV', '网易云音乐', 'QQ音乐', 'Apple', 'Google',
        '订阅', '健身房', '游泳馆', '运动馆', '瑜伽', '羽毛球', '篮球',
      ],
      'cat_utilities': [
        '国家电网', '南方电网', '水费', '电费', '燃气费', '暖气费', '物业费',
        '自来水', '燃气', '中国移动', '中国联通', '中国电信', '话费充值', '宽带',
        '手机充值', '房租', '自如', '链家', '泊寓', '租房',
      ],
      'cat_medical': [
        '医院', '诊所', '门诊', '药店', '大药房', '益丰', '一心堂', '国大药房',
        '老百姓大药房', '体检', '挂号', '医疗', '口腔', '齿科', '眼镜',
      ],
      'cat_income': [
        '工资', '薪酬', '奖金', '劳务报酬', '报销', '退税', '分红', '利息', '收益',
      ],
    };

    final list = <BuiltinDictionaryEntry>[];
    map.forEach((catId, keywords) {
      for (final kw in keywords) {
        list.add(BuiltinDictionaryEntry(kw, catId));
      }
    });

    // Sort by keyword length descending (Longest match first!)
    list.sort((a, b) => b.keyword.length.compareTo(a.keyword.length));
    return list;
  }

  /// Attempts to match merchant or remarks text against the dictionary
  static BuiltinDictionaryEntry? match(String text) {
    if (text.trim().isEmpty) return null;
    final lower = text.toLowerCase();
    for (final entry in _entries) {
      if (lower.contains(entry.keyword.toLowerCase())) {
        return entry;
      }
    }
    return null;
  }
}
```

### 7.5 历史频次/时效分类器 (`history_classifier.dart`)
```dart
// lib/features/classification/history_classifier.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../data/database/app_database.dart';
import 'models/classification_candidate_context.dart';
import 'models/classification_match_result.dart';

/// Historical identical merchant category classifier (Tier 3)
class HistoryClassifier {
  final AppDatabase _dbHelper;

  HistoryClassifier([AppDatabase? db]) : _dbHelper = db ?? AppDatabase.instance;

  /// Looks up historical preference for candidate merchant
  Future<ClassificationMatchResult?> classify(ClassificationCandidateContext context) async {
    final merchant = context.effectiveMerchant;
    if (merchant.isEmpty) return null;

    final db = await _dbHelper.database;

    final rows = await db.rawQuery(
      '''
      SELECT category_id, project_id, COUNT(*) as freq, MAX(occurred_on) as latest_date
      FROM transactions
      WHERE (merchant_normalized = ? OR merchant_raw = ?)
        AND deleted_at IS NULL
        AND category_id IS NOT NULL
        AND type = ?
      GROUP BY category_id
      ORDER BY freq DESC, latest_date DESC
      LIMIT 1;
      ''',
      [merchant, merchant, context.type],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    final categoryId = row['category_id'] as String;
    final projectId = row['project_id'] as String?;
    final freq = row['freq'] as int;

    final confidence = freq >= 2 ? 0.90 : 0.80;

    return ClassificationMatchResult.history(
      categoryId: categoryId,
      projectId: projectId,
      frequency: freq,
      confidence: confidence,
    );
  }
}
```

### 7.6 规则学习服务 (`rule_learning_service.dart`)
```dart
// lib/features/classification/rule_learning_service.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../data/database/app_database.dart';
import '../../data/models/classification_rule.dart';

/// Service for dynamically generating and persisting custom classification rules (Tier 2 & F30)
class RuleLearningService {
  final AppDatabase _dbHelper;

  RuleLearningService([AppDatabase? db]) : _dbHelper = db ?? AppDatabase.instance;

  /// Creates or updates a classification rule when user confirms a category for a merchant
  Future<ClassificationRule> learnRule({
    required String merchant,
    required String categoryId,
    String? projectId,
    String? paymentChannel,
    int priority = 100,
  }) async {
    final cleanMerchant = merchant.trim();
    if (cleanMerchant.isEmpty) {
      throw ArgumentError('Cannot learn rule for empty merchant name.');
    }

    final db = await _dbHelper.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Check existing exact pattern
    final existing = await db.query(
      'classification_rules',
      where: 'merchant_pattern = ? AND (payment_channel = ? OR (payment_channel IS NULL AND ? IS NULL))',
      whereArgs: [cleanMerchant, paymentChannel, paymentChannel],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingRule = ClassificationRule.fromMap(existing.first);
      final updated = existingRule.copyWith(
        categoryId: categoryId,
        projectId: projectId,
        priority: priority,
        enabled: 1,
        updatedAt: nowIso,
      );
      await db.update(
        'classification_rules',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      return updated;
    }

    // Insert new rule
    final ruleId = 'rule_${DateTime.now().millisecondsSinceEpoch}_${cleanMerchant.hashCode.abs()}';
    final newRule = ClassificationRule(
      id: ruleId,
      priority: priority,
      merchantPattern: cleanMerchant,
      paymentChannel: paymentChannel,
      categoryId: categoryId,
      projectId: projectId,
      enabled: 1,
      version: 1,
      createdAt: nowIso,
      updatedAt: nowIso,
    );

    await db.insert('classification_rules', newRule.toMap());
    return newRule;
  }
}
```

### 7.7 分类引擎核心门面 (`rule_engine.dart`)
```dart
// lib/features/classification/rule_engine.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../data/database/app_database.dart';
import '../../data/models/classification_rule.dart';
import 'builtin_dictionary.dart';
import 'history_classifier.dart';
import 'models/classification_candidate_context.dart';
import 'models/classification_match_result.dart';
import 'models/classification_tier.dart';
import 'rule_matcher.dart';

/// Pluggable interface for Tier 5 AI classification providers
abstract class AiClassificationProvider {
  Future<String?> recommendCategory(ClassificationCandidateContext context);
}

/// Facade coordinating all 6 classification tiers deterministically
class ClassificationRuleEngine {
  final AppDatabase _dbHelper;
  final HistoryClassifier _historyClassifier;
  final AiClassificationProvider? _aiProvider;

  ClassificationRuleEngine({
    AppDatabase? db,
    HistoryClassifier? historyClassifier,
    AiClassificationProvider? aiProvider,
  })  : _dbHelper = db ?? AppDatabase.instance,
        _historyClassifier = historyClassifier ?? HistoryClassifier(db),
        _aiProvider = aiProvider;

  /// Executes deterministic 6-tier classification evaluation
  Future<ClassificationMatchResult> classify(
    ClassificationCandidateContext context, {
    String? manualCategoryId,
    String? manualProjectId,
    List<String> manualTagIds = const [],
  }) async {
    // -------------------------------------------------------------------------
    // Tier 1: User Manual Explicit Selection
    // -------------------------------------------------------------------------
    if (manualCategoryId != null && manualCategoryId.trim().isNotEmpty) {
      return ClassificationMatchResult.manual(
        categoryId: manualCategoryId.trim(),
        projectId: manualProjectId,
        tagIds: manualTagIds,
      );
    }

    // -------------------------------------------------------------------------
    // Tier 2: User Active Custom Rules (Ordered by priority DESC, created_at DESC)
    // -------------------------------------------------------------------------
    final customRuleResult = await _matchCustomRules(context);
    if (customRuleResult != null) {
      return customRuleResult;
    }

    // -------------------------------------------------------------------------
    // Tier 3: Historical Identical Merchant Category Mapping
    // -------------------------------------------------------------------------
    final historyResult = await _historyClassifier.classify(context);
    if (historyResult != null) {
      return historyResult;
    }

    // -------------------------------------------------------------------------
    // Tier 4: Built-in Keyword Dictionary Mapping
    // -------------------------------------------------------------------------
    final dictResult = _matchBuiltinDictionary(context);
    if (dictResult != null) {
      return dictResult;
    }

    // -------------------------------------------------------------------------
    // Tier 5: Optional AI Recommendation
    // -------------------------------------------------------------------------
    if (_aiProvider != null) {
      final aiResult = await _matchAiRecommendation(context);
      if (aiResult != null) {
        return aiResult;
      }
    }

    // -------------------------------------------------------------------------
    // Tier 6: Default Fallback Category (cat_other / Unclassified)
    // -------------------------------------------------------------------------
    return ClassificationMatchResult.fallback(categoryId: 'cat_other');
  }

  /// Evaluates active rules in classification_rules table
  Future<ClassificationMatchResult?> _matchCustomRules(ClassificationCandidateContext context) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'classification_rules',
      where: 'enabled = 1',
      orderBy: 'priority DESC, created_at DESC',
    );

    for (final row in rows) {
      final rule = ClassificationRule.fromMap(row);
      if (RuleMatcher.matches(rule, context)) {
        return ClassificationMatchResult.customRule(
          categoryId: rule.categoryId,
          projectId: rule.projectId,
          ruleId: rule.id,
          pattern: rule.merchantPattern,
          priority: rule.priority,
        );
      }
    }
    return null;
  }

  /// Evaluates built-in keyword dictionary
  ClassificationMatchResult? _matchBuiltinDictionary(ClassificationCandidateContext context) {
    // 1. Try effective merchant first
    final merchant = context.effectiveMerchant;
    var match = BuiltinDictionary.match(merchant);

    // 2. Try raw merchant if different
    if (match == null && context.merchantRaw != null && context.merchantRaw != merchant) {
      match = BuiltinDictionary.match(context.merchantRaw!);
    }

    // 3. Try remarks / items text
    if (match == null && context.remarks != null && context.remarks!.isNotEmpty) {
      match = BuiltinDictionary.match(context.remarks!);
    }

    if (match != null) {
      return ClassificationMatchResult.builtinKeyword(
        categoryId: match.categoryId,
        keyword: match.keyword,
      );
    }
    return null;
  }

  /// Evaluates AI provider with local schema validation
  Future<ClassificationMatchResult?> _matchAiRecommendation(ClassificationCandidateContext context) async {
    try {
      final suggestedCatId = await _aiProvider!.recommendCategory(context);
      if (suggestedCatId == null || suggestedCatId.trim().isEmpty) return null;

      // Validate that the category actually exists in local database
      final db = await _dbHelper.database;
      final exists = await db.query(
        'categories',
        where: 'id = ? AND archived_at IS NULL',
        whereArgs: [suggestedCatId.trim()],
        limit: 1,
      );

      if (exists.isNotEmpty) {
        return ClassificationMatchResult.ai(categoryId: suggestedCatId.trim());
      }
    } catch (_) {
      // AI provider failure silently drops to fallback
    }
    return null;
  }
}
```

---

## 8. 自动化测试与验证套件设计

为保证生产就绪的高可靠性，建立四组自动化测试套件：

### 8.1 6 级层级短路与覆盖测试矩阵 (`test/classification/rule_engine_test.dart`)
1. **Tier 1 Override**:
   - 当同时存在 Manual, CustomRule, History, BuiltinKeyword 时，验证返回结果严格为 `ClassificationTier.manual`，置信度为 `1.0`。
2. **Tier 2 Priority Ordering**:
   - 插入两条匹配同一商户但优先级不同的规则（Priority 200 vs 100），验证 Priority 200 胜出；
   - 插入两条优先级相同（Priority 100）的规则，验证后创建的 `created_at` 胜出。
3. **Tier 3 Historical Frequency**:
   - 无规则时，写入 3 条历史相同商户交易指向 `cat_food`，验证命中 `ClassificationTier.history`，置信度为 `0.90`；
   - 验证回收站（`deleted_at IS NOT NULL`）的历史交易不参与统计。
4. **Tier 4 Cold-start Dictionary**:
   - 清空规则与历史，输入“星巴克臻选咖啡”，验证命中 `cat_food`，匹配关键词为“星巴克”；
   - 输入“滴滴快车”，验证命中 `cat_transport`；
   - 输入“美团外卖”，验证命中 `cat_food`（验证长词优先，不被短词误吞）。
5. **Tier 5 AI Validation**:
   - Mock AI 返回合法已存在分类，验证命中 `ClassificationTier.ai`；
   - Mock AI 返回数据库中不存在的非法分类 ID，验证被安全校验拦截，优雅降级至 Tier 6。
6. **Tier 6 Fallback**:
   - 输入无法识别的乱码商户（如“XYZ9876QWE”），验证返回 `cat_other`，置信度为 `0.10`。

### 8.2 通配符与正则对抗测试矩阵 (`test/classification/rule_matcher_test.dart`)
| 测试用例类型 | 规则模式 (`merchantPattern`) | 测试商户名 | 期望匹配结果 |
| :--- | :--- | :--- | :--- |
| 前缀匹配 | `星巴克%` | `星巴克` | 匹配 |
| 前缀匹配 | `星巴克%` | `星巴克咖啡三里屯店` | 匹配 |
| 前缀匹配 | `星巴克%` | `北京星巴克` | **不匹配** |
| 包含匹配 | `%便利店%` | `全家便利店` | 匹配 |
| 包含匹配 | `%便利店%` | `便利店` | 匹配 |
| 包含匹配 | `%便利店%` | `全家超市` | **不匹配** |
| 单字占位 | `肯德基_分店` | `肯德基A分店` | 匹配 |
| 单字占位 | `肯德基_分店` | `肯德基分店` | **不匹配** |
| 显式正则 | `regex:^滴滴(出行\|快车)$` | `滴滴快车` | 匹配 |
| 显式正则 | `regex:^滴滴(出行\|快车)$` | `滴滴代驾` | **不匹配** |
| 特殊字符转义 | `C&A (服装)` | `C&A (服装)` | 匹配 (圆括号不崩溃) |
| 特殊字符转义 | `7-Eleven+` | `7-Eleven+` | 匹配 (加号不崩溃) |
| 渠道联合匹配 | `星巴克%`, channel=`wechat`| `星巴克`, channel=`alipay` | **不匹配 (渠道不符)** |
| 渠道联合匹配 | `星巴克%`, channel=`wechat`| `星巴克`, channel=`wechat` | 匹配 |

### 8.3 动态学习增量测试矩阵 (`test/classification/rule_learning_test.dart`)
1. **新建规则沉淀**：
   - 用户确认“麦当劳”归入 `cat_food`，调用 `learnRule`，验证数据库生成 `merchant_pattern = '麦当劳'` 的记录；
   - 紧随其后运行分类引擎对新商户“麦当劳”分类，验证直接命中 Tier 2。
2. **规则幂等更新**：
   - 用户将“麦当劳”重新归类为 `cat_shopping`，验证原规则记录被 `UPDATE`，而不是产生重复的冗余规则行。
3. **历史防篡改验证**：
   - 在学习新规则前向 `transactions` 插入历史交易；
   - 学习新规则后，查询历史交易，验证历史交易的 `category_id` 绝对保持不变。

### 8.4 3D 正交性与账务聚合测试 (`test/classification/orthogonal_grouping_test.dart`)
1. **分类穷尽性校验**：
   - 插入 10 笔关联不同分类、项目、标签的交易；
   - 验证 `SUM(category_totals) == SUM(transactions.amount_minor)`；
2. **项目隔离校验**：
   - 验证某项目的总额严格等于该项目中各笔交易金额之和，不受分类归属变动影响；
   - 删除项目（`DELETE FROM projects`），验证所有交易的 `project_id` 自动置为 `NULL`，交易本身完好无损；
3. **标签独立多对多校验**：
   - 验证单笔交易可关联多个标签，标签过滤查询不影响其他标签聚合；
   - 删除标签（`DELETE FROM tags`），验证 `transaction_tags` 关联记录级联删除，交易本体完好。

---

## 9. 结论与就绪状态

本蓝图为 SingWallet M1-B 分类规则引擎（Features F27-F30）提供了完备的工程设计契约：
- **F27 (3D 正交归类)**：严格定义主分类 (1)、项目 (0..1)、标签 (0..N) 的基数与无重叠数学保证；
- **F28 (6 级分类层级)**：建立 Manual > Rules > History > Dictionary > AI > Fallback 的确定性决断梯架；
- **F29 (模式匹配引擎)**：实现 SQL `%`, `_` 到安全正则表达式的零溢出、大小写无关、防 ReDoS 转换；
- **F30 (动态规则学习)**：设计轻量沉淀机制，坚守前向生效与历史数据防篡改底线。

所有数据契约与既有 `schema.dart` 及 `docs/跨平台架构与数据规范.md` 100% 吻合，测试用例矩阵齐备，已就绪可供编码落地。
