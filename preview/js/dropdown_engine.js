/**
 * SingWallet 自定义下拉浮层引擎与联动控制器 (Dropdown Engine & Form Linkage)
 * 纯 HTML/CSS 打造无原生 Win32 弹框的安全下拉浮层系统，并包含日期与多级支付渠道联动。
 */

(function (window) {
  'use strict';

  /**
   * 打开指定 ID 的自定义下拉浮层
   */
  function openCustomDropdownId(id) {
    const wrap = document.getElementById('dropdown-wrap-' + id);
    const menu = document.getElementById('menu-' + id);
    const trigger = wrap ? wrap.querySelector('.custom-dropdown-trigger') : null;
    if (!menu) return;

    closeAllCustomDropdowns();
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

    const isOpen = menu.classList.contains('open');
    closeAllCustomDropdowns();

    if (!isOpen) {
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

    const options = menu.querySelectorAll('.custom-dropdown-option');
    let found = false;
    let displayLabel = value;
    let matchedCatIcon = null;

    options.forEach(opt => {
      const optVal = opt.getAttribute('data-value');
      const matchFn = window.isOptionMatch || (window.DomainRegistry && window.DomainRegistry.isOptionMatch);
      const isMatched = matchFn ? matchFn(id, optVal, value) : (optVal === String(value));

      if (isMatched) {
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
    const accMenu = document.getElementById('menu-select-account');
    if (!accMenu) return;
    const options = accMenu.querySelectorAll('.custom-dropdown-option');
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
    const curAccInput = document.getElementById('select-account');
    const curAcc = curAccInput ? curAccInput.value : '';
    const curOpt = accMenu.querySelector(`[data-value="${curAcc}"]`);
    if (!curOpt || curOpt.getAttribute('data-channel') !== channel) {
      if (firstMatch) {
        selectCustomDropdownOption('select-account', firstMatch);
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

})(typeof window !== 'undefined' ? window : this);
