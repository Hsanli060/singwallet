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
    if (typeof window.normalizeChannelName === 'function' && window.normalizeChannelName !== _normChan) {
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
    if (typeof window.normalizeBankCardAccount === 'function' && window.normalizeBankCardAccount !== _normBankAcc) {
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
    if (typeof window.resolveChannelAndAccount === 'function' && window.resolveChannelAndAccount !== _resolveChanAcc) {
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
      if (window.CHANNEL_DEFAULT_ACCOUNT && window.CHANNEL_DEFAULT_ACCOUNT[channel]) {
        account = window.CHANNEL_DEFAULT_ACCOUNT[channel];
      } else if (channel === '微信') account = '钱包';
      else if (channel === '支付宝') account = '余额';
      else account = '钱包';
    }
    return { channel, account };
  }

  // ================= 下拉框选项与目标值匹配辅助函数 =================
  function _matchOption(id, optVal, targetVal) {
    if (optVal === targetVal || optVal === String(targetVal)) return true;
    if (!optVal || targetVal == null) return false;

    const matchId = (id === 'detail-edit-channel' || id === 'manual-pay-channel') ? 'select-channel' :
                    (id === 'detail-edit-account' || id === 'manual-pay-sub') ? 'select-account' :
                    (id === 'detail-edit-category' || id === 'select-draft-category') ? 'manual-category' : id;
    const matchFn = window.isOptionMatch || (window.DomainRegistry && window.DomainRegistry.isOptionMatch);
    if (matchFn) {
      if (matchFn(matchId, optVal, targetVal)) return true;
      if (matchId !== id && matchFn(id, optVal, targetVal)) return true;
    }

    // 银行卡括号 [5678] 与 (5678) 兜底等价匹配
    if (typeof optVal === 'string' && typeof targetVal === 'string') {
      const cleanA = optVal.replace(/[\[【（]/g, '(').replace(/[\]】）]/g, ')').replace(/\s+/g, '');
      const cleanB = targetVal.replace(/[\[【（]/g, '(').replace(/[\]】）]/g, ')').replace(/\s+/g, '');
      if (cleanA && cleanB && cleanA === cleanB) return true;
    }
    return false;
  }

  /**
   * 确保指定账户在下拉框选项中存在，若不存在则动态创建并注入
   */
  function ensureAccountOptionInDropdown(selectId, channel, accountValue) {
    if (!selectId || !accountValue) return null;
    const pureId = selectId.replace(/^menu-/, '').replace(/^dropdown-wrap-/, '');
    const normChan = _normChan(channel);

    // 剥离渠道前缀，只保留纯支出账户名（如 '云闪付 · 银行卡[8888]' -> '银行卡[8888]', '微信·钱包' -> '钱包'）
    let cleanAcc = String(accountValue || '').trim();
    if (cleanAcc.includes(' · ')) {
      cleanAcc = cleanAcc.split(' · ')[1].trim();
    } else if (cleanAcc.includes('·')) {
      cleanAcc = cleanAcc.split('·')[1].trim();
    } else if (cleanAcc.includes(' - ')) {
      cleanAcc = cleanAcc.split(' - ')[1].trim();
    }
    cleanAcc = cleanAcc.replace(/^(?:微信|支付宝|云闪付|现金)\s*[·•\-\s]\s*/, '').trim();

    if (!cleanAcc) return null;

    let targetPureId = pureId;
    if (pureId === 'edit-account') targetPureId = 'select-account';
    const menu = document.getElementById('menu-' + targetPureId) || document.getElementById('menu-' + pureId);
    if (!menu) return null;

    // 1. 如果当前渠道下已有同名或等价选项，直接复用
    const exactMatch = menu.querySelector(`.custom-dropdown-option[data-channel="${normChan}"][data-value="${cleanAcc}"]`);
    if (exactMatch) {
      return exactMatch;
    }

    const existing = Array.from(menu.querySelectorAll('.custom-dropdown-option')).find(opt => {
      const c = opt.getAttribute('data-channel');
      const v = opt.getAttribute('data-value');
      return (!c || _normChan(c) === normChan) && (v === cleanAcc || _matchOption(pureId, v, cleanAcc));
    });

    if (existing) {
      return existing;
    }

    // 2. 如果该账户是微信/支付宝/现金内置专属钱包类账户 (钱包/零钱/零钱通/余额/余额宝/花呗/现金钱包)，绝不跨渠道重复创建
    const isBuiltinExclusive = ['钱包', '零钱', '零钱通', '余额', '余额宝', '花呗', '现金', '现金钱包'].includes(cleanAcc);
    if (isBuiltinExclusive) {
      const anyExisting = Array.from(menu.querySelectorAll('.custom-dropdown-option')).find(opt => {
        const v = opt.getAttribute('data-value');
        return v === cleanAcc || _matchOption(pureId, v, cleanAcc);
      });
      if (anyExisting) return anyExisting;
    }

    // 3. 动态创建该选项并插入到菜单中
    const optDiv = document.createElement('div');
    optDiv.className = 'custom-dropdown-option rounded-xl';
    optDiv.tabIndex = 0;
    optDiv.setAttribute('data-channel', normChan);
    optDiv.setAttribute('data-value', cleanAcc);
    const escapedAcc = cleanAcc.replace(/'/g, "\\'");
    optDiv.setAttribute('onclick', `selectCustomDropdownOption('${targetPureId}', '${escapedAcc}', event)`);
    optDiv.setAttribute('onkeydown', `if(event.key==='Enter'||event.key===' '){selectCustomDropdownOption('${targetPureId}', '${escapedAcc}', event);event.preventDefault();}`);

    optDiv.innerHTML = `<span class="truncate">${cleanAcc}</span><span class="opt-check">✓</span>`;

    // 检查当前选定渠道，若与选项渠道一致则显示，否则隐藏
    let channelInputId = 'select-channel';
    if (targetPureId === 'manual-pay-sub') channelInputId = 'manual-pay-channel';
    else if (targetPureId === 'detail-edit-account') channelInputId = 'detail-edit-channel';
    const channelInput = document.getElementById(channelInputId);
    const currentChannel = _normChan(channelInput ? channelInput.value : '');
    if (currentChannel && currentChannel !== normChan) {
      optDiv.style.display = 'none';
    } else {
      optDiv.style.display = '';
    }

    menu.appendChild(optDiv);
    return optDiv;
  }

  /**
   * 实时根据选定渠道过滤账户下拉列表选项的可见性
   */
  function filterAccountDropdownOptions(id) {
    const pureId = (id || '').replace(/^menu-/, '').replace(/^dropdown-wrap-/, '');
    if (pureId !== 'select-account' && pureId !== 'manual-pay-sub' && pureId !== 'detail-edit-account') return;

    let channelInputId = 'select-channel';
    if (pureId === 'manual-pay-sub') channelInputId = 'manual-pay-channel';
    else if (pureId === 'detail-edit-account') channelInputId = 'detail-edit-channel';

    const channelInput = document.getElementById(channelInputId);
    const currentChannel = _normChan(channelInput ? channelInput.value : '');

    let targetPureId = pureId;
    if (pureId === 'edit-account') targetPureId = 'select-account';
    const menu = document.getElementById('menu-' + targetPureId) || document.getElementById('menu-' + pureId);
    if (!menu) return;

    const options = menu.querySelectorAll('.custom-dropdown-option');
    options.forEach(opt => {
      const optChannel = opt.getAttribute('data-channel');
      if (!optChannel || _normChan(optChannel) === currentChannel) {
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

    let cleanVal = value;
    const isAccountDropdown = (id === 'select-account' || id === 'manual-pay-sub' || id === 'detail-edit-account');
    if (isAccountDropdown && typeof value === 'string') {
      if (value.includes(' · ')) {
        cleanVal = value.split(' · ')[1].trim();
      } else if (value.includes('·')) {
        cleanVal = value.split('·')[1].trim();
      } else if (value.includes(' - ')) {
        cleanVal = value.split(' - ')[1].trim();
      }
      cleanVal = cleanVal.replace(/^(?:微信|支付宝|云闪付|现金)\s*[·•\-\s]\s*/, '').trim();
    }

    // 更新各选项高亮与选中状态
    const options = menu.querySelectorAll('.custom-dropdown-option');
    let displayLabel = cleanVal != null ? cleanVal : value;
    let matchedCatIcon = null;
    let matchedValue = null;

    options.forEach(opt => {
      const optVal = opt.getAttribute('data-value');
      const isMatched = _matchOption(id, optVal, cleanVal);

      if (isMatched) {
        opt.classList.add('selected');
        matchedValue = optVal;
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
        const targetCat = matchedCatIcon || cleanVal || value;
        triggerIconEl.setAttribute('data-cat-icon', targetCat);
        if (window.IconRegistry) {
          triggerIconEl.innerHTML = window.IconRegistry.getCategoryIcon(targetCat);
        }
      }
    }

    // 更新底层 Input 值并派发事件
    if (input) {
      const finalVal = (id === 'vlm-provider-select' || !matchedValue) ? cleanVal : matchedValue;
      const valToSet = finalVal != null ? String(finalVal) : '';
      const protoDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
      if (protoDescriptor && protoDescriptor.set) {
        protoDescriptor.set.call(input, valToSet);
      } else {
        input.value = valToSet;
      }
      input.setAttribute('value', valToSet);

      if (id === 'select-channel' && typeof window.onDraftChannelChange === 'function') {
        window.onDraftChannelChange(valToSet);
      }
      if (id === 'manual-pay-channel' && typeof window.onManualChannelChange === 'function') {
        window.onManualChannelChange(valToSet);
      }
      if (id === 'manual-pay-sub' && typeof window.onManualSubChange === 'function') {
        window.onManualSubChange(valToSet);
      }
      if (id === 'detail-edit-channel' && typeof window.onDetailEditChannelChange === 'function') {
        window.onDetailEditChannelChange(valToSet);
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
    const input = document.getElementById(id);
    const menu = document.getElementById('menu-' + id);
    const label = document.getElementById('label-' + id);
    const wrap = document.getElementById('dropdown-wrap-' + id);

    let cleanVal = value;
    const isAccountDropdown = (id === 'select-account' || id === 'manual-pay-sub' || id === 'detail-edit-account');
    if (isAccountDropdown && typeof value === 'string') {
      if (value.includes(' · ')) {
        cleanVal = value.split(' · ')[1].trim();
      } else if (value.includes('·')) {
        cleanVal = value.split('·')[1].trim();
      } else if (value.includes(' - ')) {
        cleanVal = value.split(' - ')[1].trim();
      }
      cleanVal = cleanVal.replace(/^(?:微信|支付宝|云闪付|现金)\s*[·•\-\s]\s*/, '').trim();
    }

    if (!menu) {
      if (input) {
        const valToSet = cleanVal != null ? String(cleanVal) : '';
        const protoDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        if (protoDescriptor && protoDescriptor.set) {
          protoDescriptor.set.call(input, valToSet);
        } else {
          input.value = valToSet;
        }
        input.setAttribute('value', valToSet);
      }
      return;
    }

    let currentChannel = '';
    if (isAccountDropdown) {
      let chanInputId = 'select-channel';
      if (id === 'manual-pay-sub') chanInputId = 'manual-pay-channel';
      else if (id === 'detail-edit-account') chanInputId = 'detail-edit-channel';

      const chanInput = document.getElementById(chanInputId);
      currentChannel = _normChan(chanInput ? chanInput.value : '');
      if (cleanVal) {
        ensureAccountOptionInDropdown(id, currentChannel, cleanVal);
      }
      filterAccountDropdownOptions(id);
    }

    const options = menu.querySelectorAll('.custom-dropdown-option');
    let found = false;
    let displayLabel = cleanVal != null ? cleanVal : value;
    let matchedCatIcon = null;
    let matchedValue = null;

    let bestMatchOpt = null;

    // 优先选中与当前渠道完全匹配的选项
    options.forEach(opt => {
      const optVal = opt.getAttribute('data-value');
      const optChan = opt.getAttribute('data-channel');
      const isMatched = _matchOption(id, optVal, cleanVal);

      if (isMatched) {
        if (currentChannel && _normChan(optChan) === currentChannel) {
          bestMatchOpt = opt;
        } else if (!bestMatchOpt && (!optChan || !currentChannel)) {
          bestMatchOpt = opt;
        }
      }
    });

    if (!bestMatchOpt) {
      options.forEach(opt => {
        const optVal = opt.getAttribute('data-value');
        const isMatched = _matchOption(id, optVal, cleanVal);
        if (isMatched && !bestMatchOpt) {
          bestMatchOpt = opt;
        }
      });
    }

    options.forEach(opt => {
      if (opt === bestMatchOpt) {
        opt.classList.add('selected');
        const span = opt.querySelector('.truncate') || opt.querySelector('.opt-text') || opt.querySelector('span');
        if (span) {
          displayLabel = (span.textContent || span.innerText || '').trim();
        }
        const catIconEl = opt.querySelector('[data-cat-icon]') || (opt.hasAttribute('data-cat-icon') ? opt : null);
        if (catIconEl) {
          matchedCatIcon = catIconEl.getAttribute('data-cat-icon');
        }
        matchedValue = opt.getAttribute('data-value');
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
        const targetCat = matchedCatIcon || cleanVal || value;
        triggerIconEl.setAttribute('data-cat-icon', targetCat);
        if (window.IconRegistry) {
          triggerIconEl.innerHTML = window.IconRegistry.getCategoryIcon(targetCat);
        }
      }
    }

    // 更新底层 Input 的 .value 属性（使用原生属性描述符防止触发自定义 setter 形成递归）
    if (input) {
      const finalVal = (id === 'vlm-provider-select' || !matchedValue) ? cleanVal : matchedValue;
      const valToSet = finalVal != null ? String(finalVal) : '';
      const protoDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
      if (protoDescriptor && protoDescriptor.set) {
        protoDescriptor.set.call(input, valToSet);
      } else {
        input.value = valToSet;
      }
      input.setAttribute('value', valToSet);
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
      'vlm-provider-select',
      'detail-edit-category',
      'detail-edit-channel',
      'detail-edit-account'
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
          if (this.__isSettingValue) return;
          this.__isSettingValue = true;
          try {
            if (descriptor && descriptor.set) {
              descriptor.set.call(this, newVal);
            } else {
              this.setAttribute('value', newVal);
            }
            syncCustomDropdownFromValue(id, newVal);
            const effectiveVal = descriptor ? descriptor.get.call(this) : this.value;
            if (id === 'select-channel' && typeof window.onDraftChannelChange === 'function') {
              window.onDraftChannelChange(effectiveVal);
            }
            if (id === 'manual-pay-channel' && typeof window.onManualChannelChange === 'function') {
              window.onManualChannelChange(effectiveVal);
            }
            if (id === 'detail-edit-channel' && typeof window.onDetailEditChannelChange === 'function') {
              window.onDetailEditChannelChange(effectiveVal);
            }
            if (id === 'vlm-provider-select' && typeof window.onVlmProviderChange === 'function') {
              window.onVlmProviderChange(effectiveVal);
            }
          } finally {
            this.__isSettingValue = false;
          }
        },
        configurable: true
      });

      // 初始化显示标签
      syncCustomDropdownFromValue(id, input.value);
    });

    filterAccountDropdownOptions('select-account');
    filterAccountDropdownOptions('manual-pay-sub');
    filterAccountDropdownOptions('detail-edit-account');

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

    const isCurrentValid = Boolean(curAcc) && visibleOptions.some(opt => {
      const v = opt.getAttribute('data-value');
      return v === curAcc || _matchOption('select-account', v, curAcc);
    });

    if (!isCurrentValid && visibleOptions.length > 0) {
      let defaultAcc = '';
      if (window.CHANNEL_DEFAULT_ACCOUNT && window.CHANNEL_DEFAULT_ACCOUNT[normChan]) {
        defaultAcc = window.CHANNEL_DEFAULT_ACCOUNT[normChan];
      } else if (normChan === '微信') {
        defaultAcc = '钱包';
      } else if (normChan === '支付宝') {
        defaultAcc = '余额';
      }
      const hasDefault = defaultAcc && visibleOptions.find(opt => opt.getAttribute('data-value') === defaultAcc);
      const targetAcc = hasDefault ? defaultAcc : (visibleOptions[0] ? visibleOptions[0].getAttribute('data-value') : defaultAcc);
      if (targetAcc) {
        selectCustomDropdownOption('select-account', targetAcc);
      }
    }
  }

  function onManualChannelChange(channel) {
    const subMenu = document.getElementById('menu-manual-pay-sub');
    if (!subMenu) return;
    const targetChannel = _normChan(channel);
    const options = subMenu.querySelectorAll('.custom-dropdown-option');
    let firstMatch = null;
    options.forEach(opt => {
      const optChannel = opt.getAttribute('data-channel');
      if (!optChannel || _normChan(optChannel) === targetChannel) {
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

  function onDetailEditChannelChange(channel) {
    const normChan = _normChan(channel);
    filterAccountDropdownOptions('detail-edit-account');
    const accMenu = document.getElementById('menu-detail-edit-account');
    if (!accMenu) return;

    const visibleOptions = Array.from(accMenu.querySelectorAll('.custom-dropdown-option')).filter(opt => opt.style.display !== 'none');
    const curAccInput = document.getElementById('detail-edit-account');
    const curAcc = curAccInput ? curAccInput.value : '';

    const isCurrentValid = Boolean(curAcc) && visibleOptions.some(opt => {
      const v = opt.getAttribute('data-value');
      return v === curAcc || _matchOption('detail-edit-account', v, curAcc);
    });

    if (!isCurrentValid && visibleOptions.length > 0) {
      const firstOpt = visibleOptions[0];
      const targetAcc = firstOpt ? (firstOpt.getAttribute('data-value') || '') : '';
      if (targetAcc) {
        selectCustomDropdownOption('detail-edit-account', targetAcc);
      }
      if (curAccInput && targetAcc) {
        const protoDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        if (protoDescriptor && protoDescriptor.set) {
          protoDescriptor.set.call(curAccInput, targetAcc);
        } else {
          curAccInput.value = targetAcc;
        }
        curAccInput.setAttribute('value', targetAcc);
      }
      const label = document.getElementById('label-detail-edit-account');
      if (label && targetAcc) {
        label.textContent = targetAcc;
      }
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
  window.onDetailEditChannelChange = onDetailEditChannelChange;
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
