/**
 * SingWallet 领域元数据与分类配置中心 (SSOT Domain Configuration)
 * 集中管理系统 8 大核心分类、支付渠道、大模型服务商及通用校验匹配规则。
 */

(function (window) {
  'use strict';

  // 8 大核心一级分类及其详细元数据定义
  const CORE_CATEGORIES = [
    {
      id: 'catering',
      name: '餐饮美食',
      type: 'expense',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '餐饮、美食、外卖、饮品',
      subCategories: ['餐饮美食', '餐饮', '快餐简餐', '快餐', '咖啡饮品', '咖啡', '奶茶', '外卖', '小吃', '火锅'],
      keywords: [
        '餐饮', '美食', '饭', '餐', '吃', '外卖', '美团', '饿了么', '咖啡', '奶茶',
        '麦当劳', '肯德基', '瑞幸', '星巴克', '喜茶', '奈雪', '小吃', '火锅', '米线',
        '面馆', '汉堡', '烧烤', '酒楼', '食堂', '早餐', '午餐', '晚餐'
      ]
    },
    {
      id: 'transport',
      name: '交通出行',
      type: 'expense',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '公交、地铁、打车、高铁、飞机、加油、停车',
      subCategories: ['交通出行', '交通', '打车出行', '打车', '地铁公交', '加油停车'],
      keywords: [
        '12306', '铁路', '高铁', '火车', '机票', '航班', '客运', '打车', '滴滴', '曹操',
        't3', '地铁', '公交', '出行', '加油', '中石化', '中石油', '停车', 'etc',
        '过路费', '高速', '高德', '车费', '租车', '飞猪'
      ]
    },
    {
      id: 'shopping',
      name: '日常购物',
      type: 'expense',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '超市、便利店、网购、商场、服饰数码',
      subCategories: ['日常购物', '日常超市', '超市', '便利店', '生鲜百货', '网购', '服饰数码'],
      keywords: [
        '购物', '超市', '商超', '便利店', '沃尔玛', '家乐福', '大润发', '华润', '永辉',
        '世纪华购', '淘宝', '天猫', '京东', '拼多多', '唯品会', '苏宁', '百货', '生鲜',
        '水果', '菜场', '衣服', '服饰', '数码', '专卖店', '买'
      ]
    },
    {
      id: 'entertainment',
      name: '休闲娱乐',
      type: 'expense',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '游戏、电影、演出、会员、旅游度假',
      subCategories: ['休闲娱乐', '娱乐', '游戏充值', '视频会员', '电影演出'],
      keywords: [
        '娱乐', '游戏', '手游', '网游', '点券', '皮肤', '抽卡', '王者', '吃鸡', '原神',
        '崩铁', '网易', '腾讯', '米哈游', 'steam', 'playstation', 'xbox', '任天堂',
        '电影', '影城', '影院', '剧场', '演出', '大麦', 'ktv', '酒吧', '会员',
        '爱奇艺', '优酷', '哔哩哔哩', 'b站', '网易云', 'qq音乐', '门票', '景区',
        '网吧', '网咖'
      ]
    },
    {
      id: 'living',
      name: '生活缴费',
      type: 'expense',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '水电煤气、话费宽带、物业房租',
      subCategories: ['生活缴费', '缴费', '水电气费', '话费宽带', '房租物业'],
      keywords: [
        '缴费', '生活', '水费', '电费', '国家电网', '燃气', '天然气', '暖气', '话费',
        '宽带', '移动', '联通', '电信', '物业', '房租', '充值'
      ]
    },
    {
      id: 'medical',
      name: '医疗健康',
      type: 'expense',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '药品、医院挂号、门诊、体检',
      subCategories: ['医疗健康', '医疗', '药品门诊', '挂号体检'],
      keywords: [
        '医疗', '健康', '医院', '门诊', '诊所', '挂号', '药品', '大药房', '药店',
        '体检', '牙科', '口腔', '同仁堂', '益丰', '老百姓'
      ]
    },
    {
      id: 'other',
      name: '其他支出',
      type: 'expense',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '杂项、无法归类的其他支出',
      subCategories: ['其他支出', '其他'],
      keywords: []
    },
    {
      id: 'income',
      name: '工资收入',
      type: 'income',
      get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
      desc: '薪资、奖金、兼职、利息理财',
      subCategories: ['工资收入', '收入'],
      keywords: ['工资', '薪资', '兼职', '劳务', '代发', '奖金', '年终奖', '分红', '理财收益', '利息']
    }
  ];

  // 默认初始 8 大核心分类快照与基准
  const DEFAULT_INITIAL_CATEGORIES = [
    '餐饮美食', '交通出行', '日常购物', '休闲娱乐',
    '生活缴费', '医疗健康', '其他支出', '工资收入'
  ];
  const DEFAULT_CORE_CATEGORIES_SNAPSHOT = CORE_CATEGORIES.slice();

  // 核心一级分类名称列表
  const CORE_PARENT_CATEGORIES = CORE_CATEGORIES.map(c => c.name);

  // 子分类到一级分类映射表
  const subToParentCategoryMap = {};
  CORE_CATEGORIES.forEach(cat => {
    cat.subCategories.forEach(sub => {
      subToParentCategoryMap[sub] = cat.name;
    });
  });

  // 初始默认图标映射 (运行时通过 IconRegistry.getCategoryIcon 动态获取或代理)
  const defaultCategoryIconMap = new Proxy({}, {
    get(target, prop) {
      if (typeof prop === 'string') {
        if (window.IconRegistry && typeof window.IconRegistry.getCategoryIcon === 'function') {
          return window.IconRegistry.getCategoryIcon(prop);
        }
      }
      return target[prop] || '';
    },
    has(target, prop) {
      return true;
    },
    ownKeys(target) {
      return CORE_PARENT_CATEGORIES;
    },
    getOwnPropertyDescriptor(target, prop) {
      return {
        value: this.get(target, prop),
        enumerable: true,
        configurable: true
      };
    }
  });

  // 支付渠道列表与映射
  const PAYMENT_CHANNELS = [
    {
      id: 'wechat',
      name: '微信',
      aliases: ['微信', '微信支付', 'wx'],
      defaultAccounts: ['钱包', '零钱通', '招商银行(8848)']
    },
    {
      id: 'alipay',
      name: '支付宝',
      aliases: ['支付宝', 'alipay'],
      defaultAccounts: ['余额', '余额宝', '建设银行(1234)']
    },
    {
      id: 'unionpay',
      name: '云闪付',
      aliases: ['云闪付', '银联', 'unionpay'],
      defaultAccounts: ['工商银行(5678)']
    }
  ];

  // 大模型 (VLM) 协议支持与元数据
  const VLM_PROVIDERS = [
    {
      id: 'openai_chat',
      name: 'OpenAI Chat Completions',
      defaultEndpoint: '',
      defaultModel: ''
    },
    {
      id: 'anthropic_messages',
      name: 'Anthropic Messages',
      defaultEndpoint: '',
      defaultModel: ''
    },
    {
      id: 'openai_responses',
      name: 'OpenAI Responses API',
      defaultEndpoint: '',
      defaultModel: ''
    },
    {
      id: 'gemini_native',
      name: 'Gemini Native generateContent',
      defaultEndpoint: '',
      defaultModel: ''
    }
  ];

  // 默认账本与项目列表
  const DEFAULT_BOOKS = [
    { id: 'daily', name: '日常账本' },
    { id: 'travel', name: '旅行账本' },
    { id: 'business', name: '商务账本' }
  ];

  const DEFAULT_PROJECTS = [
    { id: 'daily', name: '日常' },
    { id: 'travel', name: '旅行' },
    { id: 'renovation', name: '装修' }
  ];

  // 账单大模型结构化输出 JSON Schema 定义 (OpenAI / Qwen / OpenAI Compatible 规范)
  const BILL_STRUCTURED_SCHEMA = {
    type: "json_schema",
    json_schema: {
      name: "bill_extraction",
      strict: true,
      schema: {
        type: "object",
        properties: {
          merchant: { type: "string" },
          amount: { type: "number" },
          category: {
            type: "string",
            enum: ["餐饮美食", "交通出行", "日常购物", "休闲娱乐", "生活缴费", "医疗健康", "其他支出", "工资收入"]
          },
          time: { type: "string" },
          orderId: { type: "string" },
          channel: { type: "string" }
        },
        required: ["merchant", "amount", "category", "time", "channel"],
        additionalProperties: false
      }
    }
  };

  /**
   * 应用分类列表并同步元数据体系与持久化
   */
  function applyCategoriesList(namesList, saveToStorage = true) {
    if (!Array.isArray(namesList) || namesList.length === 0) return;
    
    // 原地更新 CORE_PARENT_CATEGORIES 保持外部引用有效
    CORE_PARENT_CATEGORIES.splice(0, CORE_PARENT_CATEGORIES.length, ...namesList);

    // 同步更新 CORE_CATEGORIES 对象列表
    const existingMap = new Map();
    DEFAULT_CORE_CATEGORIES_SNAPSHOT.forEach(c => existingMap.set(c.name, c));
    CORE_CATEGORIES.forEach(c => existingMap.set(c.name, c));

    CORE_CATEGORIES.splice(0, CORE_CATEGORIES.length);
    namesList.forEach((name, idx) => {
      if (existingMap.has(name)) {
        CORE_CATEGORIES.push(existingMap.get(name));
      } else {
        CORE_CATEGORIES.push({
          id: 'custom_' + idx,
          name: name,
          type: name.includes('收入') ? 'income' : 'expense',
          get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
          desc: name,
          subCategories: [name],
          keywords: [name]
        });
      }
    });

    // 实时同步大模型结构化输出 Schema 枚举值
    if (BILL_STRUCTURED_SCHEMA && BILL_STRUCTURED_SCHEMA.json_schema && BILL_STRUCTURED_SCHEMA.json_schema.schema && BILL_STRUCTURED_SCHEMA.json_schema.schema.properties && BILL_STRUCTURED_SCHEMA.json_schema.schema.properties.category) {
      BILL_STRUCTURED_SCHEMA.json_schema.schema.properties.category.enum = [...CORE_PARENT_CATEGORIES];
    }

    // 清理并重新构建 subToParentCategoryMap，防止已删除分类残留脏映射
    Object.keys(subToParentCategoryMap).forEach(key => delete subToParentCategoryMap[key]);
    CORE_CATEGORIES.forEach(cat => {
      if (Array.isArray(cat.subCategories)) {
        cat.subCategories.forEach(sub => {
          subToParentCategoryMap[sub] = cat.name;
        });
      }
      subToParentCategoryMap[cat.name] = cat.name;
    });

    if (saveToStorage) {
      try {
        localStorage.setItem('singwallet_custom_categories', JSON.stringify(CORE_PARENT_CATEGORIES));
      } catch (e) {}
    }
  }

  /**
   * 从 localStorage 初始化持久化分类列表
   */
  function loadPersistedCategories() {
    try {
      const saved = localStorage.getItem('singwallet_custom_categories');
      if (saved) {
        const parsed = JSON.parse(saved);
        if (Array.isArray(parsed) && parsed.length > 0) {
          applyCategoriesList(parsed, false);
          return;
        }
      }
    } catch (e) {}
  }

  /**
   * 增加自定义分类
   */
  function addCategory(name) {
    if (!name || typeof name !== 'string') return false;
    const clean = name.trim();
    if (!clean || CORE_PARENT_CATEGORIES.includes(clean)) return false;
    const nextList = [...CORE_PARENT_CATEGORIES, clean];
    applyCategoriesList(nextList, true);
    if (window.IconRegistry && typeof window.IconRegistry.getCategoryIcon === 'function') {
      window.IconRegistry.categoryEmojis[clean] = window.IconRegistry.getCategoryIcon(clean);
    }
    return true;
  }

  /**
   * 删除分类 (至少保留 1 个分类)
   */
  function removeCategory(name) {
    if (!name || typeof name !== 'string') return false;
    const clean = name.trim();
    if (CORE_PARENT_CATEGORIES.length <= 1) return false;
    const idx = CORE_PARENT_CATEGORIES.indexOf(clean);
    if (idx === -1) return false;
    const nextList = CORE_PARENT_CATEGORIES.filter(c => c !== clean);
    applyCategoriesList(nextList, true);
    return true;
  }

  /**
   * 恢复为系统默认 8 大分类
   */
  function resetCategories() {
    applyCategoriesList(DEFAULT_INITIAL_CATEGORIES, true);
    return true;
  }

  // 初始化加载持久化配置
  loadPersistedCategories();

  /**
   * 智能归并一级分类算法 (100% 保持历史归并与语义关键词匹配逻辑)
   */
  function resolveParentCategory(cat, merchantName = '') {
    const fallbackCat = CORE_PARENT_CATEGORIES.includes('其他支出') ? '其他支出' : (CORE_PARENT_CATEGORIES[0] || '其他支出');
    if (!cat && !merchantName) return fallbackCat;
    const cleanCat = (cat || '').trim();
    if (CORE_PARENT_CATEGORIES.includes(cleanCat)) {
      return cleanCat;
    }
    if (subToParentCategoryMap[cleanCat] && CORE_PARENT_CATEGORIES.includes(subToParentCategoryMap[cleanCat])) {
      return subToParentCategoryMap[cleanCat];
    }

    // Keyword semantic mapping against category string and merchant name (受动态分类控制)
    const textToTest = `${cleanCat} ${merchantName || ''}`.toLowerCase();
    if (/12306|铁路|高铁|火车|机票|航班|客运|打车|滴滴|曹操|t3|地铁|公交|出行|加油|中石化|中石油|停车|etc|过路费|高速|高德|车费|租车|飞猪/.test(textToTest)) {
      if (CORE_PARENT_CATEGORIES.includes('交通出行')) return '交通出行';
    }
    if (/餐饮|美食|饭|餐|吃|外卖|美团|饿了么|咖啡|奶茶|麦当劳|肯德基|瑞幸|星巴克|喜茶|奈雪|小吃|火锅|米线|面馆|汉堡|烧烤|酒楼|食堂|早餐|午餐|晚餐/.test(textToTest)) {
      if (CORE_PARENT_CATEGORIES.includes('餐饮美食')) return '餐饮美食';
    }
    if (/购物|超市|商超|便利店|沃尔玛|家乐福|大润发|华润|永辉|世纪华购|淘宝|天猫|京东|拼多多|唯品会|苏宁|百货|生鲜|水果|菜场|衣服|服饰|数码|专卖店|买/.test(textToTest)) {
      if (CORE_PARENT_CATEGORIES.includes('日常购物')) return '日常购物';
    }
    if (/娱乐|游戏|手游|网游|点券|皮肤|抽卡|王者|吃鸡|原神|崩铁|网易|腾讯|米哈游|steam|playstation|xbox|任天堂|电影|影城|影院|剧场|演出|大麦|ktv|酒吧|会员|爱奇艺|优酷|哔哩哔哩|b站|网易云|qq音乐|门票|景区|网吧|网咖/.test(textToTest)) {
      if (CORE_PARENT_CATEGORIES.includes('休闲娱乐')) return '休闲娱乐';
    }
    if (/缴费|生活|水费|电费|国家电网|燃气|天然气|暖气|话费|宽带|移动|联通|电信|物业|房租|充值/.test(textToTest)) {
      if (CORE_PARENT_CATEGORIES.includes('生活缴费')) return '生活缴费';
    }
    if (/医疗|健康|医院|门诊|诊所|挂号|药品|大药房|药店|体检|牙科|口腔|同仁堂|益丰|老百姓/.test(textToTest)) {
      if (CORE_PARENT_CATEGORIES.includes('医疗健康')) return '医疗健康';
    }
    if (/工资|薪资|兼职|劳务|代发|奖金|年终奖|分红|理财收益|利息/.test(textToTest)) {
      if (CORE_PARENT_CATEGORIES.includes('工资收入')) return '工资收入';
    }

    return fallbackCat;
  }

  /**
   * 支付方式结构化解析函数 (100% 保持历史解析逻辑)
   */
  function parsePaymentMethodString(accStr) {
    const clean = (accStr || '').trim();
    if (clean.includes('·')) {
      const parts = clean.split('·').map(s => s.trim());
      const channel = parts[0];
      const sub = parts[1];
      const bankMatch = sub.match(/^(.*?)\((\d{4})\)$/);
      if (bankMatch) {
        return {
          channel: channel,
          channel_key: channel === '微信' ? 'wechat' : (channel === '支付宝' ? 'alipay' : 'unionpay'),
          sub_type: '银行卡',
          bank_name: bankMatch[1],
          card_last_4: bankMatch[2],
          display_name: clean
        };
      } else {
        return {
          channel: channel,
          channel_key: channel === '微信' ? 'wechat' : (channel === '支付宝' ? 'alipay' : 'unionpay'),
          sub_type: sub,
          bank_name: null,
          card_last_4: null,
          display_name: clean
        };
      }
    }
    if (clean.includes('微信')) {
      return { channel: '微信', channel_key: 'wechat', sub_type: '钱包', bank_name: null, card_last_4: null, display_name: '微信 · 钱包' };
    }
    if (clean.includes('支付宝')) {
      return { channel: '支付宝', channel_key: 'alipay', sub_type: '余额', bank_name: null, card_last_4: null, display_name: '支付宝 · 余额' };
    }
    if (clean.includes('云闪付')) {
      return { channel: '云闪付', channel_key: 'unionpay', sub_type: '银行卡', bank_name: '工商银行', card_last_4: '5678', display_name: '云闪付 · 工商银行(5678)' };
    }
    return { channel: '微信', channel_key: 'wechat', sub_type: '钱包', bank_name: null, card_last_4: null, display_name: '微信 · 钱包' };
  }

  /**
   * 下拉框选项与目标值匹配器 (保持原第 5860-5907 行完全一致的匹配逻辑，支持 2 参数与 3 参数调用)
   */
  function isOptionMatch(idOrOptVal, optValOrTargetVal, targetVal) {
    let id = '';
    let optVal = '';
    let target = '';

    if (arguments.length >= 3) {
      id = idOrOptVal;
      optVal = optValOrTargetVal;
      target = targetVal;
    } else {
      id = '';
      optVal = idOrOptVal;
      target = optValOrTargetVal;
    }

    if (optVal === String(target)) return true;

    if (!id || id === 'select-channel') {
      if ((target === '微信' || target === '微信支付' || target === 'wx') && (optVal === '微信' || optVal === '微信支付')) return true;
      if ((target === '支付宝' || target === 'alipay') && optVal === '支付宝') return true;
      if ((target === '云闪付' || target === '银联') && optVal === '云闪付') return true;
      if ((target === '招行卡' || target === '招商银行卡') && (optVal === '微信' || optVal === '招商银行卡')) return true;
    }

    if (!id || id === 'select-account') {
      if ((target === '钱包' || target === '微信钱包' || target === '现金钱包') && optVal === '钱包') return true;
      if ((target === '余额' || target === '支付宝余额') && optVal === '余额') return true;
      if (target === '零钱通' && optVal === '零钱通') return true;
      if (target === '余额宝' && optVal === '余额宝') return true;
      if ((target === '招商银行(8848)' || target === '招商银行储蓄卡' || target === '招商银行储蓄卡(1234)') && (optVal === '招商银行(8848)' || optVal === '招商银行储蓄卡(1234)')) return true;
      if (target === '建设银行(1234)' && optVal === '建设银行(1234)') return true;
      if (target === '工商银行(5678)' && optVal === '工商银行(5678)') return true;
      if (String(target).includes('·')) {
        const sub = String(target).split('·')[1].trim();
        if (optVal === sub || optVal.includes(sub) || sub.includes(optVal)) return true;
      }
    }

    if (!id || id === 'manual-category') {
      if (optVal === String(target)) return true;
    }

    if (!id || id === 'manual-account') {
      if (optVal === String(target)) return true;
      if ((target === '微信支付' || target === '微信钱包' || target === '微信') && optVal === '微信 · 钱包') return true;
      if ((target === '招商银行卡' || target === '招行卡') && optVal === '微信 · 招商银行(8848)') return true;
      if ((target === '支付宝' || target === '支付宝余额') && optVal === '支付宝 · 余额') return true;
      if (target === '云闪付' && optVal === '云闪付 · 工商银行(5678)') return true;
    }

    if (!id || id === 'rule-match-type') {
      if ((target === '前缀匹配' && optVal === 'prefix') || (target === 'prefix' && optVal === '前缀匹配')) return true;
      if ((target === '通配符' || target === '模糊包含') && optVal === 'contains') return true;
      if ((target === '全词' || target === '全词匹配') && optVal === 'exact') return true;
      if ((target === '正则' || target === '安全正则表达式') && optVal === 'regex') return true;
    }

    if (!id || id === 'vlm-provider-select') {
      if (optVal === String(target)) return true;
      if (optVal === 'openai_chat') {
        if (['openai_chat', 'OpenAI Chat Completions', 'openai', 'qwen', 'custom'].includes(String(target))) return true;
      }
      if (optVal === 'anthropic_messages') {
        if (['anthropic_messages', 'Anthropic Messages', 'anthropic', 'claude'].includes(String(target))) return true;
      }
      if (optVal === 'openai_responses') {
        if (['openai_responses', 'OpenAI Responses API', 'responses'].includes(String(target))) return true;
      }
      if (optVal === 'gemini_native') {
        if (['gemini_native', 'Gemini Native generateContent', 'gemini'].includes(String(target))) return true;
      }
    }

    if (!id || id === 'acc-add-type') {
      if ((target === '银行储蓄卡' || target === '储蓄卡') && optVal === 'bank_card') return true;
      if ((target === '信用卡' || target === '银行信用卡') && optVal === 'credit_card') return true;
      if (target === '微信钱包' && optVal === 'wechat') return true;
      if (target === '支付宝余额' && optVal === 'alipay') return true;
      if ((target === '现金钱包' || target === '现金') && optVal === 'cash') return true;
      if ((target === '其他' || target === '其他账户') && optVal === 'other') return true;
    }

    return false;
  }

  /**
   * 获取指定服务商的默认 Endpoint
   */
  function getDefaultEndpointForProvider(provider) {
    if (provider === 'gemini_native' || provider === 'gemini') return 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';
    if (provider === 'anthropic_messages' || provider === 'anthropic') return 'https://api.anthropic.com/v1/messages';
    if (provider === 'openai_responses') return 'https://api.openai.com/v1/responses';
    return 'https://api.openai.com/v1/chat/completions';
  }

  /**
   * 获取指定服务商的默认模型 Model
   */
  function getDefaultModelForProvider(provider) {
    if (provider === 'gemini_native' || provider === 'gemini') return 'gemini-1.5-flash';
    if (provider === 'anthropic_messages' || provider === 'anthropic') return 'claude-3-5-sonnet-20241022';
    if (provider === 'openai_responses') return 'gpt-4o';
    return 'gpt-4o-mini';
  }

  /**
   * 规范化账单订单号 (忽略首尾空白及常见无单号占位符)
   * @param {string|any} rawOrderId 原始订单号字符串
   * @returns {string} 规范化后的订单号，空值统一返回 ''
   */
  function normalizeOrderId(rawOrderId) {
    if (rawOrderId === null || rawOrderId === undefined) return '';
    const clean = String(rawOrderId).trim();
    if (!clean) return '';
    if (clean === '无' || clean === '--' || clean === '-' || clean === 'null' || clean === 'undefined' || clean === 'none') {
      return '';
    }
    return clean;
  }

  /**
   * 判断单个订单号是否与已入账流水存在重复 (领域层纯函数)
   * @param {string} orderId 待检测的订单号
   * @param {Set|Array|Iterable} existingTransactions 已入账流水或订单号集合
   * @returns {boolean}
   */
  function isOrderIdDuplicate(orderId, existingTransactions) {
    const cleanOrder = normalizeOrderId(orderId);
    if (!cleanOrder) return false;
    if (!existingTransactions) return false;

    if (existingTransactions instanceof Set) {
      return existingTransactions.has(cleanOrder);
    }

    if (Array.isArray(existingTransactions) || typeof existingTransactions[Symbol.iterator] === 'function') {
      for (const item of existingTransactions) {
        if (!item) continue;
        let candidate = '';
        if (typeof item === 'string') {
          candidate = normalizeOrderId(item);
        } else if (typeof item === 'object') {
          candidate = normalizeOrderId(item.orderId || item.order_id || item.orderNo || (item.getAttribute && item.getAttribute('data-order')) || item.dataset?.order);
        }
        if (candidate && candidate === cleanOrder) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * 批量草稿去重分流器 (领域层纯函数，支持与已入账账单比对 + 同批次内自去重)
   * @param {Array} drafts 待入账的草稿数组
   * @param {Set|Array|Iterable} existingTransactions 已入账交易单号或对象集合
   * @returns {{ validList: Array, dupList: Array }} 分流结果
   */
  function partitionDraftsByDedup(drafts, existingTransactions = []) {
    const validList = [];
    const dupList = [];
    if (!Array.isArray(drafts) || drafts.length === 0) {
      return { validList, dupList };
    }

    // 预处理并构建已入账订单号 Set
    const committedSet = new Set();
    if (existingTransactions instanceof Set) {
      existingTransactions.forEach(val => {
        const c = normalizeOrderId(val);
        if (c) committedSet.add(c);
      });
    } else if (Array.isArray(existingTransactions) || (existingTransactions && typeof existingTransactions[Symbol.iterator] === 'function')) {
      for (const item of existingTransactions) {
        if (!item) continue;
        let c = '';
        if (typeof item === 'string') {
          c = normalizeOrderId(item);
        } else if (typeof item === 'object') {
          c = normalizeOrderId(item.orderId || item.order_id || item.orderNo || (item.getAttribute && item.getAttribute('data-order')) || item.dataset?.order);
        }
        if (c) committedSet.add(c);
      }
    }

    // 批次内自去重追踪集合 (Intra-batch deduplication)
    const seenBatchOrders = new Set();

    drafts.forEach(draft => {
      if (!draft) return;
      const rawOrder = draft.orderId || (draft.raw && draft.raw.orderId) || '';
      const cleanOrd = normalizeOrderId(rawOrder);

      // 若草稿无有效订单号，不视作重复，允许正常入账
      if (!cleanOrd) {
        validList.push(draft);
        return;
      }

      // a) 与已入账流水比对
      if (committedSet.has(cleanOrd)) {
        dupList.push(draft);
        return;
      }

      // b) 同批次内自去重：同批次中第一笔通过，后续相同单号均被拦截
      if (seenBatchOrders.has(cleanOrd)) {
        dupList.push(draft);
        return;
      }

      // 校验通过
      seenBatchOrders.add(cleanOrd);
      validList.push(draft);
    });

    return { validList, dupList };
  }

  /**
   * 分类占比图表调色板 (适配深色/深紫背景的高辨识度配色)
   */
  const CATEGORY_CHART_PALETTE = [
    '#f9661c', '#d438f3', '#2ef7f0', '#f472b6', '#a78bfa',
    '#fbaf3c', '#d42d9f', '#f979dd', '#15fa56', '#bcfa60'
  ];

  /**
   * 将数值格式化为最多保留 2 位小数且自动去除末尾多余 0 的紧凑字符串
   * 例如: 437.20 -> "437.2", 5000.00 -> "5000", 15.77 -> "15.77"
   * @param {number|string} amount 金额数值
   * @returns {string} 紧凑格式化字符串
   */
  function formatCompactAmount(amount) {
    const num = Number(amount);
    if (isNaN(num)) return '0';
    return Number(num.toFixed(2)).toString();
  }

  /**
   * 支出分类占比聚合与最大余额法百分比统计 (Domain Layer Pure Function)
   * @param {Array} transactions 交易对象数组
   * @param {Array<string>|null} activeCategories 当前激活的分类列表 (根据分类管理动态变化)
   * @returns {{ totalExpense: number, totalExpenseText: string, items: Array }}
   */
  function computeCategoryBreakdown(transactions = [], activeCategories = null) {
    const activeList = (Array.isArray(activeCategories) && activeCategories.length > 0)
      ? activeCategories
      : (Array.isArray(CORE_PARENT_CATEGORIES) ? CORE_PARENT_CATEGORIES : []);
    const activeSet = new Set(activeList);

    const totals = {};
    if (Array.isArray(transactions)) {
      transactions.forEach(tx => {
        if (!tx) return;
        // 排除收入与退款账单
        if (tx.isIncome === true || tx.isRefund === true || tx.type === 'income' || tx.type === 'refund') return;
        if (tx.category === '工资收入' || tx.parentCat === '工资收入' || tx.catName === '工资收入') return;

        const rawCat = tx.parentCat || tx.category || tx.catName || '';
        const resolvedCat = (typeof resolveParentCategory === 'function')
          ? resolveParentCategory(rawCat, tx.merchant || tx.name || '')
          : rawCat;

        // 仅统计存在于当前激活分类中的支出
        if (!resolvedCat || (activeSet.size > 0 && !activeSet.has(resolvedCat))) return;

        const amt = Math.abs(parseFloat(tx.amount) || 0);
        if (amt <= 0) return;

        totals[resolvedCat] = (totals[resolvedCat] || 0) + amt;
      });
    }

    const total = Object.values(totals).reduce((a, b) => a + b, 0);
    if (total <= 0) {
      return {
        totalExpense: 0,
        totalExpenseText: '0',
        items: []
      };
    }

    // 按金额降序排列
    const sortedCats = Object.keys(totals).sort((a, b) => totals[b] - totals[a]);

    // 最大余额法 (Largest Remainder Method) 计算整数百分比，保证百分比总和为 100%
    const rawItems = sortedCats.map((catName, idx) => {
      const catTotal = totals[catName];
      const ratio = catTotal / total;
      const exactPercent = ratio * 100;
      const floorPercent = Math.floor(exactPercent);
      const remainder = exactPercent - floorPercent;
      return {
        catName,
        catTotal,
        ratio,
        floorPercent,
        remainder,
        origIndex: idx
      };
    });

    const sumFloor = rawItems.reduce((acc, it) => acc + it.floorPercent, 0);
    const diff = 100 - sumFloor;

    const sortedByRemainder = [...rawItems].sort((a, b) => b.remainder - a.remainder);
    for (let i = 0; i < diff && i < sortedByRemainder.length; i++) {
      sortedByRemainder[i].floorPercent += 1;
    }

    rawItems.sort((a, b) => a.origIndex - b.origIndex);

    const items = rawItems.map((it, idx) => {
      const catTotal = it.catTotal;
      const intPercent = it.floorPercent;
      const amtText = formatCompactAmount(catTotal);
      return {
        category: it.catName,
        amount: Number(catTotal.toFixed(2)),
        amountText: amtText,
        percentage: intPercent,
        ratio: it.ratio,
        color: CATEGORY_CHART_PALETTE[idx % CATEGORY_CHART_PALETTE.length],
        label: `${it.catName}(${intPercent}%):${amtText}`
      };
    });

    return {
      totalExpense: Number(total.toFixed(2)),
      totalExpenseText: formatCompactAmount(total),
      items: items
    };
  }

  // 领域元数据配置对象 (SSOT)
  const SINGWALLET_DOMAIN_CONFIG = {
    categories: CORE_CATEGORIES,
    parentCategories: CORE_PARENT_CATEGORIES,
    subToParentMap: subToParentCategoryMap,
    defaultIcons: defaultCategoryIconMap,
    channels: PAYMENT_CHANNELS,
    providers: VLM_PROVIDERS,
    defaultBooks: DEFAULT_BOOKS,
    defaultProjects: DEFAULT_PROJECTS,
    schema: BILL_STRUCTURED_SCHEMA,
    normalizeOrderId: normalizeOrderId,
    isOrderIdDuplicate: isOrderIdDuplicate,
    partitionDraftsByDedup: partitionDraftsByDedup,
    CATEGORY_CHART_PALETTE: CATEGORY_CHART_PALETTE,
    formatCompactAmount: formatCompactAmount,
    computeCategoryBreakdown: computeCategoryBreakdown
  };

  // 领域注册管理中心 (DomainRegistry)
  const DomainRegistry = {
    getConfig: () => SINGWALLET_DOMAIN_CONFIG,
    getCategories: () => CORE_CATEGORIES,
    getParentCategories: () => CORE_PARENT_CATEGORIES,
    get activeCategories() { return CORE_PARENT_CATEGORIES; },
    getCategoryByName: (name) => {
      const parent = resolveParentCategory(name);
      return CORE_CATEGORIES.find(c => c.name === parent) || null;
    },
    resolveParentCategory: resolveParentCategory,
    addCategory: addCategory,
    removeCategory: removeCategory,
    resetCategories: resetCategories,
    getChannels: () => PAYMENT_CHANNELS,
    getProviders: () => VLM_PROVIDERS,
    getProviderConfig: (providerId) => VLM_PROVIDERS.find(p => p.id === providerId) || null,
    getDefaultEndpoint: getDefaultEndpointForProvider,
    getDefaultModel: getDefaultModelForProvider,
    parsePaymentMethod: parsePaymentMethodString,
    isOptionMatch: isOptionMatch,
    normalizeOrderId: normalizeOrderId,
    isOrderIdDuplicate: isOrderIdDuplicate,
    partitionDraftsByDedup: partitionDraftsByDedup,
    CATEGORY_CHART_PALETTE: CATEGORY_CHART_PALETTE,
    formatCompactAmount: formatCompactAmount,
    computeCategoryBreakdown: computeCategoryBreakdown
  };

  // 挂载至全局 window 对象 (SingWalletDomain 作为 SSOT 统一领域中心)
  window.SINGWALLET_DOMAIN_CONFIG = SINGWALLET_DOMAIN_CONFIG;
  window.DomainRegistry = DomainRegistry;
  window.SingWalletDomain = DomainRegistry;

  // 暴露 100% 向后兼容的全局常量与函数
  window.CORE_PARENT_CATEGORIES = CORE_PARENT_CATEGORIES;
  window.subToParentCategoryMap = subToParentCategoryMap;
  window.resolveParentCategory = resolveParentCategory;
  window.addCategory = addCategory;
  window.removeCategory = removeCategory;
  window.resetCategories = resetCategories;
  window.parsePaymentMethodString = parsePaymentMethodString;
  window.isOptionMatch = isOptionMatch;
  window.getDefaultEndpointForProvider = getDefaultEndpointForProvider;
  window.getDefaultModelForProvider = getDefaultModelForProvider;
  window.BILL_STRUCTURED_SCHEMA = BILL_STRUCTURED_SCHEMA;
  window.normalizeOrderId = normalizeOrderId;
  window.isOrderIdDuplicate = isOrderIdDuplicate;
  window.partitionDraftsByDedup = partitionDraftsByDedup;
  window.CATEGORY_CHART_PALETTE = CATEGORY_CHART_PALETTE;
  window.formatCompactAmount = formatCompactAmount;
  window.computeCategoryBreakdown = computeCategoryBreakdown;

})(typeof window !== 'undefined' ? window : this);
