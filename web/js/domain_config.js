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
      defaultAccounts: ['银行卡', '工商银行(5678)']
    }
  ];

  // 渠道默认账户映射 (SSOT)
  const CHANNEL_DEFAULT_ACCOUNT = {
    '微信': '钱包',
    '支付宝': '余额',
    '云闪付': '银行卡'
  };

  // 渠道专属内置账户定义与归一化
  const CHANNEL_EXCLUSIVE_ACCOUNTS = {
    '微信': ['钱包', '零钱', '零钱通'],
    '支付宝': ['余额', '余额宝', '花呗', '蚂蚁花呗']
  };

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
          channel: { type: "string" },
          account: { type: "string" }
        },
        required: ["merchant", "amount", "category", "time", "channel", "account"],
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
   * 重命名分类 (在原索引位置替换，保留自定义图标与关键词映射，同步更新 Schema 与持久化)
   */
  function renameCategory(oldName, newName) {
    if (!oldName || typeof oldName !== 'string' || !newName || typeof newName !== 'string') return false;
    const cleanOld = oldName.trim();
    const cleanNew = newName.trim();
    if (!cleanOld || !cleanNew) return false;
    const idx = CORE_PARENT_CATEGORIES.indexOf(cleanOld);
    if (idx === -1) return false;
    if (cleanNew === cleanOld) return true;
    if (CORE_PARENT_CATEGORIES.includes(cleanNew)) return false;

    const origCat = CORE_CATEGORIES.find(c => c.name === cleanOld);
    const preservedIcon = (window.IconRegistry && window.IconRegistry.categoryEmojis && window.IconRegistry.categoryEmojis[cleanOld])
      ? window.IconRegistry.categoryEmojis[cleanOld]
      : ((window.IconRegistry && typeof window.IconRegistry.getCategoryIcon === 'function') ? window.IconRegistry.getCategoryIcon(cleanOld) : '');

    if (origCat) {
      const subCats = Array.isArray(origCat.subCategories)
        ? origCat.subCategories.map(s => s === cleanOld ? cleanNew : s)
        : [cleanNew];
      if (!subCats.includes(cleanNew)) subCats.unshift(cleanNew);
      const kwList = Array.isArray(origCat.keywords) ? [...origCat.keywords] : [];
      if (!kwList.includes(cleanNew)) kwList.push(cleanNew);
      CORE_CATEGORIES[idx] = {
        id: origCat.id || ('custom_' + idx),
        name: cleanNew,
        type: cleanNew.includes('收入') ? 'income' : (origCat.type || 'expense'),
        get defaultEmoji() { return window.IconRegistry ? window.IconRegistry.getCategoryIcon(this.name) : ''; },
        desc: origCat.desc || cleanNew,
        subCategories: subCats,
        keywords: kwList
      };
    }

    const nextList = [...CORE_PARENT_CATEGORIES];
    nextList[idx] = cleanNew;
    applyCategoriesList(nextList, true);

    if (preservedIcon && window.IconRegistry) {
      if (window.IconRegistry.categoryEmojis) {
        window.IconRegistry.categoryEmojis[cleanNew] = preservedIcon;
      }
      if (typeof window.IconRegistry.setCategoryIcon === 'function') {
        window.IconRegistry.setCategoryIcon(cleanNew, preservedIcon);
      }
    }
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

    for (let i = 0; i < CORE_CATEGORIES.length; i++) {
      const cObj = CORE_CATEGORIES[i];
      if (cObj && cObj.name && CORE_PARENT_CATEGORIES.includes(cObj.name) && Array.isArray(cObj.keywords) && cObj.keywords.length > 0) {
        for (let k = 0; k < cObj.keywords.length; k++) {
          const kw = String(cObj.keywords[k] || '').toLowerCase();
          if (kw && textToTest.includes(kw)) {
            return cObj.name;
          }
        }
      }
    }

    return fallbackCat;
  }

  /**
   * 规范化支付渠道名称 (SSOT)
   * @param {string} rawChannel 原始渠道名
   * @returns {string} '微信' | '支付宝' | '云闪付'
   */
  function normalizeChannelName(rawChannel) {
    const str = String(rawChannel || '').trim().toLowerCase();
    if (/微信|wx|wechat/.test(str)) return '微信';
    if (/支付宝|alipay/.test(str)) return '支付宝';
    if (/云闪付|unionpay/.test(str)) return '云闪付';
    if (str.includes('银联') && !/(?:银行|储蓄卡|信用卡|借记卡|尾号|\d)/.test(str)) return '云闪付';
    return '微信';
  }

  /**
   * 规范化银行卡及内置账户名称
   * @param {string} rawAccount 原始账户字符串
   * @param {string} [channel] 渠道名称
   * @returns {string} 规范化后的账户字符串
   */
  function normalizeBankCardAccount(rawAccount, channel) {
    let str = String(rawAccount || '').trim();
    if (!str) return '';

    // 1. 支持剥离 · 前面的渠道前缀
    if (str.includes('·')) {
      str = str.split('·')[1].trim();
    }

    // 2. 内置账户处理
    if (str === '零钱' || str === '微信钱包' || str === '现金钱包') return '钱包';
    if (str === '蚂蚁花呗') return '花呗';
    if (str === '支付宝余额') return '余额';
    if (['钱包', '零钱通', '余额', '余额宝', '花呗'].includes(str)) {
      return str;
    }

    // 3. 提取卡号与括号类型
    // 支持方括号 [5678], [尾号5678], 【5678】；圆括号 (5678), （5678）, (尾号5678), （尾号5678）；或无括号 尾号5678 等
    let isSquare = false;
    let cardDigits = '';
    let bankPart = str;

    const squareMatch = str.match(/[\[【](?:尾号)?(\d{3,8})[\]】]/);
    const roundMatch = str.match(/[（(](?:尾号)?(\d{3,8})[）)]/);
    const tailMatch = str.match(/(?:尾号|卡号|\s)(\d{3,8})/);
    const rawDigitsMatch = str.match(/(\d{4})/);

    if (squareMatch) {
      isSquare = true;
      cardDigits = squareMatch[1];
      bankPart = str.replace(/[\[【](?:尾号)?\d{3,8}[\]】]/, '');
    } else if (roundMatch) {
      isSquare = false;
      cardDigits = roundMatch[1];
      bankPart = str.replace(/[（(](?:尾号)?\d{3,8}[）)]/, '');
    } else if (tailMatch) {
      isSquare = false;
      cardDigits = tailMatch[1];
      bankPart = str.replace(/(?:尾号|卡号|\s)\d{3,8}/, '');
    } else if (rawDigitsMatch) {
      isSquare = false;
      cardDigits = rawDigitsMatch[1];
      bankPart = str.replace(/\d{4}/, '');
    }

    // 4. 清洗银行主体名称
    bankPart = bankPart.trim();
    // 中国邮政储蓄银行 -> 邮储银行
    bankPart = bankPart.replace(/^中国邮政储蓄银行/, '邮储银行').replace(/^邮政储蓄银行/, '邮储银行');
    // 去除冗余“中国”前缀（严格保留“中国银行”不变）
    bankPart = bankPart.replace(/^中国(工商银行|建设银行|农业银行|民生银行|光大银行|交通银行|招商银行|广发银行|平安银行|兴业银行|浦发银行|中信银行|华夏银行|北京银行|上海银行)/, '$1');
    // 去除中间冗余卡种修饰词：(银联|储蓄卡|借记卡|信用卡|银行卡|贷记卡|白金卡|金卡|普卡)
    bankPart = bankPart.replace(/(?:银联|储蓄卡|借记卡|信用卡|银行卡|贷记卡|白金卡|金卡|普卡)/g, '').trim();
    // 清理残留的非文字符号（保留中文、英文字母）
    bankPart = bankPart.replace(/^[·\-_/\s()（）\[\]【】]+|[·\-_/\s()（）\[\]【】]+$/g, '').trim();

    // 5. 组合输出
    if (cardDigits) {
      if (isSquare) {
        return `${bankPart}[${cardDigits}]`;
      } else {
        return `${bankPart}(${cardDigits})`;
      }
    }

    return bankPart || str;
  }

  /**
   * 渠道与扣款账户 SSOT 解析与互斥纠正
   * @param {string} rawChannel 原始渠道
   * @param {string} rawAccount 原始账户
   * @param {Object} [payment] 关联的支付对象 (可选)
   * @returns {{ channel: string, account: string }}
   */
  function resolveChannelAndAccount(rawChannel, rawAccount, payment) {
    let channelCandidate = rawChannel;
    let accountCandidate = rawAccount;

    if (payment && typeof payment === 'object') {
      if (!channelCandidate) {
        channelCandidate = payment.channel || payment.channel_key || '';
      }
      const pBank = payment.bank_name || '';
      const pDigits = payment.card_last_4 || '';
      if (!accountCandidate) {
        if (pBank && pDigits) {
          accountCandidate = `${pBank}(${pDigits})`;
        } else {
          accountCandidate = payment.sub_type || payment.account || payment.display_name || '';
        }
      } else if (accountCandidate === '银行卡' && pBank && pDigits) {
        accountCandidate = `${pBank}(${pDigits})`;
      }
    }

    // 若 accountCandidate 中包含 '·'，分离出渠道与子账户
    if (accountCandidate && String(accountCandidate).includes('·')) {
      const parts = String(accountCandidate).split('·').map(s => s.trim());
      if (!channelCandidate) {
        channelCandidate = parts[0];
      }
      accountCandidate = parts[1];
    }

    // 若 channelCandidate 为空，但 accountCandidate 仅为渠道别名
    if (!channelCandidate && accountCandidate) {
      const trimmed = String(accountCandidate).trim();
      if (['微信', '微信支付', 'wx', 'wechat', '支付宝', 'alipay', '云闪付', '银联', 'unionpay'].includes(trimmed)) {
        channelCandidate = trimmed;
        accountCandidate = '';
      }
    }

    const channel = normalizeChannelName(channelCandidate || accountCandidate);
    let account = String(accountCandidate || '').trim();

    // 若 account 提取后依然等于渠道名称或其别名，清空以触发默认账户
    if (['微信', '微信支付', 'wx', 'wechat', '支付宝', 'alipay', '云闪付', '银联', 'unionpay'].includes(account)) {
      account = '';
    }

    // 若无账户，回退至该渠道的 SSOT 默认账户（云闪付通用默认 '银行卡'）
    if (!account) {
      account = CHANNEL_DEFAULT_ACCOUNT[channel] || (channel === '云闪付' ? '银行卡' : '钱包');
      return { channel, account };
    }

    // 若是银行卡（含 银行|卡|\[\d+\]|[（(]\d+[）)]|【\d+】|尾号\d+）
    const isBankCard = /(?:银行|卡|\[\d+\]|[（(]\d+[）)]|【\d+】|尾号\d+)/.test(account);
    if (isBankCard) {
      return {
        channel: channel,
        account: normalizeBankCardAccount(account, channel)
      };
    }

    // 内置账户预处理归一化
    account = normalizeBankCardAccount(account, channel);

    // 渠道专属内置账户互斥纠正
    const wechatBuiltin = CHANNEL_EXCLUSIVE_ACCOUNTS['微信'] || ['钱包', '零钱', '零钱通'];
    const alipayBuiltin = CHANNEL_EXCLUSIVE_ACCOUNTS['支付宝'] || ['余额', '余额宝', '花呗', '蚂蚁花呗'];

    if (channel === '支付宝') {
      if (wechatBuiltin.includes(account)) {
        account = '余额';
      }
    } else if (channel === '微信') {
      if (alipayBuiltin.includes(account)) {
        account = '钱包';
      }
    } else if (channel === '云闪付') {
      if (wechatBuiltin.includes(account) || alipayBuiltin.includes(account)) {
        account = '银行卡';
      }
    }

    return { channel, account };
  }

  /**
   * 支付方式结构化解析函数 (升级支持动态银行卡与 SSOT 归一化)
   * @param {string|Object} accStr
   * @returns {{ channel: string, channel_key: string, sub_type: string, bank_name: string|null, card_last_4: string|null, display_name: string }}
   */
  function parsePaymentMethodString(accStr) {
    if (accStr && typeof accStr === 'object') {
      const channelCandidate = accStr.channel || accStr.channel_key || '';
      const accountCandidate = accStr.sub_type || accStr.account || accStr.display_name || '';
      const resolved = resolveChannelAndAccount(channelCandidate, accountCandidate, accStr);
      let bank_name = accStr.bank_name || null;
      let card_last_4 = accStr.card_last_4 || null;
      if (!bank_name || !card_last_4) {
        const bankMatch = resolved.account.match(/^(.*?)[（(\[【](?:尾号)?(\d{3,8})[）)\]】]$/);
        if (bankMatch) {
          bank_name = bankMatch[1];
          card_last_4 = bankMatch[2];
        } else if (/(?:银行|卡)/.test(resolved.account)) {
          bank_name = resolved.account;
        }
      }
      return {
        channel: resolved.channel,
        channel_key: resolved.channel === '微信' ? 'wechat' : (resolved.channel === '支付宝' ? 'alipay' : 'unionpay'),
        sub_type: resolved.account,
        bank_name: bank_name,
        card_last_4: card_last_4,
        display_name: `${resolved.channel} · ${resolved.account}`
      };
    }

    const clean = String(accStr || '').trim();
    let rawChannel = '';
    let rawAccount = clean;

    if (clean.includes('·')) {
      const parts = clean.split('·').map(s => s.trim());
      rawChannel = parts[0];
      rawAccount = parts[1];
    } else if (clean === '云闪付' || clean === '银联' || clean === 'unionpay') {
      rawChannel = '云闪付';
      rawAccount = '';
    } else if (clean === '支付宝' || clean === 'alipay') {
      rawChannel = '支付宝';
      rawAccount = '';
    } else if (clean === '微信' || clean === '微信支付' || clean === 'wx') {
      rawChannel = '微信';
      rawAccount = '';
    }

    const resolved = resolveChannelAndAccount(rawChannel, rawAccount);
    const channel = resolved.channel;
    const account = resolved.account;
    const channel_key = channel === '微信' ? 'wechat' : (channel === '支付宝' ? 'alipay' : 'unionpay');

    let bank_name = null;
    let card_last_4 = null;

    // 从规范化后的 account 中提取 bank_name 与 card_last_4
    const bankMatch = account.match(/^(.*?)[（(\[【](?:尾号)?(\d{3,8})[）)\]】]$/);
    if (bankMatch) {
      bank_name = bankMatch[1];
      card_last_4 = bankMatch[2];
    } else if (/(?:银行|卡)/.test(account)) {
      bank_name = account;
    }

    return {
      channel: channel,
      channel_key: channel_key,
      sub_type: account,
      bank_name: bank_name,
      card_last_4: card_last_4,
      display_name: `${channel} · ${account}`
    };
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

    function stripBankCardDecorations(val) {
      if (!val) return '';
      let s = String(val).trim();
      if (s.includes('·')) s = s.split('·')[1].trim();
      s = s.replace(/^中国(工商银行|建设银行|农业银行|民生银行|光大银行|交通银行|招商银行)/, '$1');
      s = s.replace(/^中国邮政储蓄银行|^邮政储蓄银行/, '邮储银行');
      s = s.replace(/(?:银联|储蓄卡|借记卡|信用卡|银行卡|贷记卡|白金卡|金卡|普卡|尾号)/g, '');
      s = s.replace(/[\[【（]/g, '(').replace(/[\]】）]/g, ')');
      s = s.replace(/\s+/g, '');
      return s;
    }

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
      if (target === '花呗' && (optVal === '花呗' || optVal === '蚂蚁花呗')) return true;
      if ((target === '招商银行(8848)' || target === '招商银行储蓄卡' || target === '招商银行储蓄卡(1234)') && (optVal === '招商银行(8848)' || optVal === '招商银行储蓄卡(1234)')) return true;
      if (target === '建设银行(1234)' && optVal === '建设银行(1234)') return true;
      if (target === '工商银行(5678)' && optVal === '工商银行(5678)') return true;
      if ((target === '银行卡' || target === '工商银行(5678)') && (optVal === '工商银行(5678)' || optVal === '银行卡')) return true;
      if (String(target).includes('·')) {
        const sub = String(target).split('·')[1].trim();
        if (optVal === sub || optVal.includes(sub) || sub.includes(optVal)) return true;
        if ((optVal === '工商银行(5678)' || optVal === '银行卡') && (sub === '工商银行(5678)' || sub === '银行卡')) return true;
      }

      // 动态银行卡及方括号/圆括号容错匹配
      const cleanOpt = stripBankCardDecorations(optVal);
      const cleanTarget = stripBankCardDecorations(target);
      if (cleanOpt && cleanTarget && cleanOpt === cleanTarget) return true;

      const optDigits = (String(optVal).match(/\d{3,8}/) || [])[0];
      const targetDigits = (String(target).match(/\d{3,8}/) || [])[0];
      if (optDigits && targetDigits && optDigits === targetDigits) {
        const optBank = cleanOpt.replace(/[（(]\d+[）)]/, '');
        const targetBank = cleanTarget.replace(/[（(]\d+[）)]/, '');
        if (optBank && targetBank && (optBank.includes(targetBank) || targetBank.includes(optBank))) {
          return true;
        }
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
      if ((target === '云闪付' || target === '银联') && (optVal === '云闪付 · 工商银行(5678)' || optVal === '云闪付 · 银行卡')) return true;
      if ((target === '云闪付 · 银行卡' || target === '银行卡') && (optVal === '云闪付 · 工商银行(5678)' || optVal === '云闪付 · 银行卡')) return true;
      if ((target === '云闪付 · 工商银行(5678)' || target === '工商银行(5678)') && (optVal === '云闪付 · 银行卡' || optVal === '云闪付 · 工商银行(5678)')) return true;

      // 动态银行卡及方括号/圆括号容错匹配
      const cleanOpt = stripBankCardDecorations(optVal);
      const cleanTarget = stripBankCardDecorations(target);
      if (cleanOpt && cleanTarget && cleanOpt === cleanTarget) return true;

      const optDigits = (String(optVal).match(/\d{3,8}/) || [])[0];
      const targetDigits = (String(target).match(/\d{3,8}/) || [])[0];
      if (optDigits && targetDigits && optDigits === targetDigits) {
        const optBank = cleanOpt.replace(/[（(]\d+[）)]/, '');
        const targetBank = cleanTarget.replace(/[（(]\d+[）)]/, '');
        if (optBank && targetBank && (optBank.includes(targetBank) || targetBank.includes(optBank))) {
          return true;
        }
      }
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
    return '';
  }

  /**
   * 获取指定服务商的默认模型 Model
   */
  function getDefaultModelForProvider(provider) {
    return '';
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
    '#f9661c', '#d438f3', '#2ef7f0', '#f472b6', '#44c0f6',
    '#fbaf3c', '#d42d9f', '#f979dd', '#15fa56', '#c6cc70'
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

        totals[resolvedCat] = Math.round(((totals[resolvedCat] || 0) + amt) * 100) / 100;
      });
    }

    const total = Object.values(totals).reduce((a, b) => Math.round((a + b) * 100) / 100, 0);
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
  
  /**
   * 应用版本元数据与 OTA 模拟发版配置 (SSOT Domain Layer)
   */
  const APP_VERSION_META = {
    packageId: 'com.singwallet.app',
    signingFingerprint: 'SHA256:8F:4A:2C:91:E7:0B:3D:66:SINGWALLET:RELEASE',
    currentVersion: '1.0.0',
    buildNumber: 100,
    dbSchemaVersion: 2,
    repo: 'Hsanli060/singwallet',
    branch: 'master',
    githubRepo: 'Hsanli060/singwallet',
    githubBranch: 'master',
    releasesApiUrl: 'https://api.github.com/repos/Hsanli060/singwallet/releases/latest',
    commitsApiUrl: 'https://api.github.com/repos/Hsanli060/singwallet/commits/master',
    latestMockRelease: {
      version: '1.1.0',
      buildNumber: 110,
      publishedAt: '2026-10-27',
      apkSize: '18.4 MB',
      downloadUrl: 'https://github.com/singwallet/singwallet/releases/download/v1.1.0/singwallet-v1.1.0-release.apk',
      changelog: [
        '新增月度净支出面板实心饼状图与动态分类占比统计',
        '新增自定义账单分类双列网格管理与大模型输出约束联动',
        '新增快记一笔后台异步草稿解析任务队列与极简进度条',
        '优化 SQLite v2 增量迁移引擎与全量 JSON 备份恢复机制'
      ]
    }
  };

  /**
   * 纯函数语义化版本比较器 (Semver Comparator)
   * 自动去除前缀 'v'/'V'，按 '.' 拆分主/次/修订号比较。
   * @param {string} v1
   * @param {string} v2
   * @returns {number} 若 v1 > v2 返回 1；v1 < v2 返回 -1；相等返回 0
   */
  function compareVersions(v1, v2) {
    const clean1 = String(v1 || '').trim().replace(/^[vV]/, '');
    const clean2 = String(v2 || '').trim().replace(/^[vV]/, '');
    const p1 = clean1.split('.').map(n => parseInt(n, 10) || 0);
    const p2 = clean2.split('.').map(n => parseInt(n, 10) || 0);
    const len = Math.max(p1.length, p2.length, 3);
    for (let i = 0; i < len; i++) {
      const num1 = p1[i] || 0;
      const num2 = p2[i] || 0;
      if (num1 > num2) return 1;
      if (num1 < num2) return -1;
    }
    return 0;
  }

  /**
   * 协议兼容 OTA 更新载荷解析器 (GitHub Releases API 与 自定义 version.json)
   * @param {Object} [payload] 远端响应 Payload
   * @param {string} [currentVersion='1.0.0'] 当前版本号
   * @returns {{ hasUpdate: boolean, currentVersion: string, latestVersion: string, changelog: Array<string>, downloadUrl: string, apkSize: string, publishedAt: string, preserveDataGuaranteed: boolean }}
   */
  function parseOtaReleasePayload(payload, currentVersion = '1.0.0') {
    const defaultRelease = APP_VERSION_META.latestMockRelease;
    const curVer = String(currentVersion || APP_VERSION_META.currentVersion || '1.0.0').trim().replace(/^[vV]/, '');

    if (!payload || typeof payload !== 'object') {
      return {
        hasUpdate: false,
        currentVersion: curVer,
        latestVersion: curVer,
        changelog: [],
        downloadUrl: '',
        apkSize: '',
        publishedAt: '',
        preserveDataGuaranteed: true
      };
    }

    let latestVersion = '';
    let changelog = [];
    let downloadUrl = '';
    let apkSize = '';
    let publishedAt = '';

    // a) GitHub Releases API 格式
    if (payload.tag_name || Array.isArray(payload.assets)) {
      latestVersion = String(payload.tag_name || payload.name || '').trim().replace(/^[vV]/, '');
      publishedAt = payload.published_at ? String(payload.published_at).slice(0, 10) : (defaultRelease.publishedAt || '');

      if (payload.body) {
        changelog = String(payload.body)
          .split(/\r?\n/)
          .map(line => line.trim().replace(/^[-*•\d.]+\s*/, ''))
          .filter(line => line.length > 0 && !line.startsWith('http') && !line.startsWith('#'));
      }

      if (Array.isArray(payload.assets) && payload.assets.length > 0) {
        const apkAsset = payload.assets.find(a => (a.name && a.name.endsWith('.apk')) || (a.browser_download_url && a.browser_download_url.endsWith('.apk'))) || payload.assets[0];
        if (apkAsset) {
          downloadUrl = apkAsset.browser_download_url || apkAsset.url || '';
          if (apkAsset.size) {
            apkSize = (apkAsset.size / (1024 * 1024)).toFixed(1) + ' MB';
          }
        }
      }
    }
    // b) 自定义 version.json 格式
    else if (payload.version || payload.latestVersion || payload.changelog) {
      latestVersion = String(payload.version || payload.latestVersion || '').trim().replace(/^[vV]/, '');
      downloadUrl = payload.downloadUrl || payload.apkUrl || payload.url || '';
      apkSize = payload.apkSize || (payload.size ? (payload.size / (1024 * 1024)).toFixed(1) + ' MB' : '');
      publishedAt = payload.publishedAt || payload.releaseDate || payload.date || '';

      if (Array.isArray(payload.changelog)) {
        changelog = payload.changelog.map(item => String(item).trim()).filter(Boolean);
      } else if (typeof payload.changelog === 'string') {
        changelog = payload.changelog
          .split(/\r?\n/)
          .map(line => line.trim().replace(/^[-*•\d.]+\s*/, ''))
          .filter(Boolean);
      }
    }
    // c) GitHub Commit API 格式 (免编译 Web 秒级热更新)
    else if (payload.sha || (payload.commit && payload.commit.message)) {
      const sha = String(payload.sha || '');
      const shortSha = sha ? sha.slice(0, 7) : '';
      latestVersion = curVer;
      downloadUrl = '';
      apkSize = 'Web 热更新';
      publishedAt = (payload.commit && payload.commit.author && payload.commit.author.date)
        ? String(payload.commit.author.date).slice(0, 10)
        : new Date().toISOString().slice(0, 10);

      if (payload.commit && payload.commit.message) {
        changelog = String(payload.commit.message)
          .split(/\r?\n/)
          .map(line => line.trim().replace(/^[-*•\d.]+\s*/, ''))
          .filter(line => line.length > 0 && !line.startsWith('Co-authored-by') && !line.startsWith('Signed-off-by'));
      }
      if (changelog.length === 0) {
        changelog = [`免编译热更新 Commit #${shortSha}`];
      }

      return {
        hasUpdate: true,
        isWebHotUpdate: true,
        commitSha: sha,
        shortSha: shortSha,
        currentVersion: curVer,
        latestVersion: curVer,
        changelog: changelog,
        downloadUrl: downloadUrl,
        apkSize: apkSize,
        publishedAt: publishedAt,
        preserveDataGuaranteed: true
      };
    }

    // 兜底回退
    if (!latestVersion) latestVersion = defaultRelease.version;
    if (changelog.length === 0) changelog = [...defaultRelease.changelog];
    if (!downloadUrl) downloadUrl = defaultRelease.downloadUrl;
    if (!apkSize) apkSize = defaultRelease.apkSize;
    if (!publishedAt) publishedAt = defaultRelease.publishedAt;

    return {
      hasUpdate: compareVersions(latestVersion, curVer) > 0,
      currentVersion: curVer,
      latestVersion: latestVersion,
      changelog: changelog,
      downloadUrl: downloadUrl,
      apkSize: apkSize,
      publishedAt: publishedAt,
      preserveDataGuaranteed: true
    };
  }

  /**
   * 将当前应用完整状态打包成标准备份 JSON 快照对象
   * @param {Object} [appState]
   * @returns {Object}
   */
  function exportFullBackupSnapshot(appState = {}) {
    const state = appState || {};
    return {
      backupMagic: 'SINGWALLET_BACKUP_V2',
      packageId: APP_VERSION_META.packageId,
      appVersion: state.appVersion || APP_VERSION_META.currentVersion,
      dbSchemaVersion: APP_VERSION_META.dbSchemaVersion,
      exportedAt: new Date().toISOString(),
      data: {
        customCategories: Array.isArray(state.customCategories) ? [...state.customCategories] : [...CORE_PARENT_CATEGORIES],
        vlmConfig: (state.vlmConfig && typeof state.vlmConfig === 'object') ? state.vlmConfig : {},
        transactions: Array.isArray(state.transactions) ? state.transactions : [],
        monthlyData: (state.monthlyData && typeof state.monthlyData === 'object') ? state.monthlyData : {},
        draftQueue: Array.isArray(state.draftQueue) ? state.draftQueue : []
      }
    };
  }

  /**
   * 校验并执行增量无损备份恢复迁移 (模拟 onUpgrade v1 -> v2)
   * @param {string|Object} rawInput JSON 字符串或对象
   * @returns {{ valid: boolean, error?: string, migratedFromVersion?: number, targetSchemaVersion?: number, data?: Object }}
   */
  function validateAndMigrateBackupSnapshot(rawInput) {
    let parsed = rawInput;
    if (typeof rawInput === 'string') {
      try {
        parsed = JSON.parse(rawInput);
      } catch (e) {
        return { valid: false, error: '无效的备份文件格式' };
      }
    }

    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return { valid: false, error: '无效的备份文件格式' };
    }

    // 必须包含合法备份结构字段，禁止空对象 {} 静默通过
    const hasDataObj = Boolean(parsed.data && typeof parsed.data === 'object' && !Array.isArray(parsed.data) && Object.keys(parsed.data).length > 0);
    const hasRootTx = Array.isArray(parsed.transactions) || Array.isArray(parsed.user_transactions);
    const hasRootCats = Array.isArray(parsed.customCategories) || Array.isArray(parsed.custom_categories) || Array.isArray(parsed.categories);
    const hasMetaKeys = Boolean(parsed.version || parsed.schemaVersion || parsed.dbSchemaVersion || parsed.backupMagic || parsed.budget !== undefined || parsed.monthly_budget !== undefined || parsed.vlm_configs || parsed.vlmConfig);

    if (!hasDataObj && !hasRootTx && !hasRootCats && !hasMetaKeys) {
      return { valid: false, error: '无效的备份文件格式' };
    }

    const sourceData = hasDataObj ? parsed.data : parsed;
    const oldVer = parsed.dbSchemaVersion || (parsed.backupMagic === 'SINGWALLET_BACKUP_V2' ? 2 : 1);

    // 1. 自定义分类无损保留
    let customCategories = [...CORE_PARENT_CATEGORIES];
    if (Array.isArray(sourceData.customCategories) && sourceData.customCategories.length > 0) {
      customCategories = [...sourceData.customCategories];
    }

    // 2. VLM 配置保留
    const vlmConfig = (sourceData.vlmConfig && typeof sourceData.vlmConfig === 'object')
      ? sourceData.vlmConfig
      : {};

    // 3. 历史流水增量迁移与规范化 (补齐缺失 orderId 为 '')
    const rawTxList = Array.isArray(sourceData.transactions) ? sourceData.transactions : [];
    const transactions = rawTxList.map(tx => {
      if (!tx || typeof tx !== 'object') return tx;
      return {
        ...tx,
        orderId: (tx.orderId !== undefined && tx.orderId !== null) ? String(tx.orderId) : ''
      };
    });

    // 4. 月度数据与异步草稿队列
    const monthlyData = (sourceData.monthlyData && typeof sourceData.monthlyData === 'object')
      ? sourceData.monthlyData
      : {};
    const draftQueue = Array.isArray(sourceData.draftQueue) ? sourceData.draftQueue : [];

    return {
      valid: true,
      migratedFromVersion: Number(oldVer) || 1,
      targetSchemaVersion: APP_VERSION_META.dbSchemaVersion,
      data: {
        customCategories,
        vlmConfig,
        transactions,
        monthlyData,
        draftQueue
      }
    };
  }

  // 领域元数据配置对象 (SSOT)
  const SINGWALLET_DOMAIN_CONFIG = {
    categories: CORE_CATEGORIES,
    parentCategories: CORE_PARENT_CATEGORIES,
    subToParentMap: subToParentCategoryMap,
    defaultIcons: defaultCategoryIconMap,
    channels: PAYMENT_CHANNELS,
    CHANNEL_DEFAULT_ACCOUNT: CHANNEL_DEFAULT_ACCOUNT,
    CHANNEL_EXCLUSIVE_ACCOUNTS: CHANNEL_EXCLUSIVE_ACCOUNTS,
    normalizeChannelName: normalizeChannelName,
    normalizeBankCardAccount: normalizeBankCardAccount,
    resolveChannelAndAccount: resolveChannelAndAccount,
    providers: VLM_PROVIDERS,
    defaultBooks: DEFAULT_BOOKS,
    defaultProjects: DEFAULT_PROJECTS,
    schema: BILL_STRUCTURED_SCHEMA,
    normalizeOrderId: normalizeOrderId,
    isOrderIdDuplicate: isOrderIdDuplicate,
    partitionDraftsByDedup: partitionDraftsByDedup,
    CATEGORY_CHART_PALETTE: CATEGORY_CHART_PALETTE,
    formatCompactAmount: formatCompactAmount,
    computeCategoryBreakdown: computeCategoryBreakdown,
    APP_VERSION_META: APP_VERSION_META,
    compareVersions: compareVersions,
    parseOtaReleasePayload: parseOtaReleasePayload,
    exportFullBackupSnapshot: exportFullBackupSnapshot,
    validateAndMigrateBackupSnapshot: validateAndMigrateBackupSnapshot
  };

  // 领域注册管理中心 (DomainRegistry / SingWalletDomain)
  const DomainRegistry = {
    getConfig: () => SINGWALLET_DOMAIN_CONFIG,
    getCategories: () => CORE_CATEGORIES,
    getParentCategories: () => [...CORE_PARENT_CATEGORIES],
    get activeCategories() { return CORE_PARENT_CATEGORIES; },
    getCategoryByName: (name) => {
      const parent = resolveParentCategory(name);
      return CORE_CATEGORIES.find(c => c.name === parent) || null;
    },
    resolveParentCategory: resolveParentCategory,
    addCategory: addCategory,
    removeCategory: removeCategory,
    renameCategory: renameCategory,
    resetCategories: resetCategories,
    getChannels: () => PAYMENT_CHANNELS,
    CHANNEL_DEFAULT_ACCOUNT: CHANNEL_DEFAULT_ACCOUNT,
    CHANNEL_EXCLUSIVE_ACCOUNTS: CHANNEL_EXCLUSIVE_ACCOUNTS,
    normalizeChannelName: normalizeChannelName,
    normalizeBankCardAccount: normalizeBankCardAccount,
    resolveChannelAndAccount: resolveChannelAndAccount,
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
    computeCategoryBreakdown: computeCategoryBreakdown,
    APP_VERSION_META: APP_VERSION_META,
    compareVersions: compareVersions,
    parseOtaReleasePayload: parseOtaReleasePayload,
    exportFullBackupSnapshot: exportFullBackupSnapshot,
    validateAndMigrateBackupSnapshot: validateAndMigrateBackupSnapshot
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
  window.renameCategory = renameCategory;
  window.resetCategories = resetCategories;
  window.parsePaymentMethodString = parsePaymentMethodString;
  window.CHANNEL_DEFAULT_ACCOUNT = CHANNEL_DEFAULT_ACCOUNT;
  window.CHANNEL_EXCLUSIVE_ACCOUNTS = CHANNEL_EXCLUSIVE_ACCOUNTS;
  window.normalizeChannelName = normalizeChannelName;
  window.normalizeBankCardAccount = normalizeBankCardAccount;
  window.resolveChannelAndAccount = resolveChannelAndAccount;
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
  window.APP_VERSION_META = APP_VERSION_META;
  window.compareVersions = compareVersions;
  window.parseOtaReleasePayload = parseOtaReleasePayload;
  window.exportFullBackupSnapshot = exportFullBackupSnapshot;
  window.validateAndMigrateBackupSnapshot = validateAndMigrateBackupSnapshot;

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = DomainRegistry;
  }

})(typeof window !== 'undefined' ? window : (typeof global !== 'undefined' ? global : this));
