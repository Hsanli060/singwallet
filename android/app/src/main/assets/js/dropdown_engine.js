/**
 * SingWallet 自定义下拉浮层引擎与联动控制器 (Dropdown Engine & Form Linkage)
 * 纯 HTML/CSS 打造无原生 Win32 弹框的安全下拉浮层系统，并包含日期与多级支付渠道联动。
 */

(function (window) {
  'use strict';

  // ================= 内部渠道与账户规范化辅助函数 =================
  function _normChan(ch) {
    if (window.DomainRegistry && typeof window.DomainRegistry.normalizeChannelName === 'function') {
      return window.DomainRegistry.normalizeChannelName(ch);
    }
    if (typeof window.normalizeChannelName === 'function') {
      return window.normalizeChannelName(ch);
    }
    const str = String(ch || '').trim();
    if (!str) return '微信';
    if (/支付宝|alipay/i.test(str)) return '支付宝';
    if (/云闪付|银联|unionpay/i.test(str)) return '云闪付';
    if (/微信|wechat|wx/i.test(str)) return '微信';
    if (/现金/i.test(str)) return '现金';
    return str || '微信';
  }

  function _normBankAcc(acc, ch) {
    if (window.DomainRegistry && typeof window.DomainRegistry.normalizeBankCardAccount === 'function') {
      return window.DomainRegistry.normalizeBankCardAccount(acc, ch);
    }
    if (typeof window.normalizeBankCardAccount === 'function') {
      return window.normalizeBankCardAccount(acc, ch);
    }
    let s = String(acc || '').trim();
    if (!s) return '';
    if (s.includes(' · ')) {
      s = s.split(' · ')[1].trim();
    } else if (s.includes('·')) {
      s = s.split('·')[1].trim();
    }
    // 保留原始方括号 [5678] 或圆括号 (5678)，不要把 [5678] 强转为 (5678)
    const bracketMatch = s.match(/^(.*?)(\[|\()(\d{4})(\]|\))$/);
    if (bracketMatch) {
      const bank = bracketMatch[1].trim();
      const left = bracketMatch[2];
      const digits = bracketMatch[3];
      const right = bracketMatch[4];
      return `${bank}${left}${digits}${right}`;
    }
    const digitsMatch = s.match(/^(.*?)(\d{4})$/);
    if (digitsMatch) {
      const bank = digitsMatch[1].trim();
      return `${bank}(${digitsMatch[2]})`;
    }
    return s;
  }

  function _resolveChanAcc(rawChan, rawAcc, payment) {
    if (window.DomainRegistry && typeof window.DomainRegistry.resolveChannelAndAccount === 'function') {
      return window.DomainRegistry.resolveChannelAndAccount(rawChan, rawAcc, payment);
    }
    if (typeof window.resolveChannelAndAccount === 'function') {
      return window.resolveChannelAndAccount(rawChan, rawAcc, payment);
    }
    let channel = _normChan(rawChan || (payment && payment.channel) || '');
    let account = _normBankAcc(rawAcc || (payment && payment.account) || '', channel);

    if (channel === '支付宝' && account === '钱包') {
      account = '余额';
    }
    if (channel === '微信' && account === '余额') {
      account = '钱包';
    }
    if (!account) {
      if (channel === '微信') account = '钱包';
      else if (channel === '支付宝') account = '余额';
      else if (channel === '云闪付') account = '工商银行(5678)';
      else account = '钱包';
    }
    return { channel, account };
  }

  /**
   * 确保指定账户在下拉框选项中存在，若不存在则动态创建并注入
   */
  function ensureAccountOptionInDropdown(selectId, channel, accountValue) {
    if (!selectId || !accountValue) return null;
    const pureId = selectId.replace(/^menu-/, '').replace(/^dropdown-wrap-/, '');
    const normChan = _normChan(channel);
    const normAcc = _normBankAcc(accountValue, normChan);
    if (!normAcc) return null;

    const menu = document.getElementById('menu-' + pureId);
    if (!menu) return null;

    // 1. 如果当前渠道下已有同名或等价选项，直接复用
    const existing = Array.from(menu.querySelectorAll('.custom-dropdown-option')).find(opt => {
      const c = opt.getAttribute('data-channel');
      const v = opt.getAttribute('data-value');
      return (!c || c === normChan) && (v === normAcc || (window.isOptionMatch && window.isOptionMatch(pureId, v, normAcc)));
    });

    if (existing) {
      return existing;
    }

    // 2. 如果该账户是微信/支付宝内置专属钱包类账户 (钱包/零钱/零钱通/余额/余额宝/花呗)，绝不跨渠道重复创建
    const isBuiltinExclusive = ['钱包', '零钱', '零钱通', '余额', '余额宝', '花呗', '现金'].includes(normAcc);
    if (isBuiltinExclusive) {
      const anyExisting = Array.from(menu.querySelectorAll('.custom-dropdown-option')).find(opt => {
        const v = opt.getAttribute('data-value');
        return v === normAcc || (window.isOptionMatch && window.isOptionMatch(pureId, v, normAcc));
      });
      if (anyExisting) return anyExisting;
    }

    const optDiv = document.createElement('div');
    optDiv.className = 'custom-dropdown-option rounded-xl';
    optDiv.tabIndex = 0;
    optDiv.setAttribute('data-channel', normChan);
    optDiv.setAttribute('data-value', normAcc);
    optDiv.setAttribute('onclick', `selectCustomDropdownOption('${pureId}', '${normAcc}', event)`);
    optDiv.setAttribute('onkeydown', `if(event.key==='Enter'||event.key===' '){selectCustomDropdownOption('${pureId}', '${normAcc}', event);event.preventDefault();}`);

    optDiv.innerHTML = `<span class="truncate">${normAcc}</span><span class="opt-check">✓</span>`;
    menu.appendChild(optDiv);
    return optDiv;
  }

  /**
   * 实时根据选定渠道过滤账户下拉列表选项的可见性
   */
  function filterAccountDropdownOptions(id) {
    const pureId = (id || '').replace(/^menu-/, '').replace(/^dropdown-wrap-/, '');
    if (pureId !== 'select-account' && pureId !== 'manual-pay-sub') return;

    const channelInputId = pureId === 'select-account' ? 'select-channel' : 'manual-pay-channel';
    const channelInput = document.getElementById(channelInputId);
    const currentChannel = _normChan(channelInput ? channelInput.value : '');

    const menu = document.getElementById('menu-' + pureId);
    if (!menu) return;

    const options = menu.querySelectorAll('.custom-dropdown-option');
    options.forEach(opt => {
      const optChannel = opt.getAttribute('data-channel');
      if (!optChannel || optChannel === currentChannel) {
        opt.style.display = '';
      } else {
        opt.style.display = 'none';
      }
    });
  }

  /**
   * 动态计算菜单展开朝向（结合底部导航栏与屏幕容器计算边界，动态控制最大高度与向上展开）
   */
  function adjustDropdownPosition(wrap, menu) {
    if (!wrap || !menu) return;
    try {
      const rect = wrap.getBoundingClientRect();
      let bottomBoundary = window.innerHeight;
      const navBar = document.getElementById('bottom-nav-bar');
      if (navBar) {
        const navRect = navBar.getBoundingClientRect();
        if (navRect.top > 0 && navRect.top < bottomBoundary) {
          bottomBoundary = navRect.top;
        }
      }
      const screenContainer = document.getElementById('screen-container');
      if (screenContainer) {
        const scRect = screenContainer.getBoundingClientRect();
        if (scRect.bottom > 0 && scRect.bottom < bottomBoundary) {
          bottomBoundary = scRect.bottom;
        }
      }

      let topBoundary = 0;
      if (screenContainer) {
        const scRect = screenContainer.getBoundingClientRect();
        if (scRect.top > 0) {
          topBoundary = scRect.top;
        }
      }

      const spaceBelow = bottomBoundary - rect.bottom - 12;
      const spaceAbove = rect.top - topBoundary - 12;

      if (spaceBelow < 220 && spaceAbove > spaceBelow) {
        menu.classList.add('menu-dropup');
        menu.style.maxHeight = Math.min(260, Math.max(120, Math.floor(spaceAbove - 8))) + 'px';
      } else {
        menu.classList.remove('menu-dropup');
        menu.style.maxHeight = Math.min(220, Math.max(100, Math.floor(spaceBelow - 8))) + 'px';
      }
    } catch (e) {}
  }

  /**
   * 打开指定 ID 的自定义下拉浮层
   */
  function openCustomDropdownId(id) {
    const wrap = document.getElementById('dropdown-wrap-' + id);
    const menu = document.getElementById('menu-' + id);
    const trigger = wrap ? wrap.querySelector('.custom-dropdown-trigger') : null;
    if (!menu) return;

    filterAccountDropdownOptions(id);
    closeAllCustomDropdowns();
    adjustDropdownPosition(wrap, menu);
    menu.classList.add('open');
    if (trigger) trigger.classList.add('active');
    if (wrap) wrap.classList.add('z-active');
  }

  /**
   * 切换指定 ID 下拉菜单的展开/收起状态
   */
  function toggleCustomDropdown(id, event) {
    if (event) {
      event.stopPropagation();
    }
    const wrap = document.getElementById('dropdown-wrap-' + id);
    const menu = document.getElementById('menu-' + id);
    const trigger = wrap ? wrap.querySelector('.custom-dropdown-trigger') : null;
    if (!menu) return;

    filterAccountDropdownOptions(id);
    const isOpen = menu.classList.contains('open');
    closeAllCustomDropdowns();

    if (!isOpen) {
      adjustDropdownPosition(wrap, menu);
      menu.classList.add('open');
      if (trigger) trigger.classList.add('active');
      if (wrap) wrap.classList.add('z-active');
    }
  }

  /**
   * 关闭全局所有已展开的下拉菜单
   */
  function closeAllCustomDropdowns() {
    document.querySelectorAll('.custom-dropdown-menu.open').forEach(menu => {
      menu.classList.remove('open');
    });
    document.querySelectorAll('.custom-dropdown-trigger.active').forEach(trigger => {
      trigger.classList.remove('active');
    });
    document.querySelectorAll('.custom-dropdown-container.z-active').forEach(wrap => {
      wrap.classList.remove('z-active');
    });
  }

  /**
   * 选择下拉菜单中的选项，同步底层 Input、更新触发器文本与最新图标，并触发相关联动事件
   */
  function selectCustomDropdownOption(id, value, event) {
    if (event) {
      event.stopPropagation();
    }
    const input = document.getElementById(id);
    const wrap = document.getElementById('dropdown-wrap-' + id);
    const menu = document.getElementById('menu-' + id);
    const label = document.getElementById('label-' + id);

    if (!menu) return;

    // 更新各选项高亮与选中状态
    const options = menu.querySelectorAll('.custom-dropdown-option');
    let displayLabel = value;
    let matchedCatIcon = null;

    options.forEach(opt => {
      const optVal = opt.getAttribute('data-value');
      const matchFn = window.isOptionMatch || (window.DomainRegistry && window.DomainRegistry.isOptionMatch);
      const isMatched = matchFn ? matchFn(id, optVal, value) : (optVal === String(value));

      if (isMatched) {
        opt.classList.add('selected');
        const span = opt.querySelector('.opt-text') || opt.querySelector('.truncate') || opt.querySelector('span');
        if (span) {
          displayLabel = (span.textContent || span.innerText || '').trim();
        }
        const catIconEl = opt.querySelector('[data-cat-icon]') || (opt.hasAttribute('data-cat-icon') ? opt : null);
        if (catIconEl) {
          matchedCatIcon = catIconEl.getAttribute('data-cat-icon');
        }
      } else {
        opt.classList.remove('selected');
      }
    });

    // 更新触发器文本
    if (label) {
      label.textContent = displayLabel;
    }

    // 若选项带有分类图标，确保触发器图标同步为最新图标
    if (wrap) {
      const triggerIconEl = wrap.querySelector('[data-cat-icon]') || wrap.querySelector('.dropdown-selected-icon');
      if (triggerIconEl) {
        const targetCat = matchedCatIcon || value;
        triggerIconEl.setAttribute('data-cat-icon', targetCat);
        if (window.IconRegistry) {
          triggerIconEl.innerHTML = window.IconRegistry.getCategoryIcon(targetCat);
        }
      }
    }

    // 更新底层 Input 值并派发事件
    if (input) {
      const protoDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
      if (protoDescriptor && protoDescriptor.set) {
        protoDescriptor.set.call(input, value);
      } else {
        input.value = value;
      }

      if (id === 'select-channel' && typeof window.onDraftChannelChange === 'function') {
        window.onDraftChannelChange(value);
      }
      if (id === 'manual-pay-channel' && typeof window.onManualChannelChange === 'function') {
        window.onManualChannelChange(value);
      }
      if (id === 'manual-pay-sub' && typeof window.onManualSubChange === 'function') {
        window.onManualSubChange(value);
      }
      if (id === 'manual-account' && typeof value === 'string' && value.includes(' · ')) {
        const parts = value.split(' · ');
        selectCustomDropdownOption('manual-pay-channel', parts[0]);
        selectCustomDropdownOption('manual-pay-sub', parts[1]);
      }
      if (typeof input.dispatchEvent === 'function') {
        input.dispatchEvent(new Event('change', { bubbles: true }));
        input.dispatchEvent(new Event('input', { bubbles: true }));
      }
      if (typeof input.onchange === 'function') {
        try { input.onchange(new Event('change')); } catch (e) {}
      }
    }

    // 关闭菜单浮层
    closeAllCustomDropdowns();

    // 针对特定下拉框触发业务联动回调
    if (id === 'quick-date-dropdown' && typeof window.onQuickDateDropdownChanged === 'function') {
      window.onQuickDateDropdownChanged(value);
    }
    if (id === 'vlm-provider-select' && typeof window.onVlmProviderChange === 'function') {
      window.onVlmProviderChange(value);
    }
  }

  /**
   * 根据当前数值逆向同步下拉菜单的选中状态与显示标签
   */
  function syncCustomDropdownFromValue(id, value) {
    const menu = document.getElementById('menu-' + id);
    const label = document.getElementById('label-' + id);
    const wrap = document.getElementById('dropdown-wrap-' + id);
    if (!menu) return;

    let currentChannel = '';
    if (id === 'select-account' || id === 'manual-pay-sub') {
      const chanInputId = id === 'select-account' ? 'select-channel' : 'manual-pay-channel';
      const chanInput = document.getElementById(chanInputId);
      currentChannel = _normChan(chanInput ? chanInput.value : '');
      if (value) {
        ensureAccountOptionInDropdown(id, currentChannel, value);
      }
      filterAccountDropdownOptions(id);
    }

    const options = menu.querySelectorAll('.custom-dropdown-option');
    let found = false;
    let displayLabel = value;
    let matchedCatIcon = null;

    let bestMatchOpt = null;
    const matchFn = window.isOptionMatch || (window.DomainRegistry && window.DomainRegistry.isOptionMatch);

    // 优先选中与当前渠道完全匹配的选项
    options.forEach(opt => {
      const optVal = opt.getAttribute('data-value');
      const optChan = opt.getAttribute('data-channel');
      const isMatched = matchFn ? matchFn(id, optVal, value) : (optVal === String(value));

      if (isMatched) {
        if (currentChannel && optChan === currentChannel) {
          bestMatchOpt = opt;
        } else if (!bestMatchOpt && (!optChan || !currentChannel)) {
          bestMatchOpt = opt;
        }
      }
    });

    if (!bestMatchOpt) {
      options.forEach(opt => {
        const optVal = opt.getAttribute('data-value');
        const isMatched = matchFn ? matchFn(id, optVal, value) : (optVal === String(value));
        if (isMatched && !bestMatchOpt) {
          bestMatchOpt = opt;
        }
      });
    }

    options.forEach(opt => {
      if (opt === bestMatchOpt) {
        opt.classList.add('selected');
        const span = opt.querySelector('.truncate') || opt.querySelector('span');
        if (span) {
          displayLabel = (span.textContent || span.innerText || '').trim();
        }
        const catIconEl = opt.querySelector('[data-cat-icon]') || (opt.hasAttribute('data-cat-icon') ? opt : null);
        if (catIconEl) {
          matchedCatIcon = catIconEl.getAttribute('data-cat-icon');
        }
        found = true;
      } else {
        opt.classList.remove('selected');
      }
    });

    if (label && (found || displayLabel)) {
      label.textContent = displayLabel;
    }

    if (wrap) {
      const triggerIconEl = wrap.querySelector('[data-cat-icon]') || wrap.querySelector('.dropdown-selected-icon');
      if (triggerIconEl) {
        const targetCat = matchedCatIcon || value;
        triggerIconEl.setAttribute('data-cat-icon', targetCat);
        if (window.IconRegistry) {
          triggerIconEl.innerHTML = window.IconRegistry.getCategoryIcon(targetCat);
        }
      }
    }
  }

  /**
   * 初始化系统中所有的自定义下拉框与全局关闭监听器
   */
  function initAllCustomDropdowns() {
    const dropdownIds = [
      'quick-date-dropdown',
      'select-channel',
      'select-account',
      'select-draft-category',
      'manual-category',
      'manual-account',
      'manual-pay-channel',
      'manual-pay-sub',
      'vlm-provider-select'
    ];

    dropdownIds.forEach(id => {
      const input = document.getElementById(id);
      if (!input) return;

      const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
      Object.defineProperty(input, 'value', {
        get() {
          return descriptor ? descriptor.get.call(this) : this.getAttribute('value');
        },
        set(newVal) {
          if (descriptor && descriptor.set) {
            descriptor.set.call(this, newVal);
          } else {
            this.setAttribute('value', newVal);
          }
          syncCustomDropdownFromValue(id, newVal);
          if (id === 'select-channel' && typeof window.onDraftChannelChange === 'function') {
            window.onDraftChannelChange(newVal);
          }
          if (id === 'manual-pay-channel' && typeof window.onManualChannelChange === 'function') {
            window.onManualChannelChange(newVal);
          }
          if (id === 'vlm-provider-select' && typeof window.onVlmProviderChange === 'function') {
            window.onVlmProviderChange(newVal);
          }
        },
        configurable: true
      });

      // 初始化显示标签
      syncCustomDropdownFromValue(id, input.value);
    });

    filterAccountDropdownOptions('select-account');
    filterAccountDropdownOptions('manual-pay-sub');

    // 绑定全局点击外部及 Escape 关闭事件 (单例绑定)
    if (!window.__dropdownListenersAttached) {
      window.__dropdownListenersAttached = true;

      document.addEventListener('click', function (e) {
        if (!e.target.closest('.custom-dropdown-container')) {
          closeAllCustomDropdowns();
        }
      });

      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') {
          closeAllCustomDropdowns();
        }
      });
    }
  }

  // ================= 日期与时间辅助工具函数 =================
  function getTodayDateString() {
    const d = new Date();
    const pad = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  function formatCurrentDateTime() {
    const d = new Date();
    const pad = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  function isValidDateTimeString(str) {
    if (!str || typeof str !== 'string') return false;
    const match = str.trim().match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/);
    if (!match) return false;
    const y = parseInt(match[1], 10);
    const m = parseInt(match[2], 10);
    const d = parseInt(match[3], 10);
    const hh = parseInt(match[4], 10);
    const mm = parseInt(match[5], 10);
    const ss = parseInt(match[6], 10);

    if (m < 1 || m > 12 || d < 1 || d > 31 || hh < 0 || hh > 23 || mm < 0 || mm > 59 || ss < 0 || ss > 59) {
      return false;
    }
    const dt = new Date(y, m - 1, d, hh, mm, ss);
    return (
      dt.getFullYear() === y &&
      dt.getMonth() === m - 1 &&
      dt.getDate() === d &&
      dt.getHours() === hh &&
      dt.getMinutes() === mm &&
      dt.getSeconds() === ss
    );
  }

  function normalizeDateTimeString(str) {
    let s = (str || '').trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(s)) {
      s += ' 12:00:00';
    }
    return s;
  }

  function formatDateTimeDisplay(val) {
    if (!val) return formatCurrentDateTime();
    if (val instanceof Date) {
      const pad = n => String(n).padStart(2, '0');
      return `${val.getFullYear()}-${pad(val.getMonth() + 1)}-${pad(val.getDate())} ${pad(val.getHours())}:${pad(val.getMinutes())}:${pad(val.getSeconds())}`;
    }
    return normalizeDateTimeString(String(val));
  }

  function parseDisplayToInputValue(str) {
    return normalizeDateTimeString(str);
  }

  function onDraftDatePickerChange(val) {
    const norm = normalizeDateTimeString(val);
    const dateInput = document.getElementById('select-draft-time');
    if (dateInput) dateInput.value = norm;
    if (window.draftQueue && window.draftQueue[window.currentDraftIndex]) {
      window.draftQueue[window.currentDraftIndex].time = norm;
      window.draftQueue[window.currentDraftIndex].orderTime = norm;
    }
  }

  function onManualDatePickerChange(val) {
    const norm = normalizeDateTimeString(val);
    const timeInput = document.getElementById('manual-time');
    if (timeInput) timeInput.value = norm;
  }

  // ================= 支付渠道联动辅助函数 =================
  function onDraftChannelChange(channel) {
    const normChan = _normChan(channel);
    filterAccountDropdownOptions('select-account');
    const accMenu = document.getElementById('menu-select-account');
    if (!accMenu) return;

    const visibleOptions = Array.from(accMenu.querySelectorAll('.custom-dropdown-option')).filter(opt => opt.style.display !== 'none');
    const curAccInput = document.getElementById('select-account');
    const curAcc = curAccInput ? curAccInput.value : '';

    const isCurrentValid = visibleOptions.some(opt => {
      const v = opt.getAttribute('data-value');
      return v === curAcc || (window.isOptionMatch && window.isOptionMatch('select-account', v, curAcc));
    });

    if (!isCurrentValid) {
      let defaultAcc = '';
      if (normChan === '微信') {
        defaultAcc = '钱包';
      } else if (normChan === '支付宝') {
        defaultAcc = '余额';
      } else if (normChan === '云闪付') {
        defaultAcc = '工商银行(5678)';
      }
      const hasDefault = visibleOptions.find(opt => opt.getAttribute('data-value') === defaultAcc);
      const targetAcc = hasDefault ? defaultAcc : (visibleOptions[0] ? visibleOptions[0].getAttribute('data-value') : defaultAcc);
      if (targetAcc) {
        selectCustomDropdownOption('select-account', targetAcc);
      }
    }
  }

  function onManualChannelChange(channel) {
    const subMenu = document.getElementById('menu-manual-pay-sub');
    if (!subMenu) return;
    const options = subMenu.querySelectorAll('.custom-dropdown-option');
    let firstMatch = null;
    options.forEach(opt => {
      const optChannel = opt.getAttribute('data-channel');
      if (!optChannel || optChannel === channel) {
        opt.style.display = '';
        if (!firstMatch) firstMatch = opt.getAttribute('data-value');
      } else {
        opt.style.display = 'none';
      }
    });
    if (firstMatch) {
      selectCustomDropdownOption('manual-pay-sub', firstMatch);
    }
    updateManualAccountCombined();
  }

  function onManualSubChange(sub) {
    updateManualAccountCombined();
  }

  function updateManualAccountCombined() {
    const channel = document.getElementById('manual-pay-channel')?.value || '微信';
    const sub = document.getElementById('manual-pay-sub')?.value || '钱包';
    const combined = `${channel} · ${sub}`;
    const accInput = document.getElementById('manual-account');
    if (accInput) {
      accInput.value = combined;
    }
    const label = document.getElementById('label-manual-account');
    if (label) {
      label.textContent = combined;
    }
    const menu = document.getElementById('menu-manual-account');
    if (menu) {
      menu.querySelectorAll('.custom-dropdown-option').forEach(opt => {
        if (opt.getAttribute('data-value') === combined) {
          opt.classList.add('selected');
        } else {
          opt.classList.remove('selected');
        }
      });
    }
  }

  // 挂载至全局对象
  window.openCustomDropdownId = openCustomDropdownId;
  window.toggleCustomDropdown = toggleCustomDropdown;
  window.closeAllCustomDropdowns = closeAllCustomDropdowns;
  window.selectCustomDropdownOption = selectCustomDropdownOption;
  window.syncCustomDropdownFromValue = syncCustomDropdownFromValue;
  window.initAllCustomDropdowns = initAllCustomDropdowns;
  window.filterAccountDropdownOptions = filterAccountDropdownOptions;
  window.ensureAccountOptionInDropdown = ensureAccountOptionInDropdown;

  window.getTodayDateString = getTodayDateString;
  window.formatCurrentDateTime = formatCurrentDateTime;
  window.isValidDateTimeString = isValidDateTimeString;
  window.normalizeDateTimeString = normalizeDateTimeString;
  window.formatDateTimeDisplay = formatDateTimeDisplay;
  window.parseDisplayToInputValue = parseDisplayToInputValue;
  window.onDraftDatePickerChange = onDraftDatePickerChange;
  window.onManualDatePickerChange = onManualDatePickerChange;

  window.onDraftChannelChange = onDraftChannelChange;
  window.onManualChannelChange = onManualChannelChange;
  window.onManualSubChange = onManualSubChange;
  window.updateManualAccountCombined = updateManualAccountCombined;

  // 仅在全局尚未提供时挂载内部安全兜底函数，严禁覆盖 domain_config.js 提供的实现
  if (typeof window.normalizeBankCardAccount !== 'function') {
    window.normalizeBankCardAccount = _normBankAcc;
  }
  if (typeof window.normalizeChannelName !== 'function') {
    window.normalizeChannelName = _normChan;
  }
  if (typeof window.resolveChannelAndAccount !== 'function') {
    window.resolveChannelAndAccount = _resolveChanAcc;
  }

})(typeof window !== 'undefined' ? window : this);
