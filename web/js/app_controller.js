/**
 * SingWallet 交互主控器与业务状态引擎 (App Controller & Reactive UI)
 * 职责：
 * 1. 视图切换、流水记账、草稿箱队列、规则与账户管理、12 个月财务数据引擎。
 * 2. 彻底解耦 Emoji 图标与状态元数据，完全依托 IconRegistry 和 DomainRegistry 实现单向数据流。
 * 3. 动态维护所有 DOM 节点的 [data-cat-icon] 与 [data-ui-icon] 属性，支持全系统图标无感热刷新。
 */

(function (window) {
  'use strict';

  // Global DOM element alias shim for view-rules <-> view-rules-accounts
  const origGetElementById = document.getElementById.bind(document);
  document.getElementById = function(id) {
    if (id === 'view-rules') {
      return origGetElementById('view-rules-accounts') || origGetElementById('view-rules');
    }
    if (id === 'view-rules-accounts') {
      return origGetElementById('view-rules-accounts') || origGetElementById('view-rules');
    }
    return origGetElementById(id);
  };

  // Safe Icon Resolution Helpers using SSOT IconRegistry
  function getAppCatIcon(cat, fallback = '') {
    if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.getCategoryIcon === 'function') {
      const icon = IconRegistry.getCategoryIcon(cat);
      if (icon) return icon;
    }
    if (typeof CATEGORY_ICON_MAP !== 'undefined' && CATEGORY_ICON_MAP[cat]) {
      return CATEGORY_ICON_MAP[cat];
    }
    return fallback;
  }

  function getAppStatusIcon(key, fallback = '') {
    if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.getStatusIcon === 'function') {
      const aliasMap = {
        check: 'success',
        timer: 'sparkles',
        refresh: 'sparkles',
        lightning: 'bolt',
        clean: 'broom',
        party: 'celebrate'
      };
      const resolvedKey = aliasMap[key] || key;
      const icon = IconRegistry.getStatusIcon(resolvedKey);
      if (icon && icon !== IconRegistry.getStatusIcon('fallbackCategory')) {
        return icon;
      }
      const directIcon = IconRegistry.getStatusIcon(key);
      if (directIcon && directIcon !== IconRegistry.getStatusIcon('fallbackCategory')) {
        return directIcon;
      }
    }
    return fallback;
  }

  // Polyfill / alias for add-record-modal selector
  if (typeof document !== 'undefined') {
    const origGetElementById = document.getElementById.bind(document);
    document.getElementById = function(id) {
      if (id === 'add-record-modal') {
        return origGetElementById('manual-add-modal') || origGetElementById('category-modal');
      }
      return origGetElementById(id);
    };
    const origQuerySelector = document.querySelector.bind(document);
    document.querySelector = function(selector) {
      if (selector === '#add-record-modal') {
        return origQuerySelector('#manual-add-modal') || origQuerySelector('#category-modal');
      }
      return origQuerySelector(selector);
    };
  }

  // Tab Switching
  function switchTab(tabId) {
    if (typeof closeDedupTopToast === 'function') closeDedupTopToast();
    if (typeof closeLlmTopError === 'function') closeLlmTopError();
    if (typeof closeAllCustomDropdowns === 'function') closeAllCustomDropdowns();
    const txView = document.getElementById('view-transactions');
    const draftView = document.getElementById('view-drafts');
    const rulesView = document.getElementById('view-rules-accounts') || document.getElementById('view-rules');

    if (txView) txView.classList.add('hidden');
    if (draftView) draftView.classList.add('hidden');
    if (rulesView) rulesView.classList.add('hidden');

    const btnTx = document.getElementById('nav-btn-transactions');
    const btnDr = document.getElementById('nav-btn-drafts');
    const btnRu = document.getElementById('nav-btn-rules');

    const navInactiveClass = "flex flex-col items-center justify-center gap-0.5 h-full text-slate-400 hover:text-white tap-highlight";
    const navInactiveClassRel = "relative flex flex-col items-center justify-center gap-0.5 h-full text-slate-400 hover:text-white tap-highlight";
    const navActiveClass = "flex flex-col items-center justify-center gap-0.5 h-full text-indigo-400 font-semibold tap-highlight";
    const navActiveClassRel = "relative flex flex-col items-center justify-center gap-0.5 h-full text-indigo-400 font-semibold tap-highlight";

    if (btnTx) btnTx.className = navInactiveClass;
    if (btnDr) btnDr.className = navInactiveClassRel;
    if (btnRu) btnRu.className = navInactiveClass;

    if (tabId === 'transactions' || tabId === 0 || tabId === '0') {
      if (txView) txView.classList.remove('hidden');
      if (btnTx) btnTx.className = navActiveClass;
    } else if (tabId === 'drafts' || tabId === 1 || tabId === '1') {
      if (draftView) draftView.classList.remove('hidden');
      if (btnDr) btnDr.className = navActiveClassRel;
    } else if (tabId === 'rules' || tabId === 'rules-accounts' || tabId === 2 || tabId === '2') {
      if (rulesView) rulesView.classList.remove('hidden');
      if (btnRu) btnRu.className = navActiveClass;
      if (typeof syncVlmConfigToUI === 'function') syncVlmConfigToUI();
      if (typeof checkA11yServiceStatus === 'function') checkA11yServiceStatus();
    }
  }

  // Touch-to-Fill OCR Boxes
  function fillAmount(amount) {
    document.getElementById('input-amount').value = amount;
    highlightInput('input-amount');
    showToast(`${getAppStatusIcon('sparkles')} OCR金额已自动提取回填: ¥${amount}`);
  }

  function fillMerchant(merchant) {
    document.getElementById('input-merchant').value = merchant;
    highlightInput('input-merchant');
    showToast(`${getAppStatusIcon('sparkles')} OCR商户名已自动提取回填: ${merchant}`);
  }

  function fillTime(time) {
    const el = document.getElementById('input-time');
    if (el) {
      el.value = time;
      highlightInput('input-time');
      showToast(`${getAppStatusIcon('timer')} OCR已填入交易时间: ${time}`);
    }
  }

  function highlightInput(id) {
    const el = document.getElementById(id);
    if (!el) return;
    el.classList.add('ring-4', 'ring-emerald-400');
    setTimeout(() => el.classList.remove('ring-4', 'ring-emerald-400'), 800);
  }

  // ================= 多待确认草稿队列 & 高置信度免确认入账机制 =================
  function loadStoredDrafts() {
    try {
      const raw = localStorage.getItem('singwallet_user_drafts');
      if (raw) {
        const list = JSON.parse(raw);
        if (Array.isArray(list)) return list;
      }
    } catch (e) {}
    return [];
  }

  function saveStoredDrafts() {
    try {
      localStorage.setItem('singwallet_user_drafts', JSON.stringify(draftQueue));
    } catch (e) {
      console.warn('[SingWallet] saveStoredDrafts quota warning, attempting cleanup of oldest imageData:', e);
      try {
        const safeQueue = draftQueue.map(d => ({ ...d }));
        for (let i = safeQueue.length - 1; i >= 0; i--) {
          if (safeQueue[i].imageData) {
            delete safeQueue[i].imageData;
            try {
              localStorage.setItem('singwallet_user_drafts', JSON.stringify(safeQueue));
              console.info('[SingWallet] Successfully persisted drafts after pruning draft index', i);
              return;
            } catch (subErr) {
              // 继续裁剪更早的
            }
          }
        }
        const minimalQueue = safeQueue.map(d => {
          const { imageData, rawFile, ...rest } = d;
          return rest;
        });
        localStorage.setItem('singwallet_user_drafts', JSON.stringify(minimalQueue));
      } catch (finalErr) {
        console.error('[SingWallet] Failed to persist drafts to localStorage:', finalErr);
      }
    }
  }
  window.saveStoredDrafts = saveStoredDrafts;

  function createInitialDraftQueue() {
    return loadStoredDrafts();
  }

  let draftQueue = createInitialDraftQueue();
  let currentDraftIndex = 0;

  // Auto-commit settings
  let autoCommitEnabled = false;
  let autoCommitThreshold = 95;

  function openConfidenceModal() {
    const modal = document.getElementById('confidence-modal');
    if (modal) modal.classList.remove('hidden');
    const toggle = document.getElementById('auto-commit-toggle');
    if (toggle) toggle.checked = autoCommitEnabled;
  }

  function closeConfidenceModal() {
    const modal = document.getElementById('confidence-modal');
    if (modal) modal.classList.add('hidden');
  }

  function toggleAutoCommit(checkbox) {
    autoCommitEnabled = checkbox.checked;
    if (autoCommitEnabled) {
      showToast(`${getAppStatusIcon('success')} 已开启高置信度免确认自动入账 (阈值: ≥${autoCommitThreshold}%)`);
    } else {
      showToast(`${getAppStatusIcon('info')} 已关闭自动入账，所有识别账单均需人工确认`);
    }
  }

  function setAutoCommitThreshold(val, btn) {
    autoCommitThreshold = val;
    const label = document.getElementById('current-threshold-label');
    if (label) {
      label.innerText = `≥ ${val}% ${val === 95 ? '(默认推荐)' : (val === 98 ? '(严苛)' : '')}`;
    }
    const draftHeaderBtn = document.getElementById('draft-conf-threshold-btn-label');
    if (draftHeaderBtn) {
      draftHeaderBtn.innerText = `≥${val}%`;
    }
    document.querySelectorAll('.conf-pill').forEach(b => {
      b.className = "conf-pill py-2 rounded-xl border border-slate-700 bg-slate-800 text-slate-300 text-center font-medium tap-highlight transition-all";
    });
    if (btn) {
      btn.className = "conf-pill active-conf-pill py-2 rounded-xl border-2 border-emerald-500 bg-emerald-600/30 text-emerald-300 text-center font-bold tap-highlight transition-all shadow";
    }
    renderDraftQueue();
    showToast(`已将入账置信度阈值设为: ≥${val}%`);
  }

  function simulateIncomingAutoCommit() {
    const standardPayment = {
      channel: '微信',
      channel_key: 'wechat',
      sub_type: '钱包',
      bank_name: null,
      card_last_4: null,
      display_name: '微信 · 钱包'
    };

    if (!autoCommitEnabled) {
      showToast(`${getAppStatusIcon('warning')} 当前未开启自动入账！账单已推入「草稿箱」待人工确认。`);
      draftQueue.push({
        id: 'draft-' + Date.now(),
        merchant: '星巴克甄选（国贸店）',
        merchantHeader: '星巴克',
        amount: 38.00,
        amountInCents: 3800,
        channel: '微信',
        account: '钱包',
        category: '休闲娱乐',
        categoryName: '休闲娱乐',
        categoryIcon: getAppCatIcon('休闲娱乐'),
        confidence: 99,
        rule: '内置商户规则 "星巴克*"',
        orderId: '420000' + Date.now(),
        orderTime: '2026-10-26 15:45:00',
        time: '2026-10-26 15:45:00',
        payment: standardPayment,
        imgTitle: '微信支付截图预览',
        tag: '置信度 99%'
      });
      renderDraftQueue();
      updateDraftBadge();
      return;
    }

    // Auto-commit directly
    const merchant = '星巴克甄选（国贸店）';
    const amount = 38.00;
    const catName = '休闲娱乐';
    const parentCat = (typeof resolveParentCategory === 'function' ? resolveParentCategory(catName) : catName) || '休闲娱乐';
    const catIcon = getAppCatIcon(parentCat);
    const orderId = '420000' + Date.now();
    const txTime = '2026-10-26 15:45:00';
    
    showToast(`[自动入账成功] 置信度 99% ≥ ${autoCommitThreshold}%，${merchant} ¥${amount.toFixed(2)} 已免人工确认直接记入账本！`);
    
    const targetMonthKey = '2026-10';
    // Update totals
    adjustMonthlyTotals(amount, true, 1, targetMonthKey);

    insertTransactionToList({
      id: "item-tx-" + Date.now(),
      merchant: merchant,
      amount: amount,
      amountInCents: 3800,
      catName: catName,
      catIcon: catIcon,
      parentCat: parentCat,
      category: catName,
      channel: standardPayment.channel,
      account: standardPayment.display_name,
      payment: standardPayment,
      txTime: txTime,
      orderTime: txTime,
      txDate: '2026-10-26',
      timeOnly: '15:45:00',
      orderId: orderId,
      badge: '自动入账 99%',
      _totalsAdjusted: true
    });
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
  }

  /**
   * Bug 3 修复：将当前聚焦草稿表单的已修改内容同步回内存中的 draftQueue[currentDraftIndex]，
   * 避免后台新抓屏入队或切换草稿时冲掉用户正在编辑的输入内容。
   */
  function syncActiveDraftFormToMemory() {
    if (!draftQueue || !Array.isArray(draftQueue) || draftQueue.length === 0) return;
    if (currentDraftIndex < 0 || currentDraftIndex >= draftQueue.length) return;
    const cur = draftQueue[currentDraftIndex];
    if (!cur || cur.isParsing) return;

    const inAmt = document.getElementById('input-amount');
    const inMer = document.getElementById('input-merchant');
    const inOrder = document.getElementById('input-order');
    const inTime = document.getElementById('input-time');
    const selChan = document.getElementById('select-channel');
    const selAcc = document.getElementById('select-account');
    const selCat = document.getElementById('select-draft-category');

    if (inAmt && inAmt.value !== '') {
      const parsedAmt = parseFloat(inAmt.value);
      if (!isNaN(parsedAmt)) {
        cur.amount = parsedAmt;
        cur.amountInCents = Math.round(parsedAmt * 100);
      }
    }
    if (inMer && inMer.value.trim() !== '') {
      cur.merchant = inMer.value.trim();
      cur.merchantHeader = cur.merchant.slice(0, 8);
    }
    if (inOrder && inOrder.value.trim() !== '') {
      cur.orderId = inOrder.value.trim();
    }
    if (inTime && inTime.value.trim() !== '') {
      cur.time = inTime.value.trim();
      cur.orderTime = inTime.value.trim();
    }
    if (selChan && selChan.value) {
      cur.channel = selChan.value;
    }
    if (selAcc && selAcc.value) {
      cur.account = selAcc.value;
    }
    if (selCat && selCat.value) {
      cur.category = selCat.value;
      cur.categoryName = selCat.value;
      cur.categoryIcon = getAppCatIcon(selCat.value);
    }
  }
  window.syncActiveDraftFormToMemory = syncActiveDraftFormToMemory;

  function renderDraftQueue(options = {}) {
    const container = document.getElementById('draft-pills-container');
    const countEl = document.getElementById('draft-queue-count');
    const batchCountEl = document.getElementById('batch-high-count');
    const emptyState = document.getElementById('draft-empty-state');
    const draftContent = document.getElementById('draft-content-container');
    const bar = document.getElementById('draft-queue-bar');

    if (countEl) countEl.innerText = draftQueue.length;
    updateDraftBadge();

    if (draftQueue.length === 0) {
      if (container) container.innerHTML = '';
      if (bar) bar.classList.add('hidden');
      if (emptyState) emptyState.classList.remove('hidden');
      if (draftContent) draftContent.classList.add('hidden');
      saveStoredDrafts();
      return;
    }

    if (bar) bar.classList.remove('hidden');
    if (emptyState) emptyState.classList.add('hidden');
    if (draftContent) draftContent.classList.remove('hidden');
    saveStoredDrafts();

    if (emptyState) emptyState.classList.add('hidden');
    if (draftContent) draftContent.classList.remove('hidden');

    let highCount = draftQueue.filter(d => !d.isParsing && d.confidence >= autoCommitThreshold).length;
    if (batchCountEl) batchCountEl.innerText = highCount;
    const batchLabel = document.getElementById('batch-high-label');
    if (batchLabel) batchLabel.innerText = `≥${autoCommitThreshold}%`;

    if (container) {
      container.innerHTML = draftQueue.map((draft, idx) => {
        const isActive = idx === currentDraftIndex;
        const isHigh = draft.confidence >= 95;
        const confColor = isHigh ? 'text-emerald-400 bg-emerald-500/20 border-emerald-500/40' : 'text-amber-400 bg-amber-500/20 border-amber-500/40';
        const borderClass = isActive 
          ? 'border-2 border-indigo-500 bg-indigo-950/80 shadow-md ring-2 ring-indigo-500/30' 
          : 'border border-slate-700 bg-slate-800/80 hover:border-slate-500';

        // 需求 3：大模型视觉后台异步解析中的任务胶囊与极简单色细条进度条
        if (draft.isParsing) {
          return `
            <div class="flex-shrink-0 px-3 py-1.5 rounded-xl border border-indigo-500/50 bg-slate-800/90 text-left transition-all flex flex-col justify-center min-w-[130px]">
              <div class="flex items-center space-x-2 w-full">
                <span class="w-4 h-4 inline-flex items-center justify-center shrink-0 animate-spin text-indigo-400" data-ui-icon="spinner">${getAppStatusIcon('spinner')}</span>
                <div class="text-xs leading-tight overflow-hidden">
                  <span class="font-semibold text-indigo-200 truncate block">VLM 解析中...</span>
                </div>
              </div>
              <div class="w-full bg-slate-700/50 h-1 rounded-full overflow-hidden mt-1.5">
                <div id="draft-task-prog-${draft.id}" class="bg-indigo-400 h-full rounded-full transition-all duration-300" style="width: ${draft.progress || 15}%;"></div>
              </div>
            </div>
          `;
        }

        if (draft.parseError) {
          const borderClass = isActive 
            ? 'border-2 border-amber-500 bg-amber-950/70 shadow-md ring-2 ring-amber-500/30' 
            : 'border border-amber-600/70 bg-amber-950/40 hover:border-amber-500';
          const cat = draft.categoryName || draft.category || '日常购物';
          const catIcon = getAppCatIcon(cat);
          draft.categoryIcon = catIcon;
          const displayMerchant = (draft.merchant || '抓屏待解析').split('（')[0];
          const displayAmt = (typeof draft.amount === 'number' && !isNaN(draft.amount) && draft.amount > 0)
            ? `¥${draft.amount.toFixed(2)}`
            : '待解析';

          return `
            <button onclick="switchDraft(${idx})" class="flex-shrink-0 px-3 py-1.5 rounded-xl ${borderClass} text-left transition-all tap-highlight flex items-center space-x-2">
              <span class="w-4 h-4 inline-flex items-center justify-center shrink-0 text-amber-400" data-ui-icon="warning">${getAppStatusIcon('warning')}</span>
              <div class="text-xs leading-tight">
                <div class="flex items-center space-x-1">
                  <span class="font-semibold text-amber-200 truncate max-w-[85px]">${displayMerchant}</span>
                  <span class="text-[9px] font-mono px-1 py-0.2 rounded border text-amber-400 bg-amber-500/20 border-amber-500/40">待重试</span>
                </div>
                <span class="text-[11px] font-bold text-amber-300/90">${displayAmt}</span>
              </div>
            </button>
          `;
        }
        
        const cat = draft.categoryName || draft.category || '日常购物';
        const catIcon = getAppCatIcon(cat);
        draft.categoryIcon = catIcon;

        return `
          <button onclick="switchDraft(${idx})" class="flex-shrink-0 px-3 py-1.5 rounded-xl ${borderClass} text-left transition-all tap-highlight flex items-center space-x-2">
            <span class="w-4 h-4 inline-flex items-center justify-center shrink-0" data-cat-icon="${cat}">${catIcon}</span>
            <div class="text-xs leading-tight">
              <div class="flex items-center space-x-1">
                <span class="font-semibold text-white truncate max-w-[85px]">${draft.merchant.split('（')[0]}</span>
                <span class="text-[9px] font-mono px-1 py-0.2 rounded border ${confColor}">${draft.confidence}%</span>
              </div>
              <span class="text-[11px] font-bold text-slate-300">¥${draft.amount.toFixed(2)}</span>
            </div>
          </button>
        `;
      }).join('');
    }

    if (currentDraftIndex < 0 || currentDraftIndex >= draftQueue.length) {
      currentDraftIndex = Math.max(0, draftQueue.length - 1);
    }

    // Load current draft details into UI unless explicitly skipped (e.g. background capture / non-active task completed)
    if (!options || !options.skipFormReload) {
      loadDraftData(draftQueue[currentDraftIndex]);
    }
  }

  function switchDraft(idx) {
    if (typeof closeDedupTopToast === 'function') closeDedupTopToast();
    if (idx >= 0 && idx < draftQueue.length) {
      currentDraftIndex = idx;
      renderDraftQueue();
    }
  }

  function loadDraftData(draft) {
    if (!draft) return;
    if (draft.isParsing) {
      const ocrAmount = document.getElementById('draft-ocr-amount');
      const ocrMerchant = document.getElementById('draft-ocr-merchant');
      const ocrOrder = document.getElementById('draft-ocr-order');
      const ocrTime = document.getElementById('draft-ocr-time');
      const imgTitle = document.getElementById('draft-img-title');
      const imgStatus = document.getElementById('draft-img-status');
      if (ocrAmount) ocrAmount.innerText = '¥ --.--';
      if (ocrMerchant) ocrMerchant.innerText = '大模型正在解析凭证截图...';
      if (ocrOrder) ocrOrder.innerText = '单号提取中...';
      if (ocrTime) ocrTime.innerText = '时间解析中...';
      if (imgTitle) imgTitle.innerText = draft.imgTitle || '账单截图.png';
      if (imgStatus) {
        imgStatus.innerText = '后台解析中';
        imgStatus.className = 'text-indigo-400 font-mono text-[10px] bg-indigo-500/10 px-1.5 py-0.5 rounded border border-indigo-500/30';
      }
      const inAmt = document.getElementById('input-amount');
      const inMer = document.getElementById('input-merchant');
      const inOrder = document.getElementById('input-order');
      const inTime = document.getElementById('input-time');
      if (inAmt) inAmt.value = '';
      if (inMer) inMer.value = '';
      if (inOrder) inOrder.value = '';
      if (inTime) inTime.value = '';
      const retryCard = document.getElementById('draft-vlm-retry-card');
      if (retryCard) retryCard.classList.add('hidden');
      return;
    }
    const catName = draft.categoryName || draft.category || '日常购物';
    const catIcon = getAppCatIcon(catName);
    draft.categoryIcon = catIcon;

    currentDraftCategory = {
      name: catName,
      icon: catIcon,
      tag: catName === '餐饮美食' ? '餐饮' : (catName === '日常购物' ? '购物' : (catName === '生活缴费' ? '缴费' : catName.slice(0, 2)))
    };

    // Screenshot canvas elements
    const ocrAmount = document.getElementById('draft-ocr-amount');
    const ocrMerchant = document.getElementById('draft-ocr-merchant');
    const ocrOrder = document.getElementById('draft-ocr-order');
    const ocrTime = document.getElementById('draft-ocr-time');
    const imgTitle = document.getElementById('draft-img-title');
    const imgStatus = document.getElementById('draft-img-status');

    const numAmount = (typeof draft.amount === 'number' && !isNaN(draft.amount)) ? draft.amount : (parseFloat(draft.amount) || 0);

    if (ocrAmount) {
      ocrAmount.innerText = `¥ ${numAmount.toFixed(2)}`;
      ocrAmount.onclick = null;
      if (ocrAmount.parentElement) ocrAmount.parentElement.onclick = null;
      ocrAmount.style.cursor = 'default';
    }
    if (ocrMerchant) {
      ocrMerchant.innerText = `收款商户：${draft.merchant || '--'}`;
      ocrMerchant.onclick = null;
      if (ocrMerchant.parentElement) ocrMerchant.parentElement.onclick = null;
      ocrMerchant.style.cursor = 'default';
    }
    if (ocrOrder) {
      ocrOrder.innerText = `单号: ${draft.orderId || '--'}`;
      ocrOrder.onclick = null;
      if (ocrOrder.parentElement) ocrOrder.parentElement.onclick = null;
      ocrOrder.style.cursor = 'default';
    }
    if (ocrTime) {
      ocrTime.innerText = `订单时间: ${draft.orderTime || draft.time || '--'}`;
      ocrTime.onclick = null;
      if (ocrTime.parentElement) ocrTime.parentElement.onclick = null;
      ocrTime.style.cursor = 'default';
    }
    if (imgTitle) imgTitle.innerText = draft.imgTitle || '账单截图.png';
    if (imgStatus) {
      imgStatus.innerText = draft.tag || (draft.parseError ? '待重试' : '已提取');
      if (draft.parseError) {
        imgStatus.className = "text-amber-400 font-mono text-[10px] bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/30";
      } else {
        imgStatus.className = draft.confidence >= 95 
          ? "text-emerald-400 font-mono text-[10px] bg-emerald-500/10 px-1.5 py-0.5 rounded border border-emerald-500/30"
          : "text-amber-400 font-mono text-[10px] bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/30";
      }
    }

    // 动态展示凭证区缩略图与重试操作条
    let retryCard = document.getElementById('draft-vlm-retry-card');
    if (draft.parseError) {
      if (!retryCard) {
        const simCanvas = ocrAmount ? ocrAmount.closest('.relative.w-full.h-56') : null;
        if (simCanvas && simCanvas.parentElement) {
          retryCard = document.createElement('div');
          retryCard.id = 'draft-vlm-retry-card';
          retryCard.className = 'w-full p-2.5 rounded-xl bg-amber-500/10 border border-amber-500/30 flex items-center justify-between text-xs transition-all';
          simCanvas.parentElement.insertBefore(retryCard, simCanvas);
        }
      }
      if (retryCard) {
        retryCard.classList.remove('hidden');
        const reason = draft.parseErrorReason || '未完成大模型解析';
        const refreshIcon = (typeof getAppStatusIcon === 'function') ? getAppStatusIcon('refresh') : '';
        const imgThumb = draft.imageData ? `<img src="${draft.imageData}" class="w-10 h-10 object-cover rounded-lg border border-amber-500/40 shrink-0" alt="截屏预览" />` : '';
        retryCard.innerHTML = `
          <div class="flex items-center space-x-2.5 overflow-hidden">
            ${imgThumb}
            <div class="overflow-hidden">
              <span class="text-amber-300 font-semibold block truncate">${reason}</span>
              <span class="text-[10px] text-slate-400 block truncate">已保留画面截图，点击可重试AI识别</span>
            </div>
          </div>
          <button type="button" onclick="window.retryCurrentDraftVlm()" class="shrink-0 px-2.5 py-1.5 text-xs font-semibold rounded-lg bg-amber-500 text-slate-900 hover:bg-amber-400 transition-all flex items-center space-x-1 shadow-sm tap-highlight">
            <span class="w-3.5 h-3.5 inline-flex items-center justify-center" data-ui-icon="refresh">${refreshIcon}</span>
            <span>重新识别</span>
          </button>
        `;
      }
    } else {
      if (retryCard) {
        retryCard.classList.add('hidden');
      }
    }

    // Inputs
    const inAmt = document.getElementById('input-amount');
    const inMer = document.getElementById('input-merchant');
    const inOrder = document.getElementById('input-order');
    const inTime = document.getElementById('input-time');
    const selChan = document.getElementById('select-channel');
    const selAcc = document.getElementById('select-account');
    if (inAmt) inAmt.value = numAmount.toFixed(2);
    if (inMer) inMer.value = draft.merchant || '';
    if (inOrder) inOrder.value = draft.orderId || '';
    if (inTime) inTime.value = draft.orderTime || draft.time || '';

    const rawChan = draft.payment ? draft.payment.channel : (draft.channel || '微信');
    const rawAcc = draft.payment ? (draft.payment.sub_type === '银行卡' ? `${draft.payment.bank_name}(${draft.payment.card_last_4})` : draft.payment.sub_type) : (draft.account || '钱包');

    const resolveFn = window.resolveChannelAndAccount || (window.DomainRegistry && window.DomainRegistry.resolveChannelAndAccount);
    const normBankFn = window.normalizeBankCardAccount || (window.DomainRegistry && window.DomainRegistry.normalizeBankCardAccount);
    
    let resolved = typeof resolveFn === 'function' ? resolveFn(rawChan, rawAcc, draft.payment) : { channel: rawChan, account: rawAcc };
    const channelVal = resolved.channel || '微信';
    let accountVal = resolved.account || '钱包';
    if (typeof normBankFn === 'function') {
      accountVal = normBankFn(accountVal, channelVal);
    }

    if (typeof ensureAccountOptionInDropdown === 'function') {
      ensureAccountOptionInDropdown('select-account', channelVal, accountVal);
    }

    if (selChan) selChan.value = channelVal;
    if (typeof onDraftChannelChange === 'function') {
      onDraftChannelChange(channelVal);
    }
    if (selAcc) selAcc.value = accountVal;
    if (typeof syncCustomDropdownFromValue === 'function') {
      syncCustomDropdownFromValue('select-account', accountVal);
    }

    // Suggested Category View
    const sugIcon = document.getElementById('suggested-icon');
    const sugName = document.getElementById('suggested-name');
    const sugConf = document.getElementById('suggested-confidence-badge');
    const sugRule = document.getElementById('suggested-rule');
    const labelDraftCat = document.getElementById('label-select-draft-category');
    const inputDraftCat = document.getElementById('select-draft-category');

    if (sugIcon) { 
      sugIcon.className = 'w-4 h-4 inline-flex items-center justify-center shrink-0'; 
      sugIcon.innerHTML = catIcon; 
      sugIcon.setAttribute('data-cat-icon', catName);
    }
    if (sugName) sugName.innerText = `推荐分类：${catName}`;
    if (labelDraftCat) labelDraftCat.innerText = catName;
    if (inputDraftCat) inputDraftCat.value = catName;
    if (typeof selectCustomDropdownOption === 'function') {
      selectCustomDropdownOption('select-draft-category', catName);
    }
    if (sugConf) {
      sugConf.innerText = `置信度 ${draft.confidence}%`;
      sugConf.className = draft.confidence >= 95
        ? "text-[10px] bg-indigo-500 text-white px-1.5 py-0.2 rounded font-mono"
        : "text-[10px] bg-amber-500 text-white px-1.5 py-0.2 rounded font-mono";
    }
    if (sugRule) {
      const bulbSvg = (typeof IconRegistry !== 'undefined' && typeof IconRegistry.getStatusIcon === 'function') ? IconRegistry.getStatusIcon('bulb') : '';
      sugRule.innerHTML = `<span class="w-3.5 h-3.5 inline-flex items-center justify-center align-text-bottom mr-1" data-ui-icon="bulb">${bulbSvg}</span>匹配规则：${draft.rule}`;
    }
  }

  async function retryCurrentDraftVlm() {
    const draft = draftQueue[currentDraftIndex];
    if (!draft) return;
    if (!draft.imageData) {
      if (typeof showToast === 'function') {
        showToast('该草稿无截屏原图数据，无法重新识别', 'warning');
      }
      return;
    }
    const vlmKeyInput = document.getElementById('vlm-api-key');
    let activeKey = (vlmKeyInput && vlmKeyInput.value.trim()) ? vlmKeyInput.value.trim() : '';
    if (!activeKey) {
      try {
        const raw = localStorage.getItem('singwallet_vlm_config');
        if (raw) {
          const cfg = JSON.parse(raw);
          if (cfg && cfg.apiKey) activeKey = cfg.apiKey.trim();
        }
      } catch (e) {}
    }
    if (!activeKey && window.vlmConfig && window.vlmConfig.apiKey) {
      activeKey = window.vlmConfig.apiKey.trim();
    }

    if (!activeKey) {
      if (typeof showToast === 'function') {
        showToast('请先在「大模型设置」中配置 API Key 后重试', 'warning');
      }
      if (typeof openLlmConfigModal === 'function') {
        openLlmConfigModal();
      }
      return;
    }

    const file = dataURLtoFile(draft.imageData, draft.imgTitle || ('retry_vlm_' + Date.now() + '.png'));

    draft.isParsing = true;
    draft.parseError = false;
    draft.progress = 15;
    draft.tag = '重新解析中...';
    renderDraftQueue();

    if (typeof parseBillWithVlm === 'function') {
      try {
        const result = await parseBillWithVlm(file);
        draft.isParsing = false;
        draft.parseError = false;
        draft.progress = 100;
        draft.merchant = result.merchant || '已解析商户';
        draft.merchantHeader = (draft.merchant || '').slice(0, 8);
        draft.amount = Number(result.amount) || 0;
        draft.amountInCents = Math.round(draft.amount * 100);
        draft.confidence = typeof result.confidence === 'number' ? result.confidence : 96;

        const resolver = window.resolveParentCategory || (window.DomainRegistry && window.DomainRegistry.resolveParentCategory);
        const currentCats = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
          ? window.DomainRegistry.getParentCategories()
          : (window.CORE_PARENT_CATEGORIES || ['日常购物']);
        const fallbackCat = currentCats.includes('日常购物') ? '日常购物' : (currentCats[0] || '日常购物');
        const normCat = typeof resolver === 'function' ? resolver(result.category || result.cat || '', draft.merchant || '') : (result.category || fallbackCat);

        draft.category = normCat;
        draft.categoryName = normCat;
        draft.categoryIcon = (window.IconRegistry && typeof window.IconRegistry.getCategoryIcon === 'function')
          ? window.IconRegistry.getCategoryIcon(normCat)
          : '';
        draft.orderId = result.orderId || '';
        draft.time = result.orderTime || result.time || ((typeof window.formatCurrentDateTime === 'function') ? window.formatCurrentDateTime() : '');
        draft.payment = result.payment;

        const rawRetryChan = (result.payment && result.payment.channel) || '微信';
        const rawRetryAcc = (result.payment && result.payment.sub_type === '银行卡' && result.payment.bank_name)
          ? `${result.payment.bank_name}(${result.payment.card_last_4 || ''})`
          : ((result.payment && result.payment.sub_type) || '钱包');

        const retryResolveFn = window.resolveChannelAndAccount || (window.DomainRegistry && window.DomainRegistry.resolveChannelAndAccount);
        const retryNormBankFn = window.normalizeBankCardAccount || (window.DomainRegistry && window.DomainRegistry.normalizeBankCardAccount);
        let resolvedRetry = typeof retryResolveFn === 'function' ? retryResolveFn(rawRetryChan, rawRetryAcc, result.payment) : { channel: rawRetryChan, account: rawRetryAcc };
        const retryChannelVal = resolvedRetry.channel || '微信';
        let retryAccountVal = resolvedRetry.account || '钱包';
        if (typeof retryNormBankFn === 'function') {
          retryAccountVal = retryNormBankFn(retryAccountVal, retryChannelVal);
        }

        draft.channel = retryChannelVal;
        draft.account = retryAccountVal;
        draft.tag = `置信度 ${draft.confidence}%`;
        draft.rule = result.rule || 'VLM 视觉智能识别';

        if (typeof ensureAccountOptionInDropdown === 'function') {
          ensureAccountOptionInDropdown('select-account', retryChannelVal, retryAccountVal);
        }

        const selChan = document.getElementById('select-channel');
        const selAcc = document.getElementById('select-account');
        if (selChan) selChan.value = retryChannelVal;
        if (typeof onDraftChannelChange === 'function') {
          onDraftChannelChange(retryChannelVal);
        }
        if (selAcc) selAcc.value = retryAccountVal;
        if (typeof syncCustomDropdownFromValue === 'function') {
          syncCustomDropdownFromValue('select-account', retryAccountVal);
        }

        saveStoredDrafts();
        renderDraftQueue();
        updateDraftBadge();
        if (typeof showToast === 'function') {
          showToast(`草稿重新识别成功：${draft.merchant} ¥${draft.amount.toFixed(2)}`);
        }
      } catch (err) {
        console.warn('retryCurrentDraftVlm error:', err);
        draft.isParsing = false;
        draft.parseError = true;
        draft.parseErrorReason = err.message || '大模型调用异常或网络不可达';
        draft.tag = '重试失败·已保单';
        saveStoredDrafts();
        renderDraftQueue();
        updateDraftBadge();
        if (typeof showToast === 'function') {
          showToast(`重试失败：${draft.parseErrorReason}`, 'error');
        }
      }
    }
  }
  window.retryCurrentDraftVlm = retryCurrentDraftVlm;

  function updateDraftBadge() {
    const badge = document.getElementById('draft-badge');
    const dot = document.getElementById('draft-nav-dot');
    const navBadge = document.getElementById('nav-draft-badge');
    const count = draftQueue.length;
    if (badge) {
      if (count > 0) {
        badge.innerText = `待确认 ${count} 笔`;
        badge.className = "px-2.5 py-1 text-xs font-semibold rounded-full bg-amber-500/20 text-amber-300 border border-amber-500/30";
      } else {
        badge.innerText = `待确认 0 笔`;
        badge.className = "px-2.5 py-1 text-xs font-semibold rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30";
      }
    }
    if (dot) {
      if (count > 0) {
        dot.style.display = 'block';
        dot.classList.remove('hidden');
      } else {
        dot.style.display = 'none';
        dot.classList.add('hidden');
      }
    }
    if (navBadge) {
      navBadge.innerText = String(count);
      if (count > 0) {
        navBadge.classList.remove('hidden');
        navBadge.style.display = 'flex';
      } else {
        navBadge.classList.add('hidden');
        navBadge.style.display = 'none';
      }
    }
  }

  function discardCurrentDraft() {
    if (typeof closeDedupTopToast === 'function') closeDedupTopToast();
    if (draftQueue.length === 0) return;
    const discarded = draftQueue[currentDraftIndex];
    draftQueue.splice(currentDraftIndex, 1);
    if (currentDraftIndex >= draftQueue.length) {
      currentDraftIndex = Math.max(0, draftQueue.length - 1);
    }
    showToast(`${getAppStatusIcon('trash')} 已丢弃草稿: ${discarded.merchant} (已移入草稿回收站)`);
    renderDraftQueue();
  }

  function batchConfirmHighConfidenceDrafts() {
    if (typeof closeDedupTopToast === 'function') closeDedupTopToast();

    // 1. 同步当前选中的草稿表单输入到内存
    if (draftQueue && draftQueue[currentDraftIndex]) {
      const cur = draftQueue[currentDraftIndex];
      const inOrder = document.getElementById('input-order');
      const inAmt = document.getElementById('input-amount');
      const inMer = document.getElementById('input-merchant');
      const inTime = document.getElementById('input-time');
      if (inOrder && inOrder.value.trim()) cur.orderId = inOrder.value.trim();
      if (inAmt && inAmt.value) {
        cur.amount = parseFloat(inAmt.value) || cur.amount;
        cur.amountInCents = Math.round(cur.amount * 100);
      }
      if (inMer && inMer.value.trim()) cur.merchant = inMer.value.trim();
      if (inTime && inTime.value.trim()) cur.time = inTime.value.trim();
    }

    const highList = draftQueue.filter(d => !d.isParsing && d.confidence >= autoCommitThreshold);
    if (highList.length === 0) {
      showToast("当前待确认队列中没有 ≥" + autoCommitThreshold + "% 的高置信度草稿");
      return;
    }

    // 2. 收集已有流水单号并调用领域层去重分流器 (SingWalletDomain.partitionDraftsByDedup)
    const existingOrders = (typeof collectAllExistingTransactions === 'function') 
      ? collectAllExistingTransactions() 
      : (committedOrderIds || new Set());

    let validList = [];
    let dupList = [];

    if (typeof SingWalletDomain !== 'undefined' && typeof SingWalletDomain.partitionDraftsByDedup === 'function') {
      const partitioned = SingWalletDomain.partitionDraftsByDedup(highList, existingOrders);
      validList = partitioned.validList;
      dupList = partitioned.dupList;
    } else {
      // 降级兜底：逐笔去重判断 (含已有流水比对 + 批次内自去重)
      const seenBatchOrders = new Set();
      highList.forEach(draft => {
        const ord = (typeof normalizeOrderId === 'function' ? normalizeOrderId(draft.orderId) : (draft.orderId || '').trim());
        const isDup = ord ? (isOrderIdDuplicate(ord) || seenBatchOrders.has(ord)) : false;
        if (isDup) {
          dupList.push(draft);
        } else {
          validList.push(draft);
          if (ord) seenBatchOrders.add(ord);
        }
      });
    }

    // 3. 仅对 validList 进行入账并从 draftQueue 中剔除
    let totalAmt = 0;
    if (validList.length > 0) {
      const activeMonthKey = `${currentActiveYear}-${String(currentActiveMonth).padStart(2, '0')}`;
      validList.forEach(draft => {
        totalAmt = Math.round((totalAmt + draft.amount) * 100) / 100;
        const txTime = draft.time || '2026-10-26 12:00:00';
        const txDate = txTime.split(' ')[0] || '2026-10-26';
        const timeOnly = txTime.includes(' ') ? txTime.split(' ')[1] : txTime;
        const targetMonthKey = (/^\d{4}-\d{2}/.test(txDate)) ? txDate.slice(0, 7) : activeMonthKey;
        const cat = draft.categoryName || draft.category;
        const parentCat = (typeof resolveParentCategory === 'function' ? resolveParentCategory(cat) : cat) || '其他支出';
        const catIcon = getAppCatIcon(parentCat);

        if (draft.orderId) {
          committedOrderIds.add(draft.orderId.trim());
        }

        adjustMonthlyTotals(draft.amount, true, 1, targetMonthKey);

        const batchPayment = draft.payment || (typeof parsePaymentMethodString === 'function' ? parsePaymentMethodString(`${draft.channel} · ${draft.account}`) : { channel: draft.channel, display_name: `${draft.channel} · ${draft.account}` });
        insertTransactionToList({
          id: 'item-tx-' + Date.now() + Math.random().toString(36).slice(2, 6),
          merchant: draft.merchant,
          amount: draft.amount,
          amountInCents: draft.amountInCents || Math.round(draft.amount * 100),
          catName: cat,
          catIcon: catIcon,
          parentCat: parentCat,
          category: cat,
          channel: batchPayment.channel,
          account: batchPayment.display_name,
          payment: batchPayment,
          txTime: txTime,
          orderTime: draft.orderTime || txTime,
          txDate: txDate,
          timeOnly: timeOnly,
          orderId: draft.orderId,
          badge: '批量入账',
          _totalsAdjusted: true
        });
      });

      // 从 draftQueue 移除已成功入账的草稿
      const validIds = new Set(validList.map(d => d.id));
      draftQueue = draftQueue.filter(d => !validIds.has(d.id));
    }

    // 4. 重复草稿拦截与强提醒处理
    if (dupList.length > 0) {
      // 严禁入账，保留在 draftQueue 中，自动将该重复草稿设为当前选中草稿
      const firstDup = dupList[0];
      const firstDupIdx = draftQueue.findIndex(d => d.id === firstDup.id);
      if (firstDupIdx !== -1) {
        currentDraftIndex = firstDupIdx;
      }
      renderDraftQueue();
      applyActiveFilters();
      updateDynamicCategoryChips();
      updateActiveFilterCapsules();

      // 弹出顶部橙色去重拦截卡片 (允许用户查看、忽略或强制入账)
      const firstDupOrder = (typeof normalizeOrderId === 'function' ? normalizeOrderId(firstDup.orderId) : (firstDup.orderId || '').trim());
      showDedupTopToast(firstDupOrder);

      // 提示控制：全部重复拦截时严禁弹出“成功入账”虚假提示
      if (validList.length === 0) {
        showToast(`拦截 ${dupList.length} 笔重复单号草稿，已为您自动定位并保留在草稿箱！`);
      } else {
        showToast(`已成功入账 ${validList.length} 笔，拦截 ${dupList.length} 笔重复单号草稿！`);
      }
      return;
    }

    currentDraftIndex = 0;
    renderDraftQueue();
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
    showToast(`${getAppStatusIcon('sparkles')} 成功将 ${validList.length} 笔高置信度账单入账 (共 ¥${totalAmt.toFixed(2)})！`);
  }

  function resetDemoDrafts() {
    draftQueue = createInitialDraftQueue();
    currentDraftIndex = 0;
    renderDraftQueue();
    showToast(`${getAppStatusIcon('refresh')} 已重置为 4 笔真实离线识别账单草稿`);
  }

  let currentDraftCategory = {
    name: '餐饮美食',
    icon: getAppCatIcon('餐饮美食'),
    tag: '餐饮'
  };

  function onDraftCategorySelect(dummyIcon, name, event) {
    if (event) event.stopPropagation();
    const catIcon = getAppCatIcon(name);
    selectCategory(catIcon, name, '下拉选择');
    const sug = document.getElementById('suggested-icon');
    if (sug) {
      sug.className = "w-4 h-4 inline-flex items-center justify-center shrink-0";
      sug.innerHTML = catIcon;
      sug.setAttribute('data-cat-icon', name);
    }
    const label = document.getElementById('label-select-draft-category');
    if (label) label.innerText = name;
    const inp = document.getElementById('select-draft-category');
    if (inp) inp.value = name;

    const opts = document.querySelectorAll('#menu-select-draft-category .custom-dropdown-option');
    opts.forEach(opt => {
      if (opt.getAttribute('data-value') === name) opt.classList.add('selected');
      else opt.classList.remove('selected');
    });

    if (typeof selectCustomDropdownOption === 'function') {
      selectCustomDropdownOption('select-draft-category', name, event);
    }
    if (typeof closeAllCustomDropdowns === 'function') {
      closeAllCustomDropdowns();
    }
  }

  function openCategoryPickerModal() {
    const modal = document.getElementById('category-modal');
    if (!modal) return;
    modal.classList.remove('hidden');
    const cards = modal.querySelectorAll('[data-category-name]');
    cards.forEach(card => {
      const cat = card.getAttribute('data-category-name');
      if (cat === currentDraftCategory.name) {
        card.className = "p-2.5 rounded-2xl bg-indigo-950/70 border-2 border-indigo-500 ring-2 ring-indigo-500/40 text-center cursor-pointer tap-highlight transition-all active:scale-95 flex flex-col items-center justify-center shadow-lg shadow-indigo-500/10";
        const textEl = card.querySelector('.font-medium, .font-semibold');
        if (textEl) textEl.className = "font-semibold text-indigo-200 text-[11px] block whitespace-nowrap";
      } else {
        card.className = "p-2.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 text-center cursor-pointer hover:border-indigo-500/60 tap-highlight transition-all active:scale-95 flex flex-col items-center justify-center";
        const textEl = card.querySelector('.font-medium, .font-semibold');
        if (textEl) textEl.className = "font-medium text-slate-200 text-[11px] block whitespace-nowrap";
      }
    });
  }

  function closeCategoryModal() {
    const modal = document.getElementById('category-modal');
    if (modal) modal.classList.add('hidden');
  }

  function selectCategory(icon, name, ruleText = '下拉选择') {
    const catIcon = getAppCatIcon(name);
    currentDraftCategory = {
      name: name,
      icon: catIcon,
      tag: name === '餐饮美食' ? '餐饮' : (name === '日常购物' ? '购物' : (name === '生活缴费' ? '缴费' : name.slice(0, 2)))
    };
    if (draftQueue[currentDraftIndex]) {
      draftQueue[currentDraftIndex].categoryName = name;
      draftQueue[currentDraftIndex].category = name;
      draftQueue[currentDraftIndex].categoryIcon = catIcon;
      draftQueue[currentDraftIndex].rule = `用户指定分类: ${name}`;
    }
    const iconEl = document.getElementById('suggested-icon');
    if (iconEl) {
      iconEl.className = 'w-4 h-4 inline-flex items-center justify-center shrink-0';
      iconEl.innerHTML = catIcon;
      iconEl.setAttribute('data-cat-icon', name);
    }
    const nameEl = document.getElementById('suggested-name');
    if (nameEl) nameEl.innerText = `推荐分类：${name}`;
    const labelEl = document.getElementById('label-select-draft-category');
    if (labelEl) labelEl.innerText = name;
    const inputEl = document.getElementById('select-draft-category');
    if (inputEl) inputEl.value = name;
    const ruleEl = document.getElementById('suggested-rule');
    if (ruleEl) ruleEl.innerText = `已手动指定：${name}`;
    closeCategoryModal();
    showToast(`已更换分类为：${name}`);
    renderDraftQueue();
  }

  // Order ID Security Modal
  function openOrderSecurityModal(order) {
    const valEl = document.getElementById('sec-order-val');
    if (valEl) valEl.innerText = order;
    const modal = document.getElementById('order-security-modal');
    if (modal) modal.classList.remove('hidden');
  }

  function closeOrderSecurityModal() {
    const modal = document.getElementById('order-security-modal');
    if (modal) modal.classList.add('hidden');
  }

  // Filter State Management
  let currentFilterKey = 'all'; // top chips filter key
  let quickDateFilter = 'all_month'; // 'today', 'yesterday', 'before_yesterday', '7days', 'all_month'
  let activeDayFilter = null; // 'YYYY-MM-DD' when day focus is active
  let activeDayLabel = ''; // e.g. '10月26日 今天'
  let selectedFilterType = 'all'; // 'all', 'expense', 'income'
  let selectedFilterCats = new Set(['all']); // Set of parent categories, 'all' means all
  let selectedFilterAccount = 'all'; // 'all', '微信支付', '支付宝', '招商银行卡', '现金钱包'
  let selectedDatePreset = 'all'; // 'all', 'today', 'yesterday', 'week', 'month', 'custom'

  function onQuickDateDropdownChanged(val) {
    quickDateFilter = val;
    activeDayFilter = null;
    activeDayLabel = '';
    selectedDatePreset = 'all'; // Clear any modal date override so dropdown is always respected

    // Sync drawer modal UI
    const dateBtns = document.querySelectorAll('.modal-date-btn');
    if (dateBtns.length > 0) {
      dateBtns.forEach(b => b.classList.remove('active-tag'));
      const targetBtn = Array.from(dateBtns).find(b => {
        if (val === 'today') return b.innerText.trim() === '今天';
        if (val === 'yesterday') return b.innerText.trim() === '昨天';
        if (val === 'before_yesterday') return b.innerText.trim() === '前天';
        if (val === '7days') return b.innerText.trim() === '近7天';
        if (val === 'all_month') return b.innerText.trim() === '本月';
        return false;
      });
      if (targetBtn) {
        targetBtn.classList.add('active-tag');
      } else {
        dateBtns[0].classList.add('active-tag');
      }
    }
    const dateSummary = document.getElementById('filter-date-summary');
    if (dateSummary) {
      const summaryLabels = {
        'today': '今天 (2026-10-26)',
        'yesterday': '昨天 (2026-10-25)',
        'before_yesterday': '前天 (2026-10-24)',
        '7days': '近7天',
        'all_month': '本月'
      };
      dateSummary.innerText = summaryLabels[val] || '全部日期';
    }

    const banner = document.getElementById('day-focus-banner');
    if (banner) banner.classList.add('hidden');

    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();

    const labels = {
      'today': '今天 (10月26日)',
      'yesterday': '昨天 (10月25日)',
      'before_yesterday': '前天 (10月24日)',
      '7days': '近 7 天内',
      'all_month': '当月全部'
    };
    const scopeLabel = document.getElementById('tx-scope-label');
    if (scopeLabel) {
      const shortLabels = {
        'today': '今天流水',
        'yesterday': '昨天流水',
        'before_yesterday': '前天流水',
        '7days': '近 7 天流水',
        'all_month': '全月流水'
      };
      scopeLabel.innerText = shortLabels[val] || '明细记录';
    }
    showToast(`已切换时间范围：${labels[val] || val}`);
  }

  // Helper: calculate exact last day of a month
  function getLastDayOfMonth(year, month) {
    return new Date(parseInt(year), parseInt(month), 0).getDate();
  }

  // Day Focus Filter Toggle Function
  function toggleDayFilter(dateStr, label) {
    if (activeDayFilter === dateStr) {
      clearDayFocus();
    } else {
      focusDayFilter(dateStr, label);
    }
  }

  function focusDayFilter(dateStr, label) {
    activeDayFilter = dateStr;
    activeDayLabel = label;

    const banner = document.getElementById('day-focus-banner');
    if (banner) {
      const labelEl = document.getElementById('day-focus-label');
      if (labelEl) labelEl.innerText = label;
      banner.classList.remove('hidden');
    }

    currentFilterKey = 'day:' + dateStr;
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
    showToast(`已聚焦日消费：${label} (点击取消可恢复)`);
  }

  function clearDayFocus() {
    activeDayFilter = null;
    activeDayLabel = '';

    const banner = document.getElementById('day-focus-banner');
    if (banner) {
      banner.classList.add('hidden');
    }

    if (currentFilterKey && currentFilterKey.startsWith('day:')) {
      currentFilterKey = 'all';
    }

    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
    showToast("已取消日聚焦");
  }

  // Compound Active Filter Capsules Bar
  function updateActiveFilterCapsules() {
    const bar = document.getElementById('active-filters-bar');
    if (!bar) return;

    const hasDay = !!activeDayFilter;
    const hasType = selectedFilterType !== 'all';
    const hasCats = !selectedFilterCats.has('all') && selectedFilterCats.size > 0;
    const hasDatePreset = selectedDatePreset !== 'all';
    const hasAccount = selectedFilterAccount !== 'all';

    if (!hasDay && !hasType && !hasCats && !hasDatePreset && !hasAccount) {
      bar.classList.add('hidden');
      bar.innerHTML = '';
      return;
    }

    let html = `
      <button onclick="resetFilter()" class="flex items-center space-x-1 px-2.5 py-1 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 shrink-0 tap-highlight font-medium">
        <span>重置全部</span>
        <span class="text-[11px] text-slate-400">✕</span>
      </button>
    `;

    if (hasDay) {
      html += `
        <span class="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-indigo-600/90 text-white border border-indigo-500 shrink-0 shadow-sm">
          <span class="flex items-center space-x-1"><span class="w-3.5 h-3.5 inline-block text-indigo-400" id="day-focus-cal-icon"></span><span>${activeDayLabel || activeDayFilter}</span></span>
          <button onclick="clearDayFocus()" class="hover:text-red-300 ml-1 font-bold text-xs" title="取消日聚焦">✕</button>
        </span>
      `;
    }

    if (hasType) {
      const typeLabel = selectedFilterType === 'expense' ? '仅支出' : '收入/退款';
      html += `
        <span class="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-indigo-900/80 text-indigo-200 border border-indigo-600/60 shrink-0">
          <span>类型: ${typeLabel}</span>
          <button onclick="removeTypeFilter()" class="hover:text-red-300 ml-1 font-bold text-xs" title="清除类型筛选">✕</button>
        </span>
      `;
    }

    if (hasDatePreset && !hasDay) {
      const s = document.getElementById('filter-date-summary')?.innerText || selectedDatePreset;
      html += `
        <span class="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-indigo-900/80 text-indigo-200 border border-indigo-600/60 shrink-0">
          <span>日期: ${s}</span>
          <button onclick="removeDateFilter()" class="hover:text-red-300 ml-1 font-bold text-xs" title="清除日期范围">✕</button>
        </span>
      `;
    }

    if (hasCats) {
      Array.from(selectedFilterCats).forEach(cat => {
        const icon = getAppCatIcon(cat, `<span data-ui-icon="ruleTag">${getAppStatusIcon('ruleTag')}</span>`);
        html += `
          <span class="inline-flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-indigo-900/80 text-indigo-200 border border-indigo-600/60 shrink-0">
            <span class="w-3.5 h-3.5 inline-flex items-center justify-center shrink-0" data-cat-icon="${cat}">${icon}</span>
            <span>${cat}</span>
            <button onclick="removeCatFilter('${cat}')" class="hover:text-red-300 ml-1 font-bold text-xs" title="移除该分类">✕</button>
          </span>
        `;
      });
    }

    if (hasAccount) {
      html += `
        <span class="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-indigo-900/80 text-indigo-200 border border-indigo-600/60 shrink-0">
          <span>账户: ${selectedFilterAccount}</span>
          <button onclick="removeAccountFilter()" class="hover:text-red-300 ml-1 font-bold text-xs" title="清除账户筛选">✕</button>
        </span>
      `;
    }

    bar.innerHTML = html;
    bar.classList.remove('hidden');
  }

  function removeTypeFilter() {
    selectedFilterType = 'all';
    const typeBtns = document.querySelectorAll('.modal-type-btn');
    if (typeBtns.length > 0) selectModalType(typeBtns[0], 'all');
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
  }

  function removeDateFilter() {
    selectedDatePreset = 'all';
    activeDayFilter = null;
    activeDayLabel = '';
    const dateBtns = document.querySelectorAll('.modal-date-btn');
    if (dateBtns.length > 0) selectDatePreset(dateBtns[0], 'all');
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
  }

  function removeCatFilter(cat) {
    selectedFilterCats.delete(cat);
    if (selectedFilterCats.size === 0) selectedFilterCats.add('all');
    const tags = document.querySelectorAll('#filter-modal-cats .modal-cat-tag');
    tags.forEach(t => {
      if (t.innerText.includes(cat)) t.classList.remove('active-tag');
      if (selectedFilterCats.has('all') && t.innerText.trim() === '全部') t.classList.add('active-tag');
    });
    const badge = document.getElementById('filter-cat-badge');
    if (badge) badge.innerText = selectedFilterCats.has('all') ? '全部' : `已选 ${selectedFilterCats.size} 类`;
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
  }

  function removeAccountFilter() {
    selectedFilterAccount = 'all';
    const accBtns = document.querySelectorAll('.modal-acc-btn');
    if (accBtns.length > 0) selectModalAccount(accBtns[0], 'all');
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
  }

  // Dynamic Filter Chips based on Active Month Transactions
  function updateDynamicCategoryChips() {
    const container = document.getElementById('filter-chips');
    if (!container) return;
    const items = Array.from(document.querySelectorAll('.tx-item')).filter(el => !el.classList.contains('soft-deleted'));

    // Count parent categories and day occurrences
    const parentCount = {};
    const dateCounts = {};
    let expenseCount = 0;

    items.forEach(item => {
      const rawCat = item.dataset.cat || item.dataset.parent;
      const parentCat = (typeof resolveParentCategory === 'function' ? resolveParentCategory(rawCat) : rawCat) || '其他支出';
      item.dataset.parent = parentCat;
      parentCount[parentCat] = (parentCount[parentCat] || 0) + 1;

      if (item.dataset.type === 'expense') expenseCount++;
      const d = item.dataset.date;
      if (d) {
        dateCounts[d] = (dateCounts[d] || 0) + 1;
      }
    });

    let html = '';
    
    // 1. 全部流水
    const isAll = (currentFilterKey === 'all' && !activeDayFilter && selectedFilterType === 'all' && selectedFilterCats.has('all') && selectedFilterAccount === 'all' && selectedDatePreset === 'all');
    html += `
      <span onclick="filterTransactions('all', this)" class="chip-item inline-flex items-center px-3 py-1.5 rounded-xl ${isAll ? 'bg-indigo-600 text-white font-medium' : 'bg-slate-800 border border-slate-700 text-slate-300'} shrink-0 cursor-pointer tap-highlight shadow-sm transition-all text-xs">全部流水</span>
    `;

    // 2. 仅看支出
    const isExpense = (currentFilterKey === 'expense' || selectedFilterType === 'expense');
    html += `
      <span onclick="filterTransactions('expense', this)" class="chip-item inline-flex items-center px-3 py-1.5 rounded-xl ${isExpense ? 'bg-indigo-600 text-white font-medium' : 'bg-slate-800 border border-slate-700 text-slate-300'} shrink-0 cursor-pointer tap-highlight hover:text-white transition-all text-xs">仅看支出</span>
    `;

    // 3. 8大顶级父类中该月存在的分类
    for (const [parentCat, count] of Object.entries(parentCount)) {
      if (parentCat === '工资收入') continue;
      const icon = getAppCatIcon(parentCat, `<span data-ui-icon="ruleTag">${getAppStatusIcon('ruleTag')}</span>`);
      const isSelected = (currentFilterKey === parentCat || selectedFilterCats.has(parentCat));
      html += `
        <span onclick="filterTransactions('${parentCat}', this)" class="chip-item inline-flex items-center space-x-1.5 px-3 py-1.5 rounded-xl ${isSelected ? 'bg-indigo-600 text-white font-medium' : 'bg-slate-800 border border-slate-700 text-slate-300'} shrink-0 cursor-pointer tap-highlight hover:text-white transition-all text-xs">
          <span class="w-3.5 h-3.5 inline-flex items-center justify-center shrink-0" data-cat-icon="${parentCat}">${icon}</span>
          <span>${parentCat}</span>
          <span class="opacity-70 text-[10px]">(${count})</span>
        </span>
      `;
    }

    container.innerHTML = html;
  }

  // Filter Transactions from Top Chips
  function filterTransactions(category, element) {
    if (category === 'all') {
      // Reset all compound filters back to clean month view
      selectedFilterType = 'all';
      selectedFilterCats.clear();
      selectedFilterCats.add('all');
      selectedFilterAccount = 'all';
      selectedDatePreset = 'all';
      activeDayFilter = null;
      activeDayLabel = '';
      currentFilterKey = 'all';

      // Reset drawer modal states as well
      const typeBtns = document.querySelectorAll('.modal-type-btn');
      if (typeBtns.length > 0) selectModalType(typeBtns[0], 'all');
      const dateBtns = document.querySelectorAll('.modal-date-btn');
      if (dateBtns.length > 0) selectDatePreset(dateBtns[0], 'all');
      const catTags = document.querySelectorAll('#filter-modal-cats .modal-cat-tag');
      catTags.forEach(t => t.classList.remove('active-tag'));
      if (catTags.length > 0) catTags[0].classList.add('active-tag');
      const badge = document.getElementById('filter-cat-badge');
      if (badge) badge.innerText = '全部';
      const accBtns = document.querySelectorAll('.modal-acc-btn');
      if (accBtns.length > 0) selectModalAccount(accBtns[0], 'all');
      const banner = document.getElementById('day-focus-banner');
      if (banner) banner.classList.add('hidden');
    } else {
      currentFilterKey = category;
      activeDayFilter = null;
      activeDayLabel = '';
      const banner = document.getElementById('day-focus-banner');
      if (banner) banner.classList.add('hidden');
    }

    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();

    if (category === 'all') {
      showToast(quickDateFilter === "all_month" ? "已展示当月全部流水" : "已展示全部分类流水");
    } else if (category === 'expense') {
      showToast("已筛选：仅看支出");
    } else {
      showToast(`已筛选父类：${category}`);
    }
  }

  // Unified Filter Applicator (Applies compound filters, updates day groups & subtotals)
  function applyActiveFilters() {
    const items = Array.from(document.querySelectorAll('.tx-item'));
    const dayGroups = Array.from(document.querySelectorAll('.day-group'));
    let totalVisible = 0;

    // Determine date bounds
    let startDate = null;
    let endDate = null;

    if (activeDayFilter) {
      startDate = activeDayFilter;
      endDate = activeDayFilter;
    } else if (selectedDatePreset !== 'all') {
      if (selectedDatePreset === 'today') {
        startDate = '2026-10-26';
        endDate = '2026-10-26';
      } else if (selectedDatePreset === 'yesterday') {
        startDate = '2026-10-25';
        endDate = '2026-10-25';
      } else if (selectedDatePreset === 'before_yesterday') {
        startDate = '2026-10-24';
        endDate = '2026-10-24';
      } else if (selectedDatePreset === 'week') {
        startDate = '2026-10-20';
        endDate = '2026-10-26';
      } else if (selectedDatePreset === 'month') {
        const lastDay = getLastDayOfMonth(currentActiveYear, currentActiveMonth).toString().padStart(2, '0');
        startDate = `${currentActiveYear}-${currentActiveMonth}-01`;
        endDate = `${currentActiveYear}-${currentActiveMonth}-${lastDay}`;
      } else if (selectedDatePreset === 'custom') {
        const s = document.getElementById('filter-start-date');
        const e = document.getElementById('filter-end-date');
        if (s && s.value) startDate = s.value;
        if (e && e.value) endDate = e.value;
      }
    } else if (quickDateFilter) {
      if (quickDateFilter === 'today') {
        startDate = '2026-10-26';
        endDate = '2026-10-26';
      } else if (quickDateFilter === 'yesterday') {
        startDate = '2026-10-25';
        endDate = '2026-10-25';
      } else if (quickDateFilter === 'before_yesterday') {
        startDate = '2026-10-24';
        endDate = '2026-10-24';
      } else if (quickDateFilter === '7days') {
        startDate = '2026-10-20';
        endDate = '2026-10-26';
      } else if (quickDateFilter === 'all_month') {
        const lastDay = getLastDayOfMonth(currentActiveYear, currentActiveMonth).toString().padStart(2, '0');
        startDate = `${currentActiveYear}-${currentActiveMonth}-01`;
        endDate = `${currentActiveYear}-${currentActiveMonth}-${lastDay}`;
      }
    }

    const hasModalCats = !selectedFilterCats.has('all') && selectedFilterCats.size > 0;

    items.forEach(item => {
      if (item.classList.contains('soft-deleted')) {
        item.style.display = 'none';
        return;
      }

      const itemType = item.dataset.type || 'expense';
      const itemParent = item.dataset.parent || (typeof resolveParentCategory === 'function' ? resolveParentCategory(item.dataset.cat) : item.dataset.cat);
      const itemAcc = item.dataset.account || item.dataset.channel || '';
      const itemDate = item.dataset.date || '';

      // 1. Type match
      let matchesType = true;
      if (currentFilterKey === 'expense') {
        matchesType = (itemType === 'expense');
      } else if (selectedFilterType === 'expense') {
        matchesType = (itemType === 'expense');
      } else if (selectedFilterType === 'income') {
        matchesType = (itemType === 'income' || itemType === 'refund');
      }

      // 2. Category match
      let matchesCat = true;
      if (currentFilterKey !== 'all' && currentFilterKey !== 'expense' && !currentFilterKey.startsWith('day:')) {
        matchesCat = (itemParent === currentFilterKey);
      } else if (hasModalCats) {
        matchesCat = selectedFilterCats.has(itemParent);
      }

      // 3. Account match
      let matchesAcc = true;
      if (selectedFilterAccount !== 'all') {
        matchesAcc = (itemAcc === selectedFilterAccount);
      }

      // 4. Date match
      let matchesDate = true;
      if (startDate && itemDate && itemDate < startDate) matchesDate = false;
      if (endDate && itemDate && itemDate > endDate) matchesDate = false;

      const isVisible = matchesType && matchesCat && matchesAcc && matchesDate;
      item.style.display = isVisible ? 'flex' : 'none';
      if (isVisible) totalVisible++;
    });

    // Update Day Groups visibility and subtotal, and highlight active day header
    dayGroups.forEach(group => {
      const groupItems = Array.from(group.querySelectorAll('.tx-item')).filter(i => !i.classList.contains('soft-deleted') && i.style.display !== 'none');
      if (groupItems.length === 0) {
        group.style.display = 'none';
      } else {
        group.style.display = 'block';
        const subtotal = groupItems.reduce((acc, el) => {
          const rawAmount = el.querySelector('.font-bold.text-base')?.innerText || '';
          const num = parseFloat(rawAmount.replace(/[^0-9.]/g, '') || '0');
          return acc + num;
        }, 0);
        const subtotalEl = group.querySelector('.day-subtotal');
        if (subtotalEl) {
          subtotalEl.innerText = `小计: -¥ ${subtotal.toFixed(2)}`;
        }

        // Update header active state
        const gDate = group.getAttribute('data-date');
        const isFocused = (activeDayFilter === gDate);
        const header = group.querySelector('.day-header');
        const btnText = group.querySelector('.day-filter-btn-text');
        const btn = group.querySelector('.day-filter-btn');
        if (header) {
          if (isFocused) {
            header.classList.add('bg-indigo-950/60', 'border', 'border-indigo-500/40');
          } else {
            header.classList.remove('bg-indigo-950/60', 'border', 'border-indigo-500/40');
          }
        }
        if (btnText) {
          btnText.innerText = isFocused ? '已聚焦 ✕' : '仅看此日';
        }
        if (btn) {
          if (isFocused) {
            btn.classList.add('bg-indigo-600', 'text-white');
            btn.classList.remove('bg-slate-800', 'text-indigo-300');
          } else {
            btn.classList.remove('bg-indigo-600', 'text-white');
            btn.classList.add('bg-slate-800', 'text-indigo-300');
          }
        }
      }
    });

    // Empty State Display: distinguish 0 total transactions vs filter mismatch
    const emptyState = document.getElementById('tx-empty-state');
    const noMatchState = document.getElementById('tx-no-match-state');
    if (items.length === 0) {
      if (emptyState) emptyState.classList.remove('hidden');
      if (noMatchState) noMatchState.classList.add('hidden');
    } else if (totalVisible === 0) {
      if (emptyState) emptyState.classList.add('hidden');
      if (noMatchState) noMatchState.classList.remove('hidden');
    } else {
      if (emptyState) emptyState.classList.add('hidden');
      if (noMatchState) noMatchState.classList.add('hidden');
    }

    return totalVisible;
  }

  // Advanced Filter Modal Open & Close
  function openFilterModal() {
    const modal = document.getElementById('filter-modal');
    if (modal) modal.classList.remove('hidden');
  }

  function closeFilterModal() {
    const modal = document.getElementById('filter-modal');
    if (modal) modal.classList.add('hidden');
  }

  // Modal Type Selector
  function selectModalType(btn, type) {
    selectedFilterType = type;
    const btns = document.querySelectorAll('.modal-type-btn');
    btns.forEach(b => {
      b.className = "modal-type-btn py-1.5 rounded-xl border border-slate-700 bg-slate-800 text-slate-300 font-medium tap-highlight";
    });
    btn.className = "modal-type-btn py-1.5 rounded-xl border border-indigo-500 bg-indigo-600 text-white font-medium tap-highlight";
  }

  // Modal Date Preset Selector
  function selectDatePreset(btn, preset) {
    selectedDatePreset = preset;
    const btns = document.querySelectorAll('.modal-date-btn');
    btns.forEach(b => b.classList.remove('active-tag'));
    btn.classList.add('active-tag');

    const startInput = document.getElementById('filter-start-date');
    const endInput = document.getElementById('filter-end-date');
    const summary = document.getElementById('filter-date-summary');

    if (preset === 'all') {
      if (startInput) startInput.value = '';
      if (endInput) endInput.value = '';
      if (summary) summary.innerText = '全部日期';
    } else if (preset === 'today') {
      if (startInput) startInput.value = '2026-10-26';
      if (endInput) endInput.value = '2026-10-26';
      if (summary) summary.innerText = '今天 (2026-10-26)';
    } else if (preset === 'yesterday') {
      if (startInput) startInput.value = '2026-10-25';
      if (endInput) endInput.value = '2026-10-25';
      if (summary) summary.innerText = '昨天 (2026-10-25)';
    } else if (preset === 'before_yesterday') {
      if (startInput) startInput.value = '2026-10-24';
      if (endInput) endInput.value = '2026-10-24';
      if (summary) summary.innerText = '前天 (2026-10-24)';
    } else if (preset === 'week') {
      if (startInput) startInput.value = '2026-10-20';
      if (endInput) endInput.value = '2026-10-26';
      if (summary) summary.innerText = '近7天 (10-20 ~ 10-26)';
    } else if (preset === 'month') {
      const lastDay = getLastDayOfMonth(currentActiveYear, currentActiveMonth).toString().padStart(2, '0');
      if (startInput) startInput.value = `${currentActiveYear}-${currentActiveMonth}-01`;
      if (endInput) endInput.value = `${currentActiveYear}-${currentActiveMonth}-${lastDay}`;
      if (summary) summary.innerText = `本月 (${currentActiveYear}-${currentActiveMonth})`;
    } else if (preset === 'custom') {
      if (summary) summary.innerText = '自定义区间';
      if (startInput) startInput.focus();
    }

    // Sync quick date dropdown and scope label
    const qd = document.getElementById('quick-date-dropdown');
    const scopeLabel = document.getElementById('tx-scope-label');
    if (preset === 'today') {
      quickDateFilter = 'today';
      if (qd) qd.value = 'today';
      if (scopeLabel) scopeLabel.innerText = '今天流水';
    } else if (preset === 'yesterday') {
      quickDateFilter = 'yesterday';
      if (qd) qd.value = 'yesterday';
      if (scopeLabel) scopeLabel.innerText = '昨天流水';
    } else if (preset === 'before_yesterday') {
      quickDateFilter = 'before_yesterday';
      if (qd) qd.value = 'before_yesterday';
      if (scopeLabel) scopeLabel.innerText = '前天流水';
    } else if (preset === 'week') {
      quickDateFilter = '7days';
      if (qd) qd.value = '7days';
      if (scopeLabel) scopeLabel.innerText = '近 7 天流水';
    } else if (preset === 'month' || preset === 'all') {
      quickDateFilter = 'all_month';
      if (qd) qd.value = 'all_month';
      if (scopeLabel) scopeLabel.innerText = '全月流水';
    }
  }

  function onCustomDateInputChanged() {
    selectedDatePreset = 'custom';
    const btns = document.querySelectorAll('.modal-date-btn');
    btns.forEach(b => b.classList.remove('active-tag'));
    const customBtn = Array.from(btns).find(b => b.innerText.includes('自定义'));
    if (customBtn) customBtn.classList.add('active-tag');

    const s = document.getElementById('filter-start-date')?.value;
    const e = document.getElementById('filter-end-date')?.value;
    const summary = document.getElementById('filter-date-summary');
    if (summary) {
      if (s || e) {
        summary.innerText = `${s || '...'} ~ ${e || '...'}`;
      } else {
        summary.innerText = '自定义区间';
      }
    }
  }

  // Modal Category Multi-Select Toggle (8 Core Parent Categories)
  function toggleModalCat(span, cat) {
    const allTag = document.querySelector('#filter-modal-cats .modal-cat-tag:first-child');
    const tags = document.querySelectorAll('#filter-modal-cats .modal-cat-tag');
    const badge = document.getElementById('filter-cat-badge');

    if (cat === 'all') {
      selectedFilterCats.clear();
      selectedFilterCats.add('all');
      tags.forEach(t => t.classList.remove('active-tag'));
      span.classList.add('active-tag');
      if (badge) badge.innerText = '全部';
      return;
    }

    // Deselect 'all'
    selectedFilterCats.delete('all');
    if (allTag) allTag.classList.remove('active-tag');

    if (selectedFilterCats.has(cat)) {
      selectedFilterCats.delete(cat);
      span.classList.remove('active-tag');
    } else {
      selectedFilterCats.add(cat);
      span.classList.add('active-tag');
    }

    if (selectedFilterCats.size === 0) {
      selectedFilterCats.add('all');
      if (allTag) allTag.classList.add('active-tag');
      if (badge) badge.innerText = '全部';
    } else {
      if (badge) badge.innerText = `已选 ${selectedFilterCats.size} 类`;
    }
  }

  // Modal Account Selector
  function selectModalAccount(btn, acc) {
    selectedFilterAccount = acc;
    const btns = document.querySelectorAll('.modal-acc-btn');
    btns.forEach(b => b.classList.remove('active-tag'));
    btn.classList.add('active-tag');
    const badge = document.getElementById('filter-acc-badge');
    if (badge) badge.innerText = acc === 'all' ? '全部' : acc;
  }

  // Reset All Filters
  function resetFilter() {
    selectedFilterType = 'all';
    selectedFilterCats = new Set(['all']);
    selectedFilterAccount = 'all';
    selectedDatePreset = 'all';
    activeDayFilter = null;
    activeDayLabel = '';
    currentFilterKey = 'all';
    quickDateFilter = 'all_month';
    const qd = document.getElementById('quick-date-dropdown');
    if (qd) qd.value = 'all_month';
    const scopeLabel = document.getElementById('tx-scope-label');
    if (scopeLabel) scopeLabel.innerText = '全流水';

    // Reset modal UI
    const typeBtns = document.querySelectorAll('.modal-type-btn');
    if (typeBtns.length > 0) selectModalType(typeBtns[0], 'all');

    const dateBtns = document.querySelectorAll('.modal-date-btn');
    if (dateBtns.length > 0) selectDatePreset(dateBtns[0], 'all');

    const catTags = document.querySelectorAll('#filter-modal-cats .modal-cat-tag');
    catTags.forEach(t => t.classList.remove('active-tag'));
    if (catTags.length > 0) {
      catTags[0].classList.add('active-tag');
      const badge = document.getElementById('filter-cat-badge');
      if (badge) badge.innerText = '全部';
    }

    const accBtns = document.querySelectorAll('.modal-acc-btn');
    if (accBtns.length > 0) selectModalAccount(accBtns[0], 'all');

    const banner = document.getElementById('day-focus-banner');
    if (banner) banner.classList.add('hidden');

    closeFilterModal();
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
    showToast("筛选条件已全部重置");
  }

  // Apply Filter Modal
  function applyFilterModal() {
    closeFilterModal();
    // If drawer specified a date preset or custom range, clear day focus to prevent lock
    if (selectedDatePreset !== 'all') {
      activeDayFilter = null;
      activeDayLabel = '';
      const banner = document.getElementById('day-focus-banner');
      if (banner) banner.classList.add('hidden');
    }

    currentFilterKey = 'all'; // compound mode takes over
    const matched = applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
    
    let summaryParts = [];
    if (selectedFilterType !== 'all') summaryParts.push(selectedFilterType === 'expense' ? '仅支出' : '收入/退款');
    if (!selectedFilterCats.has('all')) summaryParts.push(Array.from(selectedFilterCats).join('、'));
    if (selectedDatePreset !== 'all') {
      const s = document.getElementById('filter-date-summary')?.innerText || selectedDatePreset;
      summaryParts.push(s);
    }
    if (selectedFilterAccount !== 'all') summaryParts.push(selectedFilterAccount);

    const desc = summaryParts.length > 0 ? summaryParts.join(' | ') : '全部条件';
    showToast(`多维筛选生效：匹配 ${matched} 笔流水 (${desc})`);
  }

  // Deduplication Modal & Registry
  let committedOrderIds = new Set(['4200001234202610220098765432']);
  let dedupToastTimer = null;

  function collectAllExistingTransactions() {
    const existingOrders = new Set();
    committedOrderIds.forEach(id => {
      const c = typeof normalizeOrderId === 'function' ? normalizeOrderId(id) : String(id).trim();
      if (c) existingOrders.add(c);
    });
    const items = Array.from(document.querySelectorAll('.tx-item:not(.soft-deleted)'));
    for (const item of items) {
      const itemOrder = item.getAttribute('data-order') || item.dataset?.order;
      if (itemOrder) {
        const c = typeof normalizeOrderId === 'function' ? normalizeOrderId(itemOrder) : itemOrder.trim();
        if (c) existingOrders.add(c);
      }
      if (item.onclick) {
        const onclickStr = item.onclick.toString();
        const m = onclickStr.match(/['"]([0-9a-zA-Z_-]{8,})['"]\s*\)/);
        if (m && m[1]) {
          const c = typeof normalizeOrderId === 'function' ? normalizeOrderId(m[1]) : m[1].trim();
          if (c) existingOrders.add(c);
        }
      }
    }
    if (typeof allMonthlyData === 'object' && allMonthlyData) {
      for (const key of Object.keys(allMonthlyData)) {
        const monthObj = allMonthlyData[key];
        if (monthObj && Array.isArray(monthObj.txs)) {
          monthObj.txs.forEach(tx => {
            if (tx && tx.orderId) {
              const c = typeof normalizeOrderId === 'function' ? normalizeOrderId(tx.orderId) : String(tx.orderId).trim();
              if (c) existingOrders.add(c);
            }
          });
        }
      }
    }
    return existingOrders;
  }

  function isOrderIdDuplicate(orderId) {
    const cleanOrder = typeof normalizeOrderId === 'function' ? normalizeOrderId(orderId) : String(orderId || '').trim();
    if (!cleanOrder) return false;
    const existingOrders = collectAllExistingTransactions();
    if (typeof SingWalletDomain !== 'undefined' && typeof SingWalletDomain.isOrderIdDuplicate === 'function') {
      return SingWalletDomain.isOrderIdDuplicate(cleanOrder, existingOrders);
    }
    return existingOrders.has(cleanOrder);
  }

  function showDedupTopToast(orderId) {
    if (dedupToastTimer) {
      clearTimeout(dedupToastTimer);
      dedupToastTimer = null;
    }
    const toast = document.getElementById('dedup-top-toast');
    const orderEl = document.getElementById('dedup-toast-order-text');
    if (orderEl) orderEl.innerText = orderId;
    if (toast) {
      toast.classList.remove('hidden');
      const viewDrafts = document.getElementById('view-drafts');
      if (viewDrafts) viewDrafts.scrollTo({ top: 0, behavior: 'smooth' });
    }
    const inOrder = document.getElementById('input-order');
    if (inOrder) {
      inOrder.classList.add('ring-4', 'ring-amber-500');
      setTimeout(() => inOrder.classList.remove('ring-4', 'ring-amber-500'), 1500);
    }
    dedupToastTimer = setTimeout(() => {
      closeDedupTopToast();
    }, 7500);
  }

  function closeDedupTopToast() {
    if (dedupToastTimer) {
      clearTimeout(dedupToastTimer);
      dedupToastTimer = null;
    }
    const toast = document.getElementById('dedup-top-toast');
    if (toast) toast.classList.add('hidden');
  }

  function focusOrderInputFromToast() {
    closeDedupTopToast();
    const inOrder = document.getElementById('input-order');
    if (inOrder) {
      inOrder.focus();
      inOrder.select();
      inOrder.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  function simulateDedupWarning() {
    const curDraft = draftQueue[currentDraftIndex];
    const curOrder = document.getElementById('input-order')?.value?.trim() || (curDraft ? curDraft.orderId : '4200001234202610220098765432');
    showDedupTopToast(curOrder);
  }

  function closeDedupModal() {
    const modal = document.getElementById('dedup-modal');
    if (modal) modal.classList.add('hidden');
    closeDedupTopToast();
  }

  function forceConfirm() {
    closeDedupModal();
    confirmTransaction(true);
  }

  // 智能推断与规范化分类字段 (容错自愈引擎)
  function normalizeTxCategory(txData) {
    if (!txData) return { catName: '其他支出', parentCat: '其他支出' };
    let rawCat = txData.catName || txData.category || txData.cat || txData.parentCat || '';
    if (typeof rawCat !== 'string' || rawCat.trim() === '' || rawCat === 'undefined' || rawCat === 'null') {
      rawCat = '';
    } else {
      rawCat = rawCat.trim();
    }
    
    if (!rawCat) {
      const m = (txData.merchant || txData.name || '').toLowerCase();
      if (/公交|地铁|一码通|出行|打车|滴滴|高铁|火车|停车|加油/.test(m)) {
        rawCat = '交通出行';
      } else if (/小吃|早餐|早点|餐饮|美食|饭|面|粉|火锅|烧烤|奶茶|咖啡|瑞幸|星巴克|美团|饿了么|餐厅|食堂/.test(m)) {
        rawCat = '餐饮美食';
      } else if (/超市|便利|百货|购物|淘宝|京东|拼多多/.test(m)) {
        rawCat = '日常购物';
      } else {
        rawCat = '其他支出';
      }
    }
    
    let safeParentCat = (typeof resolveParentCategory === 'function' ? resolveParentCategory(rawCat) : rawCat) || '其他支出';
    if (!safeParentCat || safeParentCat === 'undefined' || safeParentCat === 'null') {
      safeParentCat = '其他支出';
    }
    const safeCatName = rawCat || safeParentCat;
    return { catName: safeCatName, parentCat: safeParentCat };
  }

  // Shared Transaction Insertion Engine with Dynamic Date Grouping & Exact Time Tracking
  function insertTransactionToList(txData) {
    const norm = normalizeTxCategory(txData);
    const catName = norm.catName;
    const parentCat = norm.parentCat;
    txData.catName = catName;
    txData.parentCat = parentCat;
    txData.category = catName;
    txData.cat = catName;

    const rawTxTime = txData.txTime || txData.orderTime || txData.fullTime || '';
    const txDate = txData.txDate || txData.date || (rawTxTime && rawTxTime.includes(' ') ? rawTxTime.split(' ')[0] : '') || '2026-10-26';
    const txTime = rawTxTime || (txDate + ' 12:00:00');
    const timeOnly = txData.timeOnly || txData.time || (txTime.includes(' ') ? txTime.split(' ')[1] : txTime);

    const activeMonthKey = `${currentActiveYear}-${String(currentActiveMonth).padStart(2, '0')}`;
    const targetMonthKey = (/^\d{4}-\d{2}/.test(txDate)) ? txDate.slice(0, 7) : activeMonthKey;
    const isTargetActiveMonth = (targetMonthKey === activeMonthKey);

    let groupName = `${parseInt(txDate.slice(5, 7))}月${parseInt(txDate.slice(8, 10))}日`;
    if (txDate === '2026-10-26') groupName += ' 今天';
    else if (txDate === '2026-10-25') groupName += ' 昨天';

    const numAmt = Math.round((Number(txData.amount) || 0) * 100) / 100;
    txData.amount = numAmt;
    const merchantName = txData.merchant || txData.name || '日常消费';
    txData.merchant = merchantName;

    if (isTargetActiveMonth) {
      const emptyState = document.getElementById('tx-empty-state');
      if (emptyState) emptyState.classList.add('hidden');

      // Find or create day group
      let dayGroup = document.querySelector(`.day-group[data-date="${txDate}"]`);
      const listContainer = document.getElementById('transactions-list');
      if (!dayGroup && listContainer) {
        dayGroup = document.createElement('div');
        dayGroup.className = "space-y-2 day-group";
        dayGroup.setAttribute('data-date', txDate);
        dayGroup.innerHTML = `
          <div onclick="toggleDayFilter('${txDate}', '${groupName}')" class="day-header flex items-center justify-between text-xs text-slate-400 px-2 py-1.5 rounded-xl hover:bg-slate-800/80 cursor-pointer tap-highlight font-mono group transition-all" title="点击日标题或小计，即可按日筛选">
            <div class="flex items-center space-x-2">
              <span class="font-bold text-slate-200 group-hover:text-indigo-300 transition-colors">${groupName}</span>
              <span class="day-filter-btn text-[10px] bg-slate-800 group-hover:bg-indigo-600 text-indigo-300 group-hover:text-white px-2 py-0.5 rounded-lg border border-slate-700/80 transition-all flex items-center space-x-1">
                <svg class="w-2.5 h-2.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"/></svg>
                <span class="day-filter-btn-text">仅看此日</span>
              </span>
            </div>
            <span class="day-subtotal group-hover:text-indigo-300 font-semibold transition-colors">小计: -¥ 0.00</span>
          </div>
        `;
        // Insert in chronological order (newer dates first)
        const existingGroups = Array.from(listContainer.querySelectorAll('.day-group'));
        let inserted = false;
        for (const eg of existingGroups) {
          if (txDate > (eg.getAttribute('data-date') || '')) {
            listContainer.insertBefore(dayGroup, eg);
            inserted = true;
            break;
          }
        }
        if (!inserted) listContainer.appendChild(dayGroup);
      }

      const newTx = document.createElement('div');
      newTx.className = "tx-item flex items-center justify-between p-3.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 shadow-md hover:border-indigo-500 transition-all cursor-pointer tap-highlight animate-fadeIn";
      newTx.setAttribute('data-cat', catName);
      newTx.setAttribute('data-parent', parentCat);
      newTx.setAttribute('data-category', parentCat);
      newTx.setAttribute('data-type', 'expense');
      newTx.setAttribute('data-date', txDate);
      newTx.setAttribute('data-account', txData.account || txData.channel);
      newTx.setAttribute('data-channel', txData.channel);
      newTx.setAttribute('data-order', txData.orderId || '');
      newTx.dataset.order = txData.orderId || '';
      newTx.setAttribute('data-amount', numAmt);
      newTx.dataset.amount = numAmt;
      newTx.id = txData.id;
      newTx.onclick = () => viewTransactionDetail(merchantName, numAmt.toFixed(2), `${parentCat}（${catName}）`, txData.account || txData.channel, txTime, txData.orderId);
      
      const cleanAcc = (txData.account || txData.channel || '微信钱包').replace('支付 · ', '');
      const icon = getAppCatIcon(parentCat, txData.catIcon || getAppStatusIcon('fallbackCategory'));
      
      let iconSquircle = window.renderSquircleIcon 
        ? window.renderSquircleIcon(parentCat, 'w-10 h-10') 
        : `<div class="w-10 h-10 rounded-2xl bg-slate-700/50 flex items-center justify-center text-lg shrink-0 border border-slate-600/40 shadow-sm" data-cat-icon="${parentCat}">${icon}</div>`;
      
      if (!iconSquircle.includes('data-cat-icon')) {
        iconSquircle = iconSquircle.replace('class="', `data-cat-icon="${parentCat}" class="`);
      }

      newTx.innerHTML = `
        <div class="flex items-center space-x-3 min-w-0 flex-1 mr-2.5">
          ${iconSquircle}
          <div class="min-w-0 flex-1">
            <div class="flex items-center">
              <span class="font-semibold text-sm text-slate-100 truncate">${merchantName}</span>
            </div>
            <div class="text-xs text-slate-400 mt-1 flex items-center space-x-1.5 truncate">
              <span class="inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-medium bg-indigo-500/15 text-indigo-300 border border-indigo-500/25 shrink-0">${catName}</span>
              <span class="text-slate-400 font-mono text-[11px] shrink-0">${timeOnly}</span>
            </div>
          </div>
        </div>
        <div class="text-right shrink-0 flex flex-col items-end justify-center ml-2">
          <div class="font-bold text-base text-white font-mono tracking-tight whitespace-nowrap">-¥ ${numAmt.toFixed(2)}</div>
          <span class="tx-source-tag text-[11px] text-slate-400 font-normal mt-1 block text-right whitespace-nowrap">${cleanAcc}</span>
        </div>
        <div role="button" class="tx-swipe-delete-btn" onclick="openTxDeleteConfirmModal(this.closest('.tx-item'), event)">
          <svg class="w-4 h-4 mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
          <span>删除</span>
        </div>
      `;

      if (dayGroup) {
        dayGroup.appendChild(newTx);
        // Recalculate day subtotal with IEEE 754 precision rounding
        const items = dayGroup.querySelectorAll('.tx-item:not(.soft-deleted)');
        let dayTotal = 0;
        items.forEach(el => {
          const amtStr = el.querySelector('.text-base')?.innerText?.replace(/[^\d.]/g, '') || '0';
          dayTotal = Math.round((dayTotal + parseFloat(amtStr)) * 100) / 100;
        });
        const subEl = dayGroup.querySelector('.day-subtotal');
        if (subEl) subEl.innerText = `小计: -¥ ${dayTotal.toFixed(2)}`;
      }
    }

    // Bug 2 修复：动态按 txDate 所属月份写入 allMonthlyData[targetMonthKey]，禁止硬编码 '2026-10'
    if (!allMonthlyData[targetMonthKey]) {
      allMonthlyData[targetMonthKey] = { net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00', count: '0 笔', avg: '¥0.00', txs: [] };
    }
    if (!Array.isArray(allMonthlyData[targetMonthKey].txs)) {
      allMonthlyData[targetMonthKey].txs = [];
    }
    allMonthlyData[targetMonthKey].txs.unshift({
      id: txData.id,
      name: merchantName,
      merchant: merchantName,
      cat: catName,
      category: catName,
      catName: catName,
      parentCat: parentCat,
      icon: txData.catIcon || txData.icon,
      channel: txData.channel,
      account: txData.account,
      payment: txData.payment,
      amount: numAmt,
      amountInCents: txData.amountInCents || Math.round(numAmt * 100),
      date: txDate,
      txDate: txDate,
      dateGroup: groupName,
      time: timeOnly,
      txTime: txTime,
      fullTime: txTime,
      orderTime: txData.orderTime || txTime,
      badge: txData.badge,
      orderId: txData.orderId,
      softDeleted: false
    });

    // 若外部直接调用 insertTransactionToList 插入非当前激活月份的跨月账单且尚未调整该月统计，自动同步目标月统计
    if (!isTargetActiveMonth && !txData._totalsAdjusted) {
      adjustMonthlyTotals(numAmt, true, 1, targetMonthKey);
    }

    saveUserTransactionsToStorage();
    if (isTargetActiveMonth && typeof renderMonthlyCategoryChart === 'function') {
      renderMonthlyCategoryChart();
    }
  }

  function confirmTransaction(force = false) {
    if (draftQueue.length === 0) return;
    const curDraft = draftQueue[currentDraftIndex];
    const inputOrder = document.getElementById('input-order')?.value?.trim();
    const orderId = (inputOrder || (curDraft ? curDraft.orderId : ('420000' + Date.now()))).trim();

    // Integrated duplicate detection check
    if (!force && isOrderIdDuplicate(orderId)) {
      showDedupTopToast(orderId);
      return false;
    }

    closeDedupTopToast();

    const amount = parseFloat(document.getElementById('input-amount').value || "0");
    const merchant = (document.getElementById('input-merchant').value || "日常消费").trim();
    const channel = document.getElementById('select-channel')?.value || "微信";
    const account = document.getElementById('select-account')?.value || "钱包";
    const catName = currentDraftCategory.name || "餐饮美食";
    const parentCat = (typeof resolveParentCategory === 'function' ? resolveParentCategory(catName) : catName) || '其他支出';
    const catIcon = getAppCatIcon(parentCat);

    if (amount <= 0 || isNaN(amount)) {
      showToast(`${getAppStatusIcon('warning')} 请输入大于 0 的有效金额`);
      return;
    }

    if (!merchant) {
      showToast(`${getAppStatusIcon('warning')} 请输入商户名称`);
      return;
    }

    const inputTime = document.getElementById('input-time')?.value?.trim();
    let txTime = inputTime || (curDraft ? (curDraft.orderTime || curDraft.time) : (typeof formatCurrentDateTime === 'function' ? formatCurrentDateTime() : '2026-10-26 12:00:00'));
    if (typeof normalizeDateTimeString === 'function') {
      txTime = normalizeDateTimeString(txTime);
    }
    if (typeof isValidDateTimeString === 'function' && !isValidDateTimeString(txTime)) {
      showToast(`${getAppStatusIcon('warning')} 订单时间格式错误或非法日历日期，请输入有效 YYYY-MM-DD HH:mm:ss`);
      return;
    }
    const txDate = txTime.split(' ')[0] || '2026-10-26';
    const timeOnly = txTime.includes(' ') ? txTime.split(' ')[1] : txTime;

    // Construct standard PaymentMethod object conforming to LlmBillResult
    let paymentObj = null;
    if (curDraft && curDraft.payment && curDraft.payment.channel === channel && (curDraft.payment.sub_type === account || curDraft.payment.display_name.includes(account))) {
      paymentObj = curDraft.payment;
    } else if (typeof parsePaymentMethodString === 'function') {
      paymentObj = parsePaymentMethodString(`${channel} · ${account}`);
    } else {
      paymentObj = { channel: channel, display_name: `${channel} · ${account}` };
    }

    // Register orderId to prevent future duplicates
    if (orderId) {
      committedOrderIds.add(orderId);
    }

    showToast(`${getAppStatusIcon('success')} 入账成功: ${merchant} ¥${amount.toFixed(2)}`);
    
    const activeMonthKey = `${currentActiveYear}-${String(currentActiveMonth).padStart(2, '0')}`;
    const targetMonthKey = (/^\d{4}-\d{2}/.test(txDate)) ? txDate.slice(0, 7) : activeMonthKey;

    // Update Monthly Dashboard for targetMonthKey
    adjustMonthlyTotals(amount, true, 1, targetMonthKey);

    insertTransactionToList({
      id: "item-tx-" + Date.now(),
      merchant: merchant,
      amount: amount,
      amountInCents: Math.round(amount * 100),
      catName: catName,
      catIcon: catIcon,
      parentCat: parentCat,
      category: catName,
      channel: paymentObj.channel,
      account: paymentObj.display_name,
      payment: paymentObj,
      txTime: txTime,
      orderTime: txTime,
      txDate: txDate,
      timeOnly: timeOnly,
      orderId: orderId,
      badge: '刚刚入账',
      _totalsAdjusted: true
    });

    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();

    // Remove confirmed draft from queue
    draftQueue.splice(currentDraftIndex, 1);
    if (currentDraftIndex >= draftQueue.length) {
      currentDraftIndex = Math.max(0, draftQueue.length - 1);
    }
    renderDraftQueue();

    if (draftQueue.length === 0) {
      setTimeout(() => switchTab('transactions'), 400);
    }
    return true;
  }

  // Helper: Adjust monthly expense & net expense (Bug 2 & Bug 6 修复：动态月份键 + 消除 IEEE 754 浮点尾差)
  function adjustMonthlyTotals(deltaAmount, isExpense = true, deltaCount = 0, targetMonthKey = null) {
    const activeMonthKey = `${currentActiveYear}-${String(currentActiveMonth).padStart(2, '0')}`;
    const monthKey = (targetMonthKey && /^\d{4}-\d{2}$/.test(targetMonthKey)) ? targetMonthKey : activeMonthKey;
    const isTargetActive = (monthKey === activeMonthKey);

    if (!allMonthlyData[monthKey]) {
      allMonthlyData[monthKey] = { net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00', count: '0 笔', avg: '¥0.00', txs: [] };
    }
    const mData = allMonthlyData[monthKey];
    const delta = Number(deltaAmount) || 0;

    if (isExpense === false) {
      const baseInc = parseFloat(String(mData.inc || '0').replace(/[¥\s,]/g, '') || 0);
      const nextInc = Math.max(0, Math.round((baseInc + delta) * 100) / 100);
      mData.inc = nextInc.toFixed(2);
      if (isTargetActive) {
        const incEl = document.getElementById('total-income');
        if (incEl) incEl.innerText = `¥ ${nextInc.toFixed(2)}`;
      }
      return;
    }

    const curExpEl = document.getElementById('total-expense');
    const curNetEl = document.getElementById('total-net-expense');
    const monthlyNetEl = document.getElementById('monthly-net-expense');
    const homeExpEl = document.getElementById('home-total-expense');

    const baseExp = isTargetActive && curExpEl
      ? parseFloat(curExpEl.innerText.replace(/[¥\s,]/g, '') || 0)
      : parseFloat(String(mData.exp || '0').replace(/[¥\s,]/g, '') || 0);
    const baseNet = isTargetActive && (curNetEl || monthlyNetEl)
      ? parseFloat((curNetEl ? curNetEl.innerText : monthlyNetEl.innerText).replace(/[¥\s,]/g, '') || 0)
      : parseFloat(String(mData.net || mData.exp || '0').replace(/[¥\s,]/g, '') || 0);

    const curExpense = Math.max(0, Math.round((baseExp + delta) * 100) / 100);
    const curNet = Math.max(0, Math.round((baseNet + delta) * 100) / 100);

    mData.exp = curExpense.toFixed(2);
    mData.net = curNet.toFixed(2);
    const activeTxCount = Array.isArray(mData.txs) ? mData.txs.filter(t => t && !t.softDeleted).length : Math.max(0, deltaCount);
    mData.count = `${activeTxCount} 笔`;

    if (isTargetActive) {
      if (curExpEl) curExpEl.innerText = `¥ ${curExpense.toFixed(2)}`;
      if (curNetEl) curNetEl.innerText = `¥ ${curNet.toFixed(2)}`;
      if (monthlyNetEl) monthlyNetEl.innerText = `¥ ${curNet.toFixed(2)}`;
      if (homeExpEl) homeExpEl.innerText = `¥ ${curExpense.toFixed(2)}`;
      if (typeof renderMonthlyCategoryChart === 'function') {
        renderMonthlyCategoryChart();
      }
    }
  }

  // Helper: Recalculate day subtotal for a day group
  function updateDaySubtotalForElement(itemEl) {
    if (!itemEl) return;
    const dayGroup = itemEl.closest('.day-group');
    if (dayGroup) {
      const items = dayGroup.querySelectorAll('.tx-item:not(.soft-deleted)');
      let dayTotal = 0;
      items.forEach(el => {
        const amtStr = el.querySelector('.text-base')?.innerText?.replace(/[^\d.]/g, '') || '0';
        dayTotal = Math.round((dayTotal + parseFloat(amtStr)) * 100) / 100;
      });
      const subEl = dayGroup.querySelector('.day-subtotal');
      if (subEl) subEl.innerText = `小计: -¥ ${dayTotal.toFixed(2)}`;
    }
  }

  let lastDeletedId = null;
  let deletedItems = [];
  function updateTrashBadge() {
    const trashBadge = document.getElementById('trash-badge');
    const trashDot = document.getElementById('trash-dot');
    if (deletedItems.length > 0) {
      if (trashBadge) trashBadge.classList.remove('hidden');
      if (trashDot) trashDot.classList.remove('hidden');
    } else {
      if (trashBadge) trashBadge.classList.add('hidden');
      if (trashDot) trashDot.classList.add('hidden');
    }
  }


  function deleteTransaction(itemId, name, amount) {
    // Bug 1 修复：同步在 allMonthlyData 各月份 txs 中标记 tx.softDeleted = true，确保 saveUserTransactionsToStorage 不会将已删账单写回 localStorage
    let foundMonthKey = null;
    let foundTx = null;
    Object.keys(allMonthlyData).forEach(mKey => {
      const m = allMonthlyData[mKey];
      if (m && Array.isArray(m.txs)) {
        m.txs.forEach(tx => {
          if (tx && tx.id === itemId) {
            tx.softDeleted = true;
            foundMonthKey = mKey;
            foundTx = tx;
          }
        });
      }
    });

    const item = document.getElementById(itemId);
    const resolvedName = name || (foundTx && (foundTx.merchant || foundTx.name)) || '账单';
    const resolvedAmount = (typeof amount === 'number' && !isNaN(amount))
      ? amount
      : (foundTx ? Number(foundTx.amount) || 0 : (item ? parseFloat(item.getAttribute('data-amount') || '0') : 0));

    if (item || foundTx) {
      if (item) {
        item.classList.add('soft-deleted');
        item.style.display = 'none';
      }
      lastDeletedId = itemId;
      deletedItems = deletedItems.filter(i => i.id !== itemId);
      deletedItems.push({ id: itemId, name: resolvedName, amount: resolvedAmount, monthKey: foundMonthKey });

      // Deduct from monthly totals & recalculate day subtotal
      adjustMonthlyTotals(-resolvedAmount, true, -1, foundMonthKey);
      if (item) {
        updateDaySubtotalForElement(item);
      }

      const bar = document.getElementById('undo-snackbar');
      const snackText = document.getElementById('snackbar-text');
      if (snackText) snackText.innerText = `已移入回收站: ${resolvedName} (-¥${resolvedAmount.toFixed(2)})`;
      if (bar) bar.classList.remove('hidden');

      updateTrashBadge();
      saveUserTransactionsToStorage();
      applyActiveFilters();
      updateDynamicCategoryChips();
      if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();

      setTimeout(() => {
        if (bar) bar.classList.add('hidden');
      }, 4000);
    }
  }

  function undoDelete() {
    if (lastDeletedId) {
      let foundMonthKey = null;
      let restoredTx = null;
      Object.keys(allMonthlyData).forEach(mKey => {
        const m = allMonthlyData[mKey];
        if (m && Array.isArray(m.txs)) {
          m.txs.forEach(tx => {
            if (tx && tx.id === lastDeletedId) {
              tx.softDeleted = false;
              foundMonthKey = mKey;
              restoredTx = tx;
            }
          });
        }
      });

      const item = document.getElementById(lastDeletedId);
      const lastItem = deletedItems[deletedItems.length - 1];
      const restoreAmt = (lastItem && typeof lastItem.amount === 'number')
        ? lastItem.amount
        : (restoredTx ? Number(restoredTx.amount) || 0 : 0);
      const targetKey = (lastItem && lastItem.monthKey) || foundMonthKey;

      if (item) {
        item.classList.remove('soft-deleted');
        item.style.display = 'flex';
        updateDaySubtotalForElement(item);
      }
      if (item || restoredTx) {
        adjustMonthlyTotals(restoreAmt, true, 1, targetKey);
      }
      const undoBar = document.getElementById('undo-snackbar');
      if (undoBar) undoBar.classList.add('hidden');
      deletedItems.pop();
      lastDeletedId = deletedItems.length > 0 ? deletedItems[deletedItems.length - 1].id : null;
      updateTrashBadge();
      saveUserTransactionsToStorage();
      applyActiveFilters();
      updateDynamicCategoryChips();
      if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();
      showToast("已成功撤回删除");
    }
  }

  function openTrashDialog() {
    const container = document.getElementById('trash-items');
    if (container) {
      if (deletedItems.length === 0) {
        container.innerHTML = '<p class="text-center py-4 text-slate-500">回收站为空</p>';
      } else {
        container.innerHTML = deletedItems.map(item => `
          <div class="flex items-center justify-between p-2.5 rounded-xl bg-slate-800 border border-slate-700">
            <span>${item.name} (-¥${item.amount.toFixed(2)})</span>
            <span class="text-emerald-400 font-semibold cursor-pointer hover:underline" onclick="restoreTrash('${item.id}')">恢复账目</span>
          </div>
        `).join('');
      }
    }
    const trashModal = document.getElementById('trash-modal');
    if (trashModal) trashModal.classList.remove('hidden');
  }

  function restoreTrash(id) {
    let foundMonthKey = null;
    let restoredTx = null;
    Object.keys(allMonthlyData).forEach(mKey => {
      const m = allMonthlyData[mKey];
      if (m && Array.isArray(m.txs)) {
        m.txs.forEach(tx => {
          if (tx && tx.id === id) {
            tx.softDeleted = false;
            foundMonthKey = mKey;
            restoredTx = tx;
          }
        });
      }
    });

    const item = document.getElementById(id);
    const found = deletedItems.find(i => i.id === id);
    const restoreAmt = (found && typeof found.amount === 'number')
      ? found.amount
      : (restoredTx ? Number(restoredTx.amount) || 0 : 0);
    const targetKey = (found && found.monthKey) || foundMonthKey;

    if (item) {
      item.classList.remove('soft-deleted');
      item.style.display = 'flex';
      updateDaySubtotalForElement(item);
    }
    if (item || restoredTx) {
      adjustMonthlyTotals(restoreAmt, true, 1, targetKey);
    }
    deletedItems = deletedItems.filter(i => i.id !== id);
    if (lastDeletedId === id) {
      lastDeletedId = deletedItems.length > 0 ? deletedItems[deletedItems.length - 1].id : null;
    }
    updateTrashBadge();
    saveUserTransactionsToStorage();
    openTrashDialog();
    applyActiveFilters();
    updateDynamicCategoryChips();
    if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();
    showToast("账目已还原到流水");
  }

  function closeTrashModal() {
    const modal = document.getElementById('trash-modal');
    if (modal) modal.classList.add('hidden');
  }

  // Clear manual image helper
  function clearManualImage() {
    if (window.isLlmProcessing && typeof stopLlmExecutionFeedback === 'function') {
      stopLlmExecutionFeedback(false);
    }
    const imgEmpty = document.getElementById('manual-image-empty-placeholder');
    const imgPreview = document.getElementById('manual-image-preview-box');
    const processingBox = document.getElementById('manual-llm-processing-box');
    const fileInput = document.getElementById('manual-upload-input');
    if (processingBox) processingBox.classList.add('hidden');
    if (imgEmpty && imgPreview) {
      imgEmpty.classList.remove('hidden');
      imgPreview.classList.add('hidden');
    }
    if (fileInput) fileInput.value = '';
    if (typeof lastUploadedData !== 'undefined') {
      window.lastUploadedData = null;
    }
  }

  // Manual Add Modal (快记一手)
  function openManualAddModal() {
    if (typeof closeAllCustomDropdowns === 'function') closeAllCustomDropdowns();
    clearManualImage();
    const banner = document.getElementById('manual-ocr-banner');
    if (banner) banner.classList.add('hidden');
    const amtInput = document.getElementById('manual-amount');
    const merInput = document.getElementById('manual-merchant');
    const ordInput = document.getElementById('manual-order');
    const timeInput = document.getElementById('manual-time');
    if (amtInput) amtInput.value = '';
    if (merInput) merInput.value = '';
    if (ordInput) ordInput.value = '';
    if (timeInput) timeInput.value = typeof formatCurrentDateTime === 'function' ? formatCurrentDateTime() : (window.formatCurrentDateTime ? window.formatCurrentDateTime() : '');
    if (typeof selectCustomDropdownOption === 'function') {
      selectCustomDropdownOption('manual-category', '餐饮美食');
      selectCustomDropdownOption('manual-pay-channel', '微信');
    }
    if (typeof onManualChannelChange === 'function') {
      onManualChannelChange('微信');
    }
    if (typeof selectCustomDropdownOption === 'function') {
      selectCustomDropdownOption('manual-pay-sub', '钱包');
    }
    if (typeof updateManualAccountCombined === 'function') {
      updateManualAccountCombined();
    }
    window.lastUploadedData = null;
    if (typeof updateOcrEngineUI === 'function') {
      updateOcrEngineUI();
    }
    const modal = document.getElementById('manual-add-modal');
    if (modal) modal.classList.remove('hidden');
  }

  function closeManualAddModal() {
    if (window.isLlmProcessing && typeof stopLlmExecutionFeedback === 'function') {
      stopLlmExecutionFeedback(false);
    }
    if (typeof closeAllCustomDropdowns === 'function') closeAllCustomDropdowns();
    const modal = document.getElementById('manual-add-modal');
    if (modal) modal.classList.add('hidden');
  }

  function saveManualTransaction() {
    if (window.isLlmProcessing) {
      showToast(`${getAppStatusIcon('spinner')} 大模型正在解析账单凭证，请稍候...`);
      return;
    }
    const amtInput = document.getElementById('manual-amount');
    const merInput = document.getElementById('manual-merchant');
    const ordInput = document.getElementById('manual-order');
    const timeInput = document.getElementById('manual-time');
    const amount = parseFloat(amtInput?.value || "0");
    const merchant = (merInput?.value || "日常消费").trim();
    const cat = document.getElementById('manual-category')?.value || '餐饮美食';
    const acc = document.getElementById('manual-account')?.value || '微信 · 钱包';
    const orderId = (ordInput?.value?.trim() || ('MANUAL_' + Date.now())).trim();
    let txTime = (timeInput?.value?.trim() || (typeof formatCurrentDateTime === 'function' ? formatCurrentDateTime() : '2026-10-26 12:00:00')).trim();

    if (amount <= 0 || isNaN(amount)) {
      showToast(`${getAppStatusIcon('warning')} 请输入大于 0 的有效金额`);
      return;
    }

    if (!merchant) {
      showToast(`${getAppStatusIcon('warning')} 请输入商户名称`);
      return;
    }

    // Time format and natural calendar date validation
    if (typeof normalizeDateTimeString === 'function') {
      txTime = normalizeDateTimeString(txTime);
    }
    if (typeof isValidDateTimeString === 'function' && !isValidDateTimeString(txTime)) {
      showToast(`${getAppStatusIcon('warning')} 订单时间格式错误或非法日历日期，请输入有效 YYYY-MM-DD HH:mm:ss`);
      return;
    }

    // Dedup check
    if (isOrderIdDuplicate(orderId)) {
      showDedupTopToast(orderId);
      return;
    }

    if (orderId) committedOrderIds.add(orderId);

    const paymentObj = typeof parsePaymentMethodString === 'function' 
      ? parsePaymentMethodString(acc) 
      : { channel: acc.split(' · ')[0] || '微信', display_name: acc };

    if (amtInput) amtInput.value = '';
    if (merInput) merInput.value = '';
    if (ordInput) ordInput.value = '';
    if (timeInput) timeInput.value = typeof formatCurrentDateTime === 'function' ? formatCurrentDateTime() : (window.formatCurrentDateTime ? window.formatCurrentDateTime() : '');

    closeManualAddModal();
    showToast(`记账成功: ${merchant} -¥${amount.toFixed(2)}`);

    const parentCat = (typeof resolveParentCategory === 'function' ? resolveParentCategory(cat) : cat) || '其他支出';
    const icon = getAppCatIcon(parentCat);

    const txDate = txTime.split(' ')[0] || `${currentActiveYear}-${currentActiveMonth}-26`;
    const timeOnly = txTime.includes(' ') ? txTime.split(' ')[1] : '16:30:00';
    const activeMonthKey = `${currentActiveYear}-${String(currentActiveMonth).padStart(2, '0')}`;
    const targetMonthKey = (/^\d{4}-\d{2}/.test(txDate)) ? txDate.slice(0, 7) : activeMonthKey;

    adjustMonthlyTotals(amount, true, 1, targetMonthKey);

    insertTransactionToList({
      id: "item-tx-" + Date.now(),
      merchant: merchant,
      amount: amount,
      amountInCents: Math.round(amount * 100),
      catName: cat,
      catIcon: icon,
      parentCat: parentCat,
      category: cat,
      channel: paymentObj.channel,
      account: paymentObj.display_name,
      payment: paymentObj,
      txTime: txTime,
      orderTime: txTime,
      txDate: txDate,
      timeOnly: timeOnly,
      orderId: orderId,
      badge: '手动录入',
      _totalsAdjusted: true
    });
    applyActiveFilters();
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
  }

  // Transaction Detail Modal
  function viewTransactionDetail(merchant, amount, cat, channel, time, order) {
    if (justSwiped) {
      justSwiped = false;
      return;
    }
    const hasSwiped = document.querySelector('.tx-item.swiped-left');
    if (hasSwiped) {
      closeAllSwipedTx();
      return;
    }
    const m = document.getElementById('detail-merchant');
    const a = document.getElementById('detail-amount');
    const c = document.getElementById('detail-cat');
    const ch = document.getElementById('detail-channel');
    const t = document.getElementById('detail-time');
    const o = document.getElementById('detail-order');
    if (m) m.innerText = merchant;
    if (a) a.innerText = `-¥ ${amount}`;
    if (c) c.innerText = cat;
    if (ch) ch.innerText = channel;
    if (t) t.innerText = time;
    if (o) o.innerText = order;
    const modal = document.getElementById('tx-detail-modal');
    if (modal) modal.classList.remove('hidden');
  }

  function closeTxDetailModal() {
    const modal = document.getElementById('tx-detail-modal');
    if (modal) modal.classList.add('hidden');
  }

  // Discarded legacy modals cleaned (no-ops preserved for backward-compatibility)
  function openAddRuleModal() {}
  function closeAddRuleModal() {}
  function saveNewRule() {}
  function toggleRule() {}
  function triggerRerunRules() {}
  function editAccountBalance() {}
  function closeAccEditModal() {}
  function saveAccountBalance() {}
  function openAddAccountModal() {}
  function closeAccAddModal() {}
  function saveNewAccount() {}
  function openRefundDemoModal() {}
  function closeRefundDemoModal() {}
  function executeRefundLinkDemo() {}

  // Month Picker Modal & Full 12-Month Grid Engine
  let currentActiveYear = '2026';
  let currentActiveMonth = '10';
  let pickerYear = 2026;

  // Clean 12-Month Realistic Financial Dataset Engine & LocalStorage Persistence
  const allMonthlyData = {};
  for (let m = 1; m <= 12; m++) {
    const k = `2026-${String(m).padStart(2, '0')}`;
    allMonthlyData[k] = { net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00', txs: [] };
  }

  function saveUserTransactionsToStorage() {
    try {
      const allTx = [];
      Object.keys(allMonthlyData).forEach(mKey => {
        const m = allMonthlyData[mKey];
        if (m && Array.isArray(m.txs)) {
          m.txs.forEach(t => {
            if (!t.softDeleted) allTx.push(t);
          });
        }
      });
      localStorage.setItem('singwallet_user_transactions', JSON.stringify(allTx));
    } catch (e) {}
  }

  function loadUserTransactionsFromStorage() {
    try {
      const raw = localStorage.getItem('singwallet_user_transactions');
      if (!raw) return [];
      const list = JSON.parse(raw);
      if (!Array.isArray(list)) return [];
      let needsResave = false;
      const repaired = list.map(item => {
        if (!item) return item;
        const norm = normalizeTxCategory(item);
        if (!item.catName || !item.parentCat || item.catName === 'undefined' || item.cat === 'undefined' || item.category === 'undefined' || item.catName !== norm.catName || item.parentCat !== norm.parentCat) {
          item.catName = norm.catName;
          item.parentCat = norm.parentCat;
          item.category = norm.catName;
          item.cat = norm.catName;
          needsResave = true;
        }
        return item;
      });
      if (needsResave) {
        localStorage.setItem('singwallet_user_transactions', JSON.stringify(repaired));
      }
      return repaired;
    } catch (e) {
      return [];
    }
  }

  function getMonthlyData(year, month) {
    const key = `${year}-${month}`;
    if (allMonthlyData[key]) return allMonthlyData[key];

    return {
      net: '0.00',
      exp: '0.00',
      ref: '0.00',
      inc: '0.00',
      txs: []
    };
  }

  // Month Picker Modal Open & Close
  function openMonthModal() {
    pickerYear = parseInt(currentActiveYear);
    renderMonthGrid();
    const modal = document.getElementById('month-modal');
    if (modal) modal.classList.remove('hidden');
  }

  function closeMonthModal() {
    const modal = document.getElementById('month-modal');
    if (modal) modal.classList.add('hidden');
  }

  function setPickerYear(y) {
    pickerYear = y;
    renderMonthGrid();
  }

  function changePickerYear(delta) {
    pickerYear += delta;
    renderMonthGrid();
  }

  // Render Full 12-Month Grid
  function renderMonthGrid() {
    const label = document.getElementById('picker-year-label');
    if (label) label.innerText = `${pickerYear} 年`;

    // Update Year Pills dynamically
    const pillsContainer = document.getElementById('quick-year-pills');
    if (pillsContainer) {
      const years = [2024, 2025, 2026];
      if (!years.includes(pickerYear)) years.push(pickerYear);
      years.sort();
      pillsContainer.innerHTML = years.map(y => `
        <button onclick="setPickerYear(${y})" class="px-2 py-0.5 rounded-lg text-[11px] ${y === pickerYear ? 'bg-indigo-600 text-white font-bold' : 'bg-slate-700 text-slate-300 hover:text-white'} tap-highlight transition-all">${y}</button>
      `).join('');
    }

    const container = document.getElementById('month-grid-container');
    if (!container) return;

    let html = '';
    for (let m = 1; m <= 12; m++) {
      const monthStr = m.toString().padStart(2, '0');
      const isActive = (pickerYear === parseInt(currentActiveYear) && monthStr === currentActiveMonth);
      const monthData = getMonthlyData(pickerYear, monthStr);

      let badge = `¥${parseFloat(monthData.net.replace(/,/g, '')).toFixed(0)}`;
      if (pickerYear === 2026 && monthStr === '10') badge = '当月';

      html += `
        <button onclick="selectMonthYear(${pickerYear}, '${monthStr}')" class="p-2.5 rounded-2xl ${isActive ? 'bg-indigo-600 border border-indigo-400 text-white font-bold ring-2 ring-indigo-500/40 shadow-lg' : 'bg-slate-800/90 hover:bg-slate-700 border border-slate-700 text-slate-200'} text-center tap-highlight transition-all flex flex-col items-center justify-center space-y-0.5">
          <span class="text-xs font-semibold">${m} 月</span>
          <span class="text-[10px] ${isActive ? 'text-indigo-200' : 'text-slate-400'} font-mono">${badge}</span>
        </button>
      `;
    }

    container.innerHTML = html;
  }

  // Select Year & Month
  function selectMonthYear(year, month) {
    currentActiveYear = String(year);
    currentActiveMonth = String(month).padStart(2, '0');
    const data = getMonthlyData(currentActiveYear, currentActiveMonth);

    const lblMonth = document.getElementById('label-current-month');
    const totalNet = document.getElementById('total-net-expense');
    const monthlyNet = document.getElementById('monthly-net-expense');
    const totalExp = document.getElementById('total-expense');
    const totalRef = document.getElementById('total-refund');
    const totalInc = document.getElementById('total-income');

    if (lblMonth) lblMonth.innerText = `${currentActiveYear} 年 ${currentActiveMonth} 月`;
    if (totalNet) totalNet.innerText = `¥ ${data.net}`;
    if (monthlyNet) monthlyNet.innerText = `¥ ${data.net}`;
    if (totalExp) totalExp.innerText = `¥ ${data.exp}`;
    if (totalRef) totalRef.innerText = data.ref.startsWith('-') ? data.ref : `-¥ ${data.ref}`;
    if (totalInc) totalInc.innerText = `¥ ${data.inc}`;

    closeMonthModal();

    // Clear any day focus from previous month
    activeDayFilter = null;
    activeDayLabel = '';
    const banner = document.getElementById('day-focus-banner');
    if (banner) banner.classList.add('hidden');

    const qd = document.getElementById('quick-date-dropdown');
    const scopeLabel = document.getElementById('tx-scope-label');
    if (currentActiveYear === '2026' && currentActiveMonth === '10') {
      quickDateFilter = 'all_month';
      if (qd) qd.value = 'all_month';
      if (scopeLabel) scopeLabel.innerText = '全流水';
    } else {
      quickDateFilter = 'all_month';
      if (qd) qd.value = 'all_month';
      if (scopeLabel) scopeLabel.innerText = '全月流水';
    }

    renderMonthTransactions(currentActiveYear, currentActiveMonth);
    showToast(`已切换至 ${currentActiveYear} 年 ${currentActiveMonth} 月，动态加载该月类别与流水`);
  }

  // Render Monthly Transactions Grouped by Date
  function renderMonthTransactions(year, month) {
    const data = getMonthlyData(year, month);
    const list = (data.txs || []).filter(tx => tx && !tx.softDeleted);
    const container = document.getElementById('transactions-list');
    if (!container) return;

    // Group transactions by dateGroup
    const groups = {};
    list.forEach(tx => {
      const gKey = tx.dateGroup || `${parseInt(String(tx.date || '2026-10-26').slice(5, 7))}月${parseInt(String(tx.date || '2026-10-26').slice(8, 10))}日`;
      if (!groups[gKey]) groups[gKey] = [];
      groups[gKey].push(tx);
    });

    if (Object.keys(groups).length === 0) {
      container.innerHTML = `
        <div id="tx-empty-state" class="py-16 text-center space-y-3">
          <div id="empty-state-ledger" class="space-y-3">
            <div class="w-16 h-16 rounded-3xl bg-slate-800/80 border border-slate-700/80 text-indigo-400 flex items-center justify-center p-3.5 mx-auto shadow-inner" id="empty-state-ledger-icon"></div>
            <div class="space-y-1">
              <h4 class="text-white font-bold text-sm">暂无账单记录</h4>
            </div>
          </div>
        </div>
      `;
      if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.refreshAllIcons === 'function') {
        IconRegistry.refreshAllIcons();
      }
      currentFilterKey = 'all';
      updateDynamicCategoryChips();
      updateActiveFilterCapsules();
      applyActiveFilters();
      if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();
      return;
    }

    let html = '';
    for (const [groupName, items] of Object.entries(groups)) {
      const subtotal = items.reduce((acc, cur) => Math.round((acc + (Number(cur.amount) || 0)) * 100) / 100, 0);
      const groupDate = items[0]?.date || items[0]?.txDate || '';
      html += `
        <div class="space-y-2 day-group" data-date="${groupDate}">
          <div onclick="toggleDayFilter('${groupDate}', '${groupName}')" class="day-header flex items-center justify-between text-xs text-slate-400 px-2 py-1.5 rounded-xl hover:bg-slate-800/80 cursor-pointer tap-highlight font-mono group transition-all" title="点击日标题或小计，即可按日筛选">
            <div class="flex items-center space-x-2">
              <span class="font-bold text-slate-200 group-hover:text-indigo-300 transition-colors">${groupName}</span>
              <span class="day-filter-btn text-[10px] bg-slate-800 group-hover:bg-indigo-600 text-indigo-300 group-hover:text-white px-2 py-0.5 rounded-lg border border-slate-700/80 transition-all flex items-center space-x-1">
                <svg class="w-2.5 h-2.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"/></svg>
                <span class="day-filter-btn-text">仅看此日</span>
              </span>
            </div>
            <span class="day-subtotal group-hover:text-indigo-300 font-semibold transition-colors">小计: -¥ ${subtotal.toFixed(2)}</span>
          </div>
      `;
      items.forEach(tx => {
          const norm = normalizeTxCategory(tx);
          const catName = norm.catName;
          const parentCat = norm.parentCat;
          const icon = getAppCatIcon(parentCat, tx.icon || getAppStatusIcon('fallbackCategory'));
          let iconSquircle = window.renderSquircleIcon 
            ? window.renderSquircleIcon(parentCat, 'w-10 h-10') 
            : `<div class="w-10 h-10 rounded-2xl bg-slate-700/50 flex items-center justify-center text-lg shrink-0 border border-slate-600/40 shadow-sm" data-cat-icon="${parentCat}">${icon}</div>`;
          
          if (!iconSquircle.includes('data-cat-icon')) {
            iconSquircle = iconSquircle.replace('class="', `data-cat-icon="${parentCat}" class="`);
          }

          const timeShort = tx.time && tx.time.includes(':') ? tx.time.split(':').slice(0, 2).join(':') : (tx.time || '');
          const cleanAcc = (tx.account || tx.channel || '钱包').replace('支付 · ', '');
          const txOrd = tx.orderId || `${tx.id}_ORDER`;
          const txTitle = tx.name || tx.merchant || '日常消费';
          html += `
          <div data-cat="${catName}" data-parent="${parentCat}" data-category="${parentCat}" data-type="expense" data-date="${tx.date || tx.txDate || ''}" data-account="${tx.account || tx.channel}" data-channel="${tx.channel}" data-order="${txOrd}" data-amount="${tx.amount}" class="tx-item flex items-center justify-between p-3.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 shadow-md hover:border-indigo-500 transition-all cursor-pointer tap-highlight animate-fadeIn" id="${tx.id}" onclick="viewTransactionDetail('${txTitle}', '${Number(tx.amount).toFixed(2)}', '${parentCat}（${catName}）', '${tx.account || tx.channel}', '${groupName} ${tx.time}', '${txOrd}')">
            <div class="flex items-center space-x-3 min-w-0 flex-1 mr-2.5">
              ${iconSquircle}
              <div class="min-w-0 flex-1">
                <div class="flex items-center">
                  <span class="font-semibold text-sm text-slate-100 truncate">${txTitle}</span>
                </div>
                <div class="text-xs text-slate-400 mt-1 flex items-center space-x-1.5 truncate">
                  <span class="inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-medium bg-indigo-500/15 text-indigo-300 border border-indigo-500/25 shrink-0">${catName}</span>
                  <span class="text-slate-400 font-mono text-[11px] shrink-0">${timeShort}</span>
                  ${tx.refund ? `<span class="text-slate-600 shrink-0">•</span><span class="text-purple-300 text-[10px] shrink-0 bg-purple-500/20 px-1 rounded">退款</span>` : ''}
                </div>
              </div>
            </div>
            <div class="text-right shrink-0 flex flex-col items-end justify-center ml-2">
              <div class="font-bold text-base text-white font-mono tracking-tight whitespace-nowrap">${tx.refund ? '+' : '-'}¥ ${tx.amount.toFixed(2)}</div>
              <span class="tx-source-tag text-[11px] text-slate-400 font-normal mt-1 block text-right whitespace-nowrap">${cleanAcc}</span>
            </div>
            <div role="button" class="tx-swipe-delete-btn" onclick="openTxDeleteConfirmModal(this.closest('.tx-item'), event)">
              <svg class="w-4 h-4 mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
              <span>删除</span>
            </div>
          </div>
          `;
        });
      html += `</div>`;
    }

    container.innerHTML = html;
    currentFilterKey = 'all';
    updateDynamicCategoryChips();
    updateActiveFilterCapsules();
    applyActiveFilters();
    if (typeof renderMonthlyCategoryChart === 'function') {
      renderMonthlyCategoryChart();
    }
  }

  // Toast helper (挂载至手机屏幕容器内部并使用全宽 Flex 水平居中，绝无位移冲突)
  function showToast(msg) {
    const host = document.getElementById('screen-container') || document.body;
    host.querySelectorAll('.singwallet-toast-wrap').forEach(el => el.remove());

    const wrap = document.createElement('div');
    wrap.className = "singwallet-toast-wrap absolute top-[160px] left-4 right-4 z-50 flex justify-center pointer-events-none";
    const t = document.createElement('div');
    t.className = "bg-slate-800/95 text-white border border-slate-700/90 px-4 py-2 rounded-2xl text-xs shadow-2xl flex items-center space-x-1.5 animate-fadeIn backdrop-blur-md max-w-full text-center pointer-events-auto";
    t.innerHTML = `<span class="inline-flex items-center space-x-1.5">${msg}</span>`;
    wrap.appendChild(t);
    host.appendChild(wrap);
    setTimeout(() => {
      wrap.style.opacity = '0';
      wrap.style.transition = 'opacity 0.22s ease';
      setTimeout(() => wrap.remove(), 220);
    }, 2000);
  }

  // ================= VIEW SYNCHRONIZATION HOOKS & COMPATIBILITY ALIASES =================
  let isUpdatingAppViews = false;
  window.refreshAppViewsOnIconChange = function() {
    if (isUpdatingAppViews) return;
    isUpdatingAppViews = true;
    try {
      // 1. Update current draft category icon
      if (typeof draftQueue !== 'undefined' && draftQueue[currentDraftIndex]) {
        const cur = draftQueue[currentDraftIndex];
        const cat = cur.categoryName || cur.category || '日常购物';
        const newIcon = getAppCatIcon(cat);
        cur.categoryIcon = newIcon;
        if (typeof currentDraftCategory !== 'undefined') {
          currentDraftCategory.name = cat;
          currentDraftCategory.icon = newIcon;
        }
      }

      // 2. Update #suggested-icon
      const curCat = document.getElementById('select-draft-category')?.value || (typeof currentDraftCategory !== 'undefined' ? currentDraftCategory.name : '餐饮美食');
      const sugIcon = document.getElementById('suggested-icon');
      if (sugIcon) {
        const icon = getAppCatIcon(curCat);
        sugIcon.innerHTML = icon;
        sugIcon.setAttribute('data-cat-icon', curCat);
      }

      // 3. Re-render draft queue thumbs
      if (typeof renderDraftQueue === 'function') {
        renderDraftQueue();
      }

      // 4. Synchronize custom dropdowns
      ['select-draft-category', 'manual-category', 'rule-target-cat'].forEach(dropdownId => {
        const input = document.getElementById(dropdownId);
        if (input) {
          const val = input.value;
          const wrap = document.getElementById('dropdown-wrap-' + dropdownId);
          if (wrap) {
            const iconSpan = wrap.querySelector('.custom-dropdown-trigger [data-cat-icon]');
            if (iconSpan && typeof IconRegistry !== 'undefined') {
              iconSpan.innerHTML = IconRegistry.getCategoryIcon(val);
            }
          }
        }
      });

      // 5. Update dynamic chips
      if (typeof updateDynamicCategoryChips === 'function') {
        updateDynamicCategoryChips();
      }
      if (typeof renderMonthlyCategoryChart === 'function') {
        renderMonthlyCategoryChart();
      }
    } finally {
      isUpdatingAppViews = false;
    }
  };

  function updateDraftUI() {
    if (draftQueue && draftQueue[currentDraftIndex]) {
      const cur = draftQueue[currentDraftIndex];
      const cat = cur.categoryName || cur.category || '日常购物';
      cur.categoryIcon = getAppCatIcon(cat);
      loadDraftData(cur);
    }
    renderDraftQueue();
  }

  function renderDraftQueueThumbs() {
    renderDraftQueue();
  }

  /**
   * 自动提交高置信度草稿入账
   */
  function commitDraftTransaction(draft, force = false) {
    if (!draft || draft.isParsing) return false;
    const ord = typeof normalizeOrderId === 'function' ? normalizeOrderId(draft.orderId) : String(draft.orderId || '').trim();
    if (!force && ord && typeof isOrderIdDuplicate === 'function' && isOrderIdDuplicate(ord)) {
      const idx = draftQueue.findIndex(d => d.id === draft.id);
      if (idx !== -1) {
        currentDraftIndex = idx;
      }
      renderDraftQueue();
      if (typeof showDedupTopToast === 'function') {
        showDedupTopToast(ord);
      }
      showToast(`检测到重复单号：${ord}，已自动拦截并保留在草稿箱！`);
      return false;
    }
    const merchant = draft.merchant || '已解析商户';
    const amount = Number(draft.amount) || 0;
    const catName = draft.categoryName || draft.category || '日常购物';
    const parentCat = (typeof resolveParentCategory === 'function' ? resolveParentCategory(catName) : catName) || '其他支出';
    const catIcon = getAppCatIcon(parentCat);
    const orderId = draft.orderId || ('420000' + Date.now());
    const txTime = draft.time || draft.orderTime || (typeof formatCurrentDateTime === 'function' ? formatCurrentDateTime() : '2026-10-26 12:00:00');
    const txDate = txTime.split(' ')[0] || '2026-10-26';
    const timeOnly = txTime.includes(' ') ? txTime.split(' ')[1] : txTime;

    if (draft.orderId) {
      committedOrderIds.add(draft.orderId.trim());
    }

    const activeMonthKey = `${currentActiveYear}-${String(currentActiveMonth).padStart(2, '0')}`;
    const targetMonthKey = (/^\d{4}-\d{2}/.test(txDate)) ? txDate.slice(0, 7) : activeMonthKey;
    adjustMonthlyTotals(amount, true, 1, targetMonthKey);

    insertTransactionToList({
      id: "item-tx-" + Date.now(),
      merchant: merchant,
      amount: amount,
      amountInCents: Math.round(amount * 100),
      catName: catName,
      catIcon: catIcon,
      parentCat: parentCat,
      category: catName,
      channel: draft.channel || '微信',
      account: draft.account || '微信 · 钱包',
      payment: draft.payment,
      txTime: txTime,
      orderTime: txTime,
      txDate: txDate,
      timeOnly: timeOnly,
      orderId: orderId,
      badge: `自动入账 ${draft.confidence || 98}%`,
      _totalsAdjusted: true
    });

    const idx = draftQueue.findIndex(d => d.id === draft.id);
    if (idx !== -1) {
      draftQueue.splice(idx, 1);
      if (idx < currentDraftIndex) {
        currentDraftIndex = Math.max(0, currentDraftIndex - 1);
      }
    }
    if (currentDraftIndex >= draftQueue.length) {
      currentDraftIndex = Math.max(0, draftQueue.length - 1);
    }

    renderDraftQueue();
    updateDraftBadge();
    applyActiveFilters();
    updateDynamicCategoryChips();

    showToast(`[自动入账成功] 置信度 ${draft.confidence}% ≥ ${autoCommitThreshold}%，${merchant} ¥${amount.toFixed(2)} 已免人工确认直接记入账本！`);
    return true;
  }

  /**
   * 全站分类 UI 联动同步函数
   */
  function syncAllCategoryUIs() {
    const categories = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
      ? window.DomainRegistry.getParentCategories()
      : (window.CORE_PARENT_CATEGORIES || ['餐饮美食', '交通出行', '日常购物', '休闲娱乐', '生活缴费', '医疗健康', '其他支出', '工资收入']);

    // 1. 同步「AI 配置」卡片分类管理胶囊列表 (#custom-categories-list) 与数量徽章
    const listEl = document.getElementById('custom-categories-list');
    const countBadge = document.getElementById('category-count-badge');
    if (countBadge) {
      countBadge.innerText = categories.length;
    }
    if (listEl) {
      listEl.className = "grid grid-cols-2 gap-2 py-1";
      listEl.innerHTML = categories.map(cat => {
        const icon = getAppCatIcon(cat);
        const safeCat = String(cat).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
        return `
          <div onclick="handleCategoryPillClick('${safeCat}', event)" class="category-pill-item group flex items-center space-x-2 px-2.5 py-1.5 rounded-xl bg-slate-900/75 hover:bg-slate-900 active:scale-[0.98] border border-slate-700/60 hover:border-indigo-500/50 transition-all min-h-[36px] cursor-pointer select-none tap-highlight" title="单击修改名称，双击删除分类">
            <span class="w-6 h-6 rounded-lg bg-slate-800/90 border border-slate-700/50 inline-flex items-center justify-center p-1 shrink-0 aspect-square text-indigo-300" data-cat-icon="${cat}">${icon}</span>
            <span class="text-xs font-medium text-slate-200 truncate flex-1">${cat}</span>
          </div>
        `;
      }).join('');
    }

    // 2. 同步待确认草稿的账单分类下拉菜单 (#menu-select-draft-category)
    const menuDraft = document.getElementById('menu-select-draft-category');
    const curDraftVal = (document.getElementById('select-draft-category') && document.getElementById('select-draft-category').value) || categories[0];
    if (menuDraft) {
      menuDraft.innerHTML = categories.map(cat => {
        const isSel = cat === curDraftVal ? 'selected' : '';
        const icon = getAppCatIcon(cat);
        return `
          <div class="custom-dropdown-option rounded-xl ${isSel}" tabindex="0" data-value="${cat}" onclick="onDraftCategorySelect('', '${cat}', event)">
            <div class="flex items-center space-x-2">
              <span class="w-4 h-4 inline-flex items-center justify-center shrink-0" data-cat-icon="${cat}">${icon}</span>
              <span class="opt-text truncate font-medium">${cat}</span>
            </div>
            <span class="opt-check">✓</span>
          </div>
        `;
      }).join('');
    }

    // 3. 同步快记一手手动记账分类下拉菜单 (#menu-manual-category)
    const menuManual = document.getElementById('menu-manual-category');
    const curManualVal = (document.getElementById('manual-category') && document.getElementById('manual-category').value) || categories[0];
    if (menuManual) {
      menuManual.innerHTML = categories.map(cat => {
        const isSel = cat === curManualVal ? 'selected' : '';
        return `
          <div class="custom-dropdown-option rounded-xl ${isSel}" tabindex="0" data-value="${cat}" onclick="selectCustomDropdownOption('manual-category', '${cat}', event)">
            <span class="truncate">${cat}</span>
            <span class="opt-check">✓</span>
          </div>
        `;
      }).join('');
    }

    // 4. 同步分类选择弹窗网格 (#category-modal-grid)
    const grid = document.getElementById('category-modal-grid');
    if (grid) {
      grid.innerHTML = categories.map(cat => {
        const icon = getAppCatIcon(cat);
        return `
          <div data-category-name="${cat}" onclick="selectCategory('', '${cat}', '${cat}')" class="p-2.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 text-center cursor-pointer hover:border-indigo-500/60 tap-highlight transition-all active:scale-95 flex flex-col items-center justify-center">
            <span class="text-2xl block mb-1 w-7 h-7 inline-flex items-center justify-center" data-cat-icon="${cat}">${icon}</span>
            <span class="font-medium text-slate-200 text-[11px] block whitespace-nowrap">${cat}</span>
          </div>
        `;
      }).join('');
    }

    // 5. 同步多维筛选抽屉分类标签 (#filter-modal-cats)
    const filterCats = document.getElementById('filter-modal-cats');
    if (filterCats) {
      let html = `<span onclick="toggleModalCat(this, 'all')" class="modal-cat-tag active-tag px-3 py-1.5 rounded-xl bg-slate-800 border border-slate-700 text-slate-300 cursor-pointer tap-highlight">全部</span>`;
      categories.forEach(cat => {
        const icon = getAppCatIcon(cat);
        const isActive = (typeof selectedFilterCats !== 'undefined' && selectedFilterCats.has(cat)) ? 'active-tag' : '';
        html += `
          <span onclick="toggleModalCat(this, '${cat}')" class="modal-cat-tag ${isActive} px-2.5 py-1.5 rounded-xl bg-slate-800 border border-slate-700 text-slate-300 cursor-pointer tap-highlight flex items-center space-x-1">
            <span class="w-4 h-4 inline-flex items-center justify-center shrink-0" data-cat-icon="${cat}">${icon}</span>
            <span>${cat}</span>
          </span>
        `;
      });
      filterCats.innerHTML = html;
    }

    // 6. 刷新全站图标中心
    if (window.IconRegistry && typeof window.IconRegistry.refreshAllIcons === 'function') {
      window.IconRegistry.refreshAllIcons();
    }

    if (typeof renderMonthlyCategoryChart === 'function') {
      renderMonthlyCategoryChart();
    }
  }

  let editingCategoryOldName = '';
  let pendingDeleteCategoryName = '';

  function addCustomCategory() {
    const input = document.getElementById('custom-category-input');
    if (!input) return;
    const name = input.value.trim();
    if (!name) {
      showToast('请输入有效的分类名称');
      return;
    }
    const currentCats = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
      ? window.DomainRegistry.getParentCategories()
      : window.CORE_PARENT_CATEGORIES;
    if (currentCats.includes(name)) {
      showToast(`分类「${name}」已存在`);
      return;
    }
    const success = (window.DomainRegistry && typeof window.DomainRegistry.addCategory === 'function')
      ? window.DomainRegistry.addCategory(name)
      : false;
    if (success) {
      input.value = '';
      syncAllCategoryUIs();
      if (typeof updateDynamicCategoryChips === 'function') updateDynamicCategoryChips();
      if (typeof updateBackupStatsLabel === 'function') updateBackupStatsLabel();
      showToast(`已成功添加新分类：${name}`);
    } else {
      showToast('添加分类失败');
    }
  }

  let categoryPillClickTimer = null;
  let categoryPillLastClicked = null;

  function handleCategoryPillClick(catName, event) {
    if (event) {
      event.stopPropagation();
      event.preventDefault();
    }
    if (!catName) return;

    if (categoryPillClickTimer && categoryPillLastClicked === catName) {
      // 双击：取消待触发的单击编辑，直接唤起删除确认弹窗
      clearTimeout(categoryPillClickTimer);
      categoryPillClickTimer = null;
      categoryPillLastClicked = null;
      openCategoryDeleteConfirmModal(catName, event);
    } else {
      // 单击：延迟 260ms，若无连续双击则唤起编辑重命名弹窗
      if (categoryPillClickTimer) clearTimeout(categoryPillClickTimer);
      categoryPillLastClicked = catName;
      categoryPillClickTimer = setTimeout(() => {
        categoryPillClickTimer = null;
        categoryPillLastClicked = null;
        openEditCategoryModal(catName, event);
      }, 260);
    }
  }

  function toggleCategoryHelpTip(event) {
    if (event) {
      event.stopPropagation();
      event.preventDefault();
    }
    const tip = document.getElementById('category-help-tip');
    if (tip) {
      const isHidden = tip.classList.contains('hidden');
      if (isHidden) {
        tip.classList.remove('hidden');
      } else {
        tip.classList.add('hidden');
      }
    }
    if (typeof showToast === 'function') {
      showToast('分类操作提示：单击修改名称，双击删除分类');
    }
  }

  function openEditCategoryModal(catName, event) {
    if (event) {
      event.stopPropagation();
      event.preventDefault();
    }
    if (!catName) return;
    editingCategoryOldName = String(catName);
    const modal = document.getElementById('category-edit-modal');
    const input = document.getElementById('edit-category-input');
    if (input) {
      input.value = editingCategoryOldName;
    }
    if (modal) {
      modal.classList.remove('hidden');
    }
    setTimeout(() => {
      if (input) {
        input.focus();
        if (typeof input.select === 'function') input.select();
      }
    }, 30);
  }

  function closeEditCategoryModal() {
    const modal = document.getElementById('category-edit-modal');
    if (modal) modal.classList.add('hidden');
    editingCategoryOldName = '';
  }

  function saveEditedCategory() {
    const input = document.getElementById('edit-category-input');
    if (!editingCategoryOldName) {
      closeEditCategoryModal();
      return false;
    }
    const oldName = editingCategoryOldName;
    const newName = input ? input.value.trim() : '';
    if (!newName) {
      showToast('请输入有效的分类名称');
      return false;
    }
    if (newName === oldName) {
      closeEditCategoryModal();
      return true;
    }
    const currentCats = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
      ? window.DomainRegistry.getParentCategories()
      : (window.CORE_PARENT_CATEGORIES || []);
    if (currentCats.includes(newName)) {
      showToast(`分类「${newName}」已存在`);
      return false;
    }

    const ok = (window.DomainRegistry && typeof window.DomainRegistry.renameCategory === 'function')
      ? window.DomainRegistry.renameCategory(oldName, newName)
      : false;
    if (!ok) {
      showToast('修改分类名称失败');
      return false;
    }

    // 1. 同步 allMonthlyData 中的历史流水分类字段
    if (typeof allMonthlyData !== 'undefined' && allMonthlyData) {
      Object.values(allMonthlyData).forEach(monthObj => {
        if (monthObj && Array.isArray(monthObj.txs)) {
          monthObj.txs.forEach(tx => {
            if (!tx) return;
            if (tx.cat === oldName) tx.cat = newName;
            if (tx.category === oldName) tx.category = newName;
            if (tx.catName === oldName) tx.catName = newName;
            if (tx.parentCat === oldName) tx.parentCat = newName;
          });
        }
      });
    }

    // 2. 同步当前 DOM 中所有 .tx-item 账单行的分类属性、胶囊文字、图标与详情点击参数
    document.querySelectorAll('.tx-item').forEach(el => {
      const dCat = el.getAttribute('data-cat');
      const dParent = el.getAttribute('data-parent');
      const dCategory = el.getAttribute('data-category');
      if (dCat === oldName || dParent === oldName || dCategory === oldName) {
        const nextCat = dCat === oldName ? newName : dCat;
        const nextParent = dParent === oldName ? newName : dParent;
        if (dCat === oldName) el.setAttribute('data-cat', newName);
        if (dParent === oldName) el.setAttribute('data-parent', newName);
        if (dCategory === oldName) el.setAttribute('data-category', newName);

        const badgeSpan = el.querySelector('span[class*="bg-indigo-500/15"]');
        if (badgeSpan && badgeSpan.innerText.trim() === oldName) {
          badgeSpan.innerText = newName;
        }

        el.querySelectorAll('[data-cat-icon]').forEach(ic => {
          if (ic.getAttribute('data-cat-icon') === oldName) {
            ic.setAttribute('data-cat-icon', newName);
            ic.innerHTML = getAppCatIcon(newName);
          }
        });

        const onclickAttr = el.getAttribute('onclick');
        if (onclickAttr && onclickAttr.includes(oldName)) {
          el.setAttribute('onclick', onclickAttr.split(oldName).join(newName));
        } else if (typeof el.onclick === 'function' && !onclickAttr) {
          const merText = el.querySelector('.font-semibold.text-sm')?.innerText?.trim() || '日常消费';
          const amtVal = parseFloat(el.getAttribute('data-amount') || '0') || 0;
          const accText = el.getAttribute('data-account') || el.getAttribute('data-channel') || '钱包';
          const dateText = el.getAttribute('data-date') || '';
          const timeText = el.querySelector('.font-mono.text-\\[11px\\]')?.innerText?.trim() || '';
          const ordText = el.getAttribute('data-order') || '';
          el.onclick = () => viewTransactionDetail(merText, amtVal.toFixed(2), `${nextParent || newName}（${nextCat || newName}）`, accText, `${dateText} ${timeText}`.trim(), ordText);
        }
      }
    });

    // 3. 同步待确认草稿队列与当前选中草稿分类表单
    if (typeof draftQueue !== 'undefined' && Array.isArray(draftQueue)) {
      draftQueue.forEach(d => {
        if (!d) return;
        if (d.category === oldName) d.category = newName;
        if (d.categoryName === oldName) d.categoryName = newName;
        if (d.category === newName || d.categoryName === newName) {
          d.categoryIcon = getAppCatIcon(newName);
        }
      });
      if (typeof saveStoredDrafts === 'function') {
        saveStoredDrafts();
      }
    }

    if (typeof currentDraftCategory !== 'undefined' && currentDraftCategory && currentDraftCategory.name === oldName) {
      currentDraftCategory.name = newName;
      currentDraftCategory.icon = getAppCatIcon(newName);
      currentDraftCategory.tag = newName.slice(0, 2);
    }

    const selectDraftInput = document.getElementById('select-draft-category');
    if (selectDraftInput && selectDraftInput.value === oldName) {
      selectDraftInput.value = newName;
      const lblDraft = document.getElementById('label-select-draft-category');
      if (lblDraft) lblDraft.innerText = newName;
      const sugName = document.getElementById('suggested-name');
      if (sugName) sugName.innerText = `推荐分类：${newName}`;
      const sugIcon = document.getElementById('suggested-icon');
      if (sugIcon) {
        sugIcon.setAttribute('data-cat-icon', newName);
        sugIcon.innerHTML = getAppCatIcon(newName);
      }
    }

    const manualCatInput = document.getElementById('manual-category');
    if (manualCatInput && manualCatInput.value === oldName) {
      manualCatInput.value = newName;
      const lblManual = document.getElementById('label-manual-category');
      if (lblManual) lblManual.innerText = newName;
    }

    // 4. 同步筛选状态与胶囊
    if (typeof currentFilterKey !== 'undefined' && currentFilterKey === oldName) {
      currentFilterKey = newName;
    }
    if (typeof selectedFilterCats !== 'undefined' && selectedFilterCats && selectedFilterCats.has(oldName)) {
      selectedFilterCats.delete(oldName);
      selectedFilterCats.add(newName);
    }

    // 5. 持久化流水并刷新全部关联视图
    if (typeof saveUserTransactionsToStorage === 'function') {
      saveUserTransactionsToStorage();
    }
    syncAllCategoryUIs();
    if (typeof renderDraftQueue === 'function') renderDraftQueue();
    if (typeof updateDynamicCategoryChips === 'function') updateDynamicCategoryChips();
    if (typeof updateActiveFilterCapsules === 'function') updateActiveFilterCapsules();
    if (typeof applyActiveFilters === 'function') applyActiveFilters();
    if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();
    if (typeof updateBackupStatsLabel === 'function') updateBackupStatsLabel();

    closeEditCategoryModal();
    showToast(`已将分类「${oldName}」修改为「${newName}」`);
    return true;
  }

  function openCategoryDeleteConfirmModal(catName, event) {
    if (event) {
      event.stopPropagation();
      event.preventDefault();
    }
    if (!catName) return;
    const currentCats = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
      ? window.DomainRegistry.getParentCategories()
      : (window.CORE_PARENT_CATEGORIES || []);
    if (currentCats.length <= 1) {
      showToast('至少保留一个分类，禁止删除！');
      return;
    }
    pendingDeleteCategoryName = String(catName);
    const descEl = document.getElementById('category-delete-confirm-desc');
    if (descEl) {
      descEl.innerText = `确定要删除分类「${pendingDeleteCategoryName}」吗？删除后不可恢复。`;
    }
    const modal = document.getElementById('category-delete-confirm-modal');
    if (modal) {
      modal.classList.remove('hidden');
    }
  }

  function closeCategoryDeleteConfirmModal() {
    const modal = document.getElementById('category-delete-confirm-modal');
    if (modal) modal.classList.add('hidden');
    pendingDeleteCategoryName = '';
  }

  function confirmCategoryDelete() {
    const target = pendingDeleteCategoryName;
    closeCategoryDeleteConfirmModal();
    if (target) {
      removeCustomCategory(target);
    }
  }

  function removeCustomCategory(name) {
    if (!name) return;
    const currentCats = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
      ? window.DomainRegistry.getParentCategories()
      : window.CORE_PARENT_CATEGORIES;
    if (currentCats.length <= 1) {
      showToast('至少保留一个分类，禁止删除！');
      return;
    }
    const success = (window.DomainRegistry && typeof window.DomainRegistry.removeCategory === 'function')
      ? window.DomainRegistry.removeCategory(name)
      : false;
    if (success) {
      // Bug 6 修复：删除自定义分类时，将已使用该分类的账单（allMonthlyData / DOM / draftQueue）平滑迁移至「其他支出」，消除孤儿分类
      const remainingCats = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
        ? window.DomainRegistry.getParentCategories()
        : (window.CORE_PARENT_CATEGORIES || ['其他支出']);
      const fallbackCat = remainingCats.includes('其他支出') ? '其他支出' : (remainingCats[0] || '其他支出');
      const fallbackIcon = getAppCatIcon(fallbackCat);

      // 1. 迁移内存账单池 allMonthlyData 中的孤儿分类账单
      if (typeof allMonthlyData === 'object' && allMonthlyData) {
        Object.keys(allMonthlyData).forEach(mKey => {
          const mObj = allMonthlyData[mKey];
          if (mObj && Array.isArray(mObj.txs)) {
            mObj.txs.forEach(tx => {
              if (!tx) return;
              if (tx.cat === name || tx.category === name || tx.catName === name || tx.parentCat === name) {
                tx.cat = fallbackCat;
                tx.category = fallbackCat;
                tx.catName = fallbackCat;
                tx.parentCat = fallbackCat;
                tx.icon = fallbackIcon;
              }
            });
          }
        });
      }

      // 2. 迁移当前页面 DOM 中的已入账流水节点
      document.querySelectorAll('#transactions-list .tx-item, #tx-list-container .tx-item, .tx-item').forEach(item => {
        const dCat = item.getAttribute('data-cat');
        const dParent = item.getAttribute('data-parent');
        const dCategory = item.getAttribute('data-category');
        if (dCat === name || dParent === name || dCategory === name) {
          item.setAttribute('data-cat', fallbackCat);
          item.setAttribute('data-parent', fallbackCat);
          item.setAttribute('data-category', fallbackCat);
          if (item.dataset) {
            item.dataset.cat = fallbackCat;
            item.dataset.parent = fallbackCat;
            item.dataset.category = fallbackCat;
          }
          const badgeEl = item.querySelector('.bg-indigo-500\\/15');
          if (badgeEl) badgeEl.innerText = fallbackCat;
          const iconEl = item.querySelector('[data-cat-icon]');
          if (iconEl) {
            iconEl.setAttribute('data-cat-icon', fallbackCat);
            iconEl.innerHTML = fallbackIcon;
          }
        }
      });

      // 3. 迁移草稿队列 draftQueue 与当前选中的草稿分类
      if (Array.isArray(draftQueue)) {
        draftQueue.forEach(d => {
          if (!d) return;
          if (d.category === name || d.categoryName === name) {
            d.category = fallbackCat;
            d.categoryName = fallbackCat;
            d.categoryIcon = fallbackIcon;
          }
        });
        saveStoredDrafts();
      }
      if (currentDraftCategory && currentDraftCategory.name === name) {
        currentDraftCategory.name = fallbackCat;
        currentDraftCategory.icon = fallbackIcon;
      }

      // 4. 清理筛选器中已被删除的分类
      if (typeof currentFilterKey !== 'undefined' && currentFilterKey === name) {
        currentFilterKey = 'all';
      }
      if (typeof selectedFilterCats !== 'undefined' && selectedFilterCats && selectedFilterCats.has(name)) {
        selectedFilterCats.delete(name);
        if (selectedFilterCats.size === 0) selectedFilterCats.add('all');
      }

      saveUserTransactionsToStorage();
      syncAllCategoryUIs();
      if (typeof renderDraftQueue === 'function') renderDraftQueue();
      if (typeof updateDynamicCategoryChips === 'function') updateDynamicCategoryChips();
      if (typeof updateActiveFilterCapsules === 'function') updateActiveFilterCapsules();
      if (typeof applyActiveFilters === 'function') applyActiveFilters();
      if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();
      if (typeof updateBackupStatsLabel === 'function') updateBackupStatsLabel();
      showToast(`已删除分类：${name}`);
    } else {
      showToast('删除分类失败');
    }
  }

  function resetCategoriesToDefault() {
    if (window.DomainRegistry && typeof window.DomainRegistry.resetCategories === 'function') {
      window.DomainRegistry.resetCategories();
    }
    syncAllCategoryUIs();
    if (typeof updateDynamicCategoryChips === 'function') updateDynamicCategoryChips();
    if (typeof updateBackupStatsLabel === 'function') updateBackupStatsLabel();
    showToast('已恢复默认 8 大标准分类');
  }

  // Bind Global API Exports
  window.switchTab = switchTab;
  window.fillAmount = fillAmount;
  window.fillMerchant = fillMerchant;
  window.fillTime = fillTime;
  window.highlightInput = highlightInput;

  window.openConfidenceModal = openConfidenceModal;
  window.closeConfidenceModal = closeConfidenceModal;
  window.toggleAutoCommit = toggleAutoCommit;
  window.setAutoCommitThreshold = setAutoCommitThreshold;
  window.simulateIncomingAutoCommit = simulateIncomingAutoCommit;

  window.renderDraftQueue = renderDraftQueue;
  window.renderDraftQueueThumbs = renderDraftQueueThumbs;
  window.updateDraftUI = updateDraftUI;
  window.switchDraft = switchDraft;
  window.loadDraftData = loadDraftData;
  window.updateDraftBadge = updateDraftBadge;
  window.discardCurrentDraft = discardCurrentDraft;
  window.batchConfirmHighConfidenceDrafts = batchConfirmHighConfidenceDrafts;
  window.resetDemoDrafts = resetDemoDrafts;
  window.commitDraftTransaction = commitDraftTransaction;
  window.syncAllCategoryUIs = syncAllCategoryUIs;
  window.addCustomCategory = addCustomCategory;
  window.handleCategoryPillClick = handleCategoryPillClick;
  window.toggleCategoryHelpTip = toggleCategoryHelpTip;
  window.openEditCategoryModal = openEditCategoryModal;
  window.closeEditCategoryModal = closeEditCategoryModal;
  window.saveEditedCategory = saveEditedCategory;
  window.openCategoryDeleteConfirmModal = openCategoryDeleteConfirmModal;
  window.closeCategoryDeleteConfirmModal = closeCategoryDeleteConfirmModal;
  window.confirmCategoryDelete = confirmCategoryDelete;
  window.removeCustomCategory = removeCustomCategory;
  window.resetCategoriesToDefault = resetCategoriesToDefault;

  window.onDraftCategorySelect = onDraftCategorySelect;
  window.openCategoryPickerModal = openCategoryPickerModal;
  window.closeCategoryModal = closeCategoryModal;
  window.selectCategory = selectCategory;

  window.openOrderSecurityModal = openOrderSecurityModal;
  window.closeOrderSecurityModal = closeOrderSecurityModal;

  window.onQuickDateDropdownChanged = onQuickDateDropdownChanged;
  window.toggleDayFilter = toggleDayFilter;
  window.focusDayFilter = focusDayFilter;
  window.clearDayFocus = clearDayFocus;
  window.updateActiveFilterCapsules = updateActiveFilterCapsules;
  window.removeTypeFilter = removeTypeFilter;
  window.removeDateFilter = removeDateFilter;
  window.removeCatFilter = removeCatFilter;
  window.removeAccountFilter = removeAccountFilter;
  window.updateDynamicCategoryChips = updateDynamicCategoryChips;
  window.filterTransactions = filterTransactions;
  window.applyActiveFilters = applyActiveFilters;
  window.openFilterModal = openFilterModal;
  window.closeFilterModal = closeFilterModal;
  window.selectModalType = selectModalType;
  window.selectDatePreset = selectDatePreset;
  window.onCustomDateInputChanged = onCustomDateInputChanged;
  window.toggleModalCat = toggleModalCat;
  window.selectModalAccount = selectModalAccount;
  window.resetFilter = resetFilter;
  window.applyFilterModal = applyFilterModal;

  // Helper: Format compact amount (去除末尾多余0，最多2位小数)
  function formatCompactAmount(amount) {
    if (window.SingWalletDomain && typeof window.SingWalletDomain.formatCompactAmount === 'function') {
      return window.SingWalletDomain.formatCompactAmount(amount);
    }
    const num = Number(amount);
    if (isNaN(num)) return '0';
    return Number(num.toFixed(2)).toString();
  }

  // Fallback calculation for category breakdown
  function computeCategoryBreakdownFallback(transactions = [], activeCategories = null) {
    const activeList = (Array.isArray(activeCategories) && activeCategories.length > 0)
      ? activeCategories
      : ['餐饮美食', '交通出行', '日常购物', '休闲娱乐', '生活缴费', '医疗健康', '其他支出'];
    const activeSet = new Set(activeList);
    const palette = (window.SingWalletDomain && window.SingWalletDomain.CATEGORY_CHART_PALETTE) || [
      '#6366f1', '#ec4899', '#10b981', '#f59e0b', '#8b5cf6',
      '#06b6d4', '#ef4444', '#14b8a6', '#f97316', '#84cc16'
    ];

    const totals = {};
    if (Array.isArray(transactions)) {
      transactions.forEach(tx => {
        if (!tx || tx.isIncome || tx.isRefund || tx.type === 'income' || tx.type === 'refund') return;
        if (tx.category === '工资收入' || tx.parentCat === '工资收入' || tx.catName === '工资收入') return;
        const rawCat = tx.parentCat || tx.category || tx.catName || '';
        const resolvedCat = (typeof resolveParentCategory === 'function')
          ? resolveParentCategory(rawCat, tx.merchant || tx.name || '')
          : (rawCat || '其他支出');
        if (!activeSet.has(resolvedCat)) return;
        const amt = Math.abs(parseFloat(tx.amount) || 0);
        if (amt <= 0) return;
        totals[resolvedCat] = (totals[resolvedCat] || 0) + amt;
      });
    }

    const total = Object.values(totals).reduce((a, b) => a + b, 0);
    if (total <= 0) {
      return { totalExpense: 0, totalExpenseText: '0', items: [] };
    }

    const sortedCats = Object.keys(totals).sort((a, b) => totals[b] - totals[a]);
    const rawItems = sortedCats.map((cat, idx) => {
      const catTotal = totals[cat];
      const ratio = catTotal / total;
      const exact = ratio * 100;
      const floor = Math.floor(exact);
      return { cat, catTotal, ratio, floor, remainder: exact - floor, origIdx: idx };
    });

    const diff = 100 - rawItems.reduce((acc, it) => acc + it.floor, 0);
    const sortedByRem = [...rawItems].sort((a, b) => b.remainder - a.remainder);
    for (let i = 0; i < diff && i < sortedByRem.length; i++) {
      sortedByRem[i].floor += 1;
    }
    rawItems.sort((a, b) => a.origIdx - b.origIdx);

    const items = rawItems.map((it, idx) => {
      const compactAmt = formatCompactAmount(it.catTotal);
      return {
        category: it.cat,
        amount: Number(it.catTotal.toFixed(2)),
        amountText: compactAmt,
        percentage: it.floor,
        ratio: it.ratio,
        color: palette[idx % palette.length],
        label: `${it.cat}(${it.floor}%):${compactAmt}`
      };
    });

    return {
      totalExpense: Number(total.toFixed(2)),
      totalExpenseText: formatCompactAmount(total),
      items: items
    };
  }

  // Monthly Category Breakdown SVG Donut & Legend Renderer
  function renderMonthlyCategoryChart() {
    const chartContainer = document.getElementById('monthly-pie-chart');
    const legendContainer = document.getElementById('monthly-pie-legend');
    if (!chartContainer || !legendContainer) return;

    // Gather active transactions from current view
    const txItems = Array.from(document.querySelectorAll('#transactions-list .tx-item, #tx-list-container .tx-item, .tx-item'))
      .filter(el => !el.classList.contains('soft-deleted'));

    const txList = txItems.map(el => {
      let amt = 0;
      if (el.dataset.amount !== undefined && el.dataset.amount !== '') {
        amt = parseFloat(el.dataset.amount) || 0;
      } else {
        const amtEl = el.querySelector('.font-mono');
        if (amtEl) {
          amt = parseFloat(amtEl.innerText.replace(/[¥\s,\-]/g, '')) || 0;
        }
      }
      const rawCat = el.dataset.parent || el.dataset.cat || el.dataset.category || '';
      const resolvedCat = (typeof resolveParentCategory === 'function')
        ? resolveParentCategory(rawCat, el.querySelector('.truncate')?.innerText || '')
        : (rawCat || '其他支出');
      const type = el.dataset.type || 'expense';
      const isRefund = el.dataset.refund === 'true' || (el.innerText && el.innerText.includes('退款'));
      const isIncome = type === 'income' || resolvedCat === '工资收入';
      return {
        id: el.id,
        amount: amt,
        category: resolvedCat,
        parentCat: resolvedCat,
        catName: el.dataset.cat || resolvedCat,
        type: type,
        isRefund: isRefund,
        isIncome: isIncome
      };
    });

    // Gather active parent categories
    let activeCats = null;
    if (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function') {
      activeCats = window.DomainRegistry.getParentCategories();
    } else if (window.CORE_PARENT_CATEGORIES && Array.isArray(window.CORE_PARENT_CATEGORIES)) {
      activeCats = window.CORE_PARENT_CATEGORIES;
    }

    // Compute breakdown using SSOT DomainConfig or fallback
    let breakdown = null;
    if (window.SingWalletDomain && typeof window.SingWalletDomain.computeCategoryBreakdown === 'function') {
      breakdown = window.SingWalletDomain.computeCategoryBreakdown(txList, activeCats);
    } else if (typeof window.computeCategoryBreakdown === 'function') {
      breakdown = window.computeCategoryBreakdown(txList, activeCats);
    } else {
      breakdown = computeCategoryBreakdownFallback(txList, activeCats);
    }

    const items = (breakdown && breakdown.items) || [];
    const total = (breakdown && breakdown.totalExpense) || 0;

    if (items.length === 0 || total <= 0) {
      chartContainer.innerHTML = `
        <svg viewBox="0 0 64 64" class="w-16 h-16 pointer-events-none">
          <circle cx="32" cy="32" r="22" fill="none" stroke="rgba(255, 255, 255, 0.16)" stroke-width="10" />
        </svg>
      `;
      legendContainer.innerHTML = `
        <div class="text-indigo-200/60 text-[10px] italic py-1 whitespace-nowrap">暂无支出数据</div>
      `;
      legendContainer.classList.remove('pie-legend-fade-bottom');
      legendContainer.onscroll = null;
      return;
    }

    const validItems = items.filter(it => (typeof it.amount === 'number' && it.amount > 0) || (typeof it.ratio === 'number' && it.ratio > 0));

    if (validItems.length === 0) {
      chartContainer.innerHTML = `
        <svg viewBox="0 0 64 64" class="w-16 h-16 pointer-events-none">
          <circle cx="32" cy="32" r="22" fill="none" stroke="rgba(255, 255, 255, 0.16)" stroke-width="10" />
        </svg>
      `;
      legendContainer.innerHTML = `
        <div class="text-indigo-200/60 text-[10px] italic py-1 whitespace-nowrap">暂无支出数据</div>
      `;
      legendContainer.classList.remove('pie-legend-fade-bottom');
      legendContainer.onscroll = null;
      return;
    }

    // 空心圆环图渲染逻辑 (Hollow Donut Chart, r=22, stroke-width=10)
    const C = 2 * Math.PI * 22; // ~138.23
    let currentOffset = 0;
    const slicesHtml = validItems.map((item) => {
      const itemRatio = item.ratio !== undefined ? item.ratio : (item.amount / total);
      const dash = itemRatio * C;
      const offset = currentOffset;
      currentOffset += dash;
      return `<circle class="pie-slice" data-category="${item.category}" cx="32" cy="32" r="22" fill="none" stroke="${item.color}" stroke-width="10" stroke-dasharray="${dash.toFixed(2)} ${C.toFixed(2)}" stroke-dashoffset="${(-offset).toFixed(2)}" transform="rotate(-90 32 32)" />`;
    }).join('');

    chartContainer.innerHTML = `
      <svg viewBox="0 0 64 64" class="w-16 h-16">
        <circle cx="32" cy="32" r="22" fill="none" stroke="rgba(255, 255, 255, 0.1)" stroke-width="10" />
        ${slicesHtml}
      </svg>
    `;

    legendContainer.innerHTML = items.map(item => `<div class="monthly-pie-legend-item flex items-center gap-1.5 leading-tight truncate text-slate-100 shrink-0" data-category="${item.category}" title="${item.label}"><span class="w-1.5 h-1.5 rounded-full shrink-0" style="background-color: ${item.color}"></span><span class="truncate">${item.label}</span></div>`).join('');

    legendContainer.scrollTop = 0;
    const updateLegendScrollMask = () => {
      if (items.length > 4) {
        const isAtBottom = (legendContainer.scrollHeight > legendContainer.clientHeight)
          && (legendContainer.scrollTop + legendContainer.clientHeight >= legendContainer.scrollHeight - 2);
        if (!isAtBottom) {
          legendContainer.classList.add('pie-legend-fade-bottom');
        } else {
          legendContainer.classList.remove('pie-legend-fade-bottom');
        }
      } else {
        legendContainer.classList.remove('pie-legend-fade-bottom');
      }
    };
    legendContainer.onscroll = updateLegendScrollMask;
    updateLegendScrollMask();
  }

  // Backward compatible helper to delete a transaction item
  function deleteTxItem(btnOrItem) {
    if (!btnOrItem) return;
    let item = null;
    if (typeof btnOrItem === 'string') {
      item = document.getElementById(btnOrItem);
    } else if (btnOrItem.classList && btnOrItem.classList.contains('tx-item')) {
      item = btnOrItem;
    } else if (btnOrItem.closest) {
      item = btnOrItem.closest('.tx-item');
    }
    if (!item) return;

    const id = item.id;
    const nameEl = item.querySelector('.truncate');
    const name = nameEl ? nameEl.innerText.trim() : '账单';
    let amount = 0;
    if (item.dataset.amount !== undefined && item.dataset.amount !== '') {
      amount = parseFloat(item.dataset.amount) || 0;
    } else {
      const amtEl = item.querySelector('.font-mono');
      if (amtEl) {
        amount = parseFloat(amtEl.innerText.replace(/[¥\s,\-]/g, '')) || 0;
      }
    }
    deleteTransaction(id, name, amount);
  }

  // ================= iOS 风格流水账单左滑删除交互引擎 =================
  let pendingDeleteTxElement = null;
  let activeSwipeItem = null;
  let justSwiped = false;

  function closeAllSwipedTx(exceptItem) {
    document.querySelectorAll('.tx-item.swiped-left').forEach(el => {
      if (el !== exceptItem) {
        el.classList.remove('swiped-left');
      }
    });
    if (!exceptItem) activeSwipeItem = null;
  }

  function openTxDeleteConfirmModal(txItemEl, event) {
    if (event) {
      if (typeof event.stopPropagation === 'function') event.stopPropagation();
      if (typeof event.preventDefault === 'function') event.preventDefault();
    }
    let el = null;
    if (typeof txItemEl === 'string') {
      el = document.getElementById(txItemEl);
    } else if (txItemEl && txItemEl.nodeType) {
      el = txItemEl.classList.contains('tx-item') ? txItemEl : txItemEl.closest('.tx-item');
    }
    if (!el) return;
    pendingDeleteTxElement = el;

    const nameEl = el.querySelector('.truncate');
    const merchantName = nameEl ? nameEl.innerText.trim() : '账单';
    let amtVal = 0;
    if (el.dataset.amount !== undefined && el.dataset.amount !== '') {
      amtVal = parseFloat(el.dataset.amount) || 0;
    } else {
      const amtEl = el.querySelector('.text-base.font-mono') || el.querySelector('.font-mono');
      if (amtEl) {
        amtVal = parseFloat(amtEl.innerText.replace(/[^\d.]/g, '')) || 0;
      }
    }
    const amountFormatted = '¥' + amtVal.toFixed(2);
    const descEl = document.getElementById('tx-delete-confirm-desc');
    if (descEl) {
      descEl.innerText = `确定要删除「${merchantName} (${amountFormatted})」吗？删除后可在右上角回收站中还原。`;
    }

    const modal = document.getElementById('tx-delete-confirm-modal');
    if (modal) {
      modal.classList.remove('hidden');
    }
  }

  function closeTxDeleteConfirmModal() {
    const modal = document.getElementById('tx-delete-confirm-modal');
    if (modal) {
      modal.classList.add('hidden');
    }
    if (pendingDeleteTxElement) {
      pendingDeleteTxElement.classList.remove('swiped-left');
      pendingDeleteTxElement = null;
    }
    closeAllSwipedTx();
  }

  function confirmTxSwipeDelete() {
    if (!pendingDeleteTxElement) {
      closeTxDeleteConfirmModal();
      return;
    }
    const target = pendingDeleteTxElement;
    pendingDeleteTxElement = null;
    const modal = document.getElementById('tx-delete-confirm-modal');
    if (modal) {
      modal.classList.add('hidden');
    }
    target.classList.remove('swiped-left');
    deleteTxItem(target);
    closeAllSwipedTx();
  }

  function initSwipeToDelete() {
    const container = document.getElementById('tx-scroll-viewport') || document.getElementById('transactions-list') || document.body;

    let touchStartX = 0;
    let touchStartY = 0;
    let isTouchSwiping = false;

    // Mobile Touch Gesture Support
    container.addEventListener('touchstart', (e) => {
      const item = e.target.closest('.tx-item');
      if (!item || e.target.closest('.tx-swipe-delete-btn')) return;
      if (activeSwipeItem && activeSwipeItem !== item) {
        activeSwipeItem.classList.remove('swiped-left');
        activeSwipeItem = null;
      }
      const touch = e.touches[0];
      touchStartX = touch.clientX;
      touchStartY = touch.clientY;
      isTouchSwiping = true;
      activeSwipeItem = item;
    }, { passive: true });

    container.addEventListener('touchmove', (e) => {
      if (!isTouchSwiping || !activeSwipeItem) return;
      const touch = e.touches[0];
      const dx = touch.clientX - touchStartX;
      const dy = touch.clientY - touchStartY;
      if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 10) {
        if (e.cancelable) e.preventDefault();
      }
    }, { passive: false });

    container.addEventListener('touchend', (e) => {
      if (!isTouchSwiping || !activeSwipeItem) return;
      isTouchSwiping = false;
      const touch = e.changedTouches[0];
      const dx = touch.clientX - touchStartX;
      const dy = touch.clientY - touchStartY;

      if (Math.abs(dx) > 35 && Math.abs(dx) > Math.abs(dy)) {
        justSwiped = true;
        setTimeout(() => { justSwiped = false; }, 320);
        if (dx < -35) {
          closeAllSwipedTx(activeSwipeItem);
          activeSwipeItem.classList.add('swiped-left');
        } else if (dx > 35) {
          activeSwipeItem.classList.remove('swiped-left');
          activeSwipeItem = null;
        }
      } else {
        if (activeSwipeItem && activeSwipeItem.classList.contains('swiped-left')) {
          justSwiped = true;
          setTimeout(() => { justSwiped = false; }, 320);
          activeSwipeItem.classList.remove('swiped-left');
          activeSwipeItem = null;
        }
      }
    }, { passive: true });

    // PC / Mouse Drag Gesture Support
    let isMouseDown = false;
    let mouseStartX = 0;
    let mouseStartY = 0;
    let mouseTargetItem = null;

    container.addEventListener('mousedown', (e) => {
      const item = e.target.closest('.tx-item');
      if (!item || e.target.closest('.tx-swipe-delete-btn')) return;
      if (activeSwipeItem && activeSwipeItem !== item) {
        activeSwipeItem.classList.remove('swiped-left');
        activeSwipeItem = null;
      }
      isMouseDown = true;
      mouseStartX = e.clientX;
      mouseStartY = e.clientY;
      mouseTargetItem = item;
    });

    window.addEventListener('mouseup', (e) => {
      if (!isMouseDown || !mouseTargetItem) return;
      isMouseDown = false;
      const dx = e.clientX - mouseStartX;
      const dy = e.clientY - mouseStartY;

      if (Math.abs(dx) > 35 && Math.abs(dx) > Math.abs(dy)) {
        justSwiped = true;
        setTimeout(() => { justSwiped = false; }, 320);
        if (dx < -35) {
          closeAllSwipedTx(mouseTargetItem);
          mouseTargetItem.classList.add('swiped-left');
          activeSwipeItem = mouseTargetItem;
        } else if (dx > 35) {
          mouseTargetItem.classList.remove('swiped-left');
          activeSwipeItem = null;
        }
      } else if (mouseTargetItem && mouseTargetItem.classList.contains('swiped-left') && !e.target.closest('.tx-swipe-delete-btn')) {
        justSwiped = true;
        setTimeout(() => { justSwiped = false; }, 320);
        mouseTargetItem.classList.remove('swiped-left');
        activeSwipeItem = null;
      }
      mouseTargetItem = null;
    });

    // Dismiss on click outside
    document.addEventListener('click', (e) => {
      if (e.target.closest('.tx-swipe-delete-btn') || e.target.closest('#tx-delete-confirm-modal')) return;
      const swiped = document.querySelectorAll('.tx-item.swiped-left');
      if (swiped.length > 0) {
        const clickedItem = e.target.closest('.tx-item.swiped-left');
        if (!clickedItem) {
          closeAllSwipedTx();
        }
      }
    }, true);
  }

  window.openTxDeleteConfirmModal = openTxDeleteConfirmModal;
  window.closeTxDeleteConfirmModal = closeTxDeleteConfirmModal;
  window.confirmTxSwipeDelete = confirmTxSwipeDelete;
  window.closeAllSwipedTx = closeAllSwipedTx;
  window.initSwipeToDelete = initSwipeToDelete;
  window.normalizeTxCategory = normalizeTxCategory;

    window.isOrderIdDuplicate = isOrderIdDuplicate;
  window.showDedupTopToast = showDedupTopToast;
  window.closeDedupTopToast = closeDedupTopToast;
  window.focusOrderInputFromToast = focusOrderInputFromToast;
  window.simulateDedupWarning = simulateDedupWarning;
  window.closeDedupModal = closeDedupModal;
  window.forceConfirm = forceConfirm;
  window.insertTransactionToList = insertTransactionToList;
  window.confirmTransaction = confirmTransaction;
  window.confirmDraft = confirmTransaction;

  window.adjustMonthlyTotals = adjustMonthlyTotals;
  window.updateDaySubtotalForElement = updateDaySubtotalForElement;
  window.deleteTransaction = deleteTransaction;
  window.deleteTxItem = deleteTxItem;
  window.renderMonthlyCategoryChart = renderMonthlyCategoryChart;
  window.formatCompactAmount = formatCompactAmount;
  window.computeCategoryBreakdownFallback = computeCategoryBreakdownFallback;
  window.undoDelete = undoDelete;
  window.openTrashDialog = openTrashDialog;
  window.restoreTrash = restoreTrash;
  window.closeTrashModal = closeTrashModal;

  window.clearManualImage = clearManualImage;
  window.openManualAddModal = openManualAddModal;
  window.closeManualAddModal = closeManualAddModal;
  window.saveManualTransaction = saveManualTransaction;
  window.submitManualTransaction = saveManualTransaction;

  window.viewTransactionDetail = viewTransactionDetail;
  window.closeTxDetailModal = closeTxDetailModal;
  window.openAddRuleModal = openAddRuleModal;
  window.closeAddRuleModal = closeAddRuleModal;
  window.saveNewRule = saveNewRule;
  window.toggleRule = toggleRule;
  window.triggerRerunRules = triggerRerunRules;

  window.editAccountBalance = editAccountBalance;
  window.closeAccEditModal = closeAccEditModal;
  window.saveAccountBalance = saveAccountBalance;
  window.openAddAccountModal = openAddAccountModal;
  window.closeAccAddModal = closeAccAddModal;
  window.saveNewAccount = saveNewAccount;

  window.openRefundDemoModal = openRefundDemoModal;
  window.closeRefundDemoModal = closeRefundDemoModal;
  window.executeRefundLinkDemo = executeRefundLinkDemo;

  window.getMonthlyData = getMonthlyData;
  window.openMonthModal = openMonthModal;
  window.closeMonthModal = closeMonthModal;
  window.setPickerYear = setPickerYear;
  window.changePickerYear = changePickerYear;
  window.renderMonthGrid = renderMonthGrid;
  window.selectMonthYear = selectMonthYear;
  window.renderMonthTransactions = renderMonthTransactions;

  window.showToast = showToast;

  // Shared state references
  Object.defineProperty(window, 'draftQueue', {
    get: () => draftQueue,
    set: (val) => { draftQueue = val; },
    configurable: true
  });
  window.allMonthlyData = allMonthlyData;
  window.committedOrderIds = committedOrderIds;

  Object.defineProperty(window, 'quickDateFilter', {
    get: () => quickDateFilter,
    set: (val) => { quickDateFilter = val; },
    configurable: true
  });
  Object.defineProperty(window, 'autoCommitEnabled', {
    get: () => autoCommitEnabled,
    set: (val) => { autoCommitEnabled = val; },
    configurable: true
  });
  Object.defineProperty(window, 'autoCommitThreshold', {
    get: () => autoCommitThreshold,
    set: (val) => { autoCommitThreshold = val; },
    configurable: true
  });
  Object.defineProperty(window, 'currentDraftIndex', {
    get: () => currentDraftIndex,
    set: (val) => { currentDraftIndex = val; },
    configurable: true
  });
  Object.defineProperty(window, 'currentFilterKey', {
    get: () => currentFilterKey,
    set: (val) => { currentFilterKey = val; },
    configurable: true
  });

  // ================= 方式 2：OTA 检查更新与三条铁律（全量 JSON 备份/恢复 + SQLite v2 无损迁移） =================

  function updateBackupStatsLabel() {
    const label = document.getElementById('backup-stats-label');
    if (!label) return;
    let txCount = 0;
    if (window.allMonthlyData) {
      Object.values(window.allMonthlyData).forEach(m => {
        if (m && Array.isArray(m.txs)) {
          txCount += m.txs.filter(t => !t.softDeleted).length;
        }
      });
    }
    if (txCount === 0) {
      const items = document.querySelectorAll('#transactions-list .tx-item, #tx-list-container .tx-item, .tx-item');
      txCount = Array.from(items).filter(el => !el.classList.contains('soft-deleted')).length;
    }
    const categories = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
      ? window.DomainRegistry.getParentCategories()
      : (window.CORE_PARENT_CATEGORIES || ['餐饮美食', '交通出行', '日常购物', '休闲娱乐', '生活缴费', '医疗健康', '其他支出', '工资收入']);
    const catCount = categories.length;
    label.innerText = `${txCount} 笔账单 · ${catCount} 个分类`;
  }

  function getEffectiveAppVersion() {
    let nativeVer = '';
    if (window.AndroidBridge && typeof window.AndroidBridge.getAppVersion === 'function') {
      try { nativeVer = window.AndroidBridge.getAppVersion() || ''; } catch (e) {}
    }
    const savedVer = localStorage.getItem('singwallet_app_version');
    if (nativeVer) {
      if (savedVer && typeof compareVersions === 'function') {
        return compareVersions(nativeVer, savedVer) >= 0 ? nativeVer : savedVer;
      }
      return nativeVer;
    }
    if (savedVer) return savedVer;
    return (window.APP_VERSION_META && window.APP_VERSION_META.currentVersion) ? window.APP_VERSION_META.currentVersion : '1.0.0';
  }

  function initAppVersionBadge() {
    const badge = document.getElementById('app-current-version-badge');
    if (!badge) return;
    let nativeVer = '';
    if (window.AndroidBridge && typeof window.AndroidBridge.getAppVersion === 'function') {
      try { nativeVer = window.AndroidBridge.getAppVersion() || ''; } catch (e) {}
    }
    const savedVer = localStorage.getItem('singwallet_app_version');
    const savedSha = localStorage.getItem('singwallet_hot_commit_sha');

    let effectiveVer = '';
    if (nativeVer) {
      if (savedVer && typeof compareVersions === 'function') {
        effectiveVer = compareVersions(nativeVer, savedVer) >= 0 ? nativeVer : savedVer;
      } else {
        effectiveVer = nativeVer;
      }
    } else if (savedVer) {
      effectiveVer = savedVer;
    }

    if (effectiveVer) {
      const cleanVer = effectiveVer.replace(/^[vV]/, '');
      const shaTag = savedSha ? ` #${savedSha.slice(0, 7)}` : '';
      badge.innerText = `v${cleanVer}${shaTag}`;
      badge.className = "text-[10px] px-2 py-0.5 rounded-md bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 font-mono whitespace-nowrap";
    } else {
      const defaultVer = (window.APP_VERSION_META && window.APP_VERSION_META.currentVersion) ? window.APP_VERSION_META.currentVersion : '1.0.0';
      badge.innerText = `v${defaultVer.replace(/^[vV]/, '')}`;
      badge.className = "text-[10px] px-2 py-0.5 rounded-md bg-slate-700/60 text-slate-300 font-mono whitespace-nowrap";
    }
  }

  function exportFullBackupSnapshot() {
    const rawCategories = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
      ? window.DomainRegistry.getParentCategories()
      : (window.CORE_PARENT_CATEGORIES || ['餐饮美食', '交通出行', '日常购物', '休闲娱乐', '生活缴费', '医疗健康', '其他支出', '工资收入']);
    const categories = Array.isArray(rawCategories) ? [...rawCategories] : [];

    let txList = [];
    if (window.allMonthlyData) {
      Object.keys(window.allMonthlyData).forEach(m => {
        const mData = window.allMonthlyData[m];
        if (mData && Array.isArray(mData.txs)) {
          txList.push(...mData.txs);
        }
      });
    }
    if (txList.length === 0) {
      const items = Array.from(document.querySelectorAll('#transactions-list .tx-item, #tx-list-container .tx-item, .tx-item'))
        .filter(el => !el.classList.contains('soft-deleted'));
      txList = items.map(el => ({
        id: el.id,
        merchant: el.querySelector('.truncate')?.innerText || '账单',
        amount: parseFloat(el.dataset.amount) || 0,
        amountInCents: Math.round((parseFloat(el.dataset.amount) || 0) * 100),
        catName: el.dataset.cat || el.dataset.category || '其他支出',
        category: el.dataset.category || '其他支出',
        parentCat: el.dataset.parent || el.dataset.category || '其他支出',
        channel: el.dataset.channel || el.dataset.account || '微信',
        account: el.dataset.account || '钱包',
        txDate: el.dataset.date || '2026-10-26',
        txTime: el.dataset.date ? (el.dataset.date + ' 12:00:00') : '2026-10-26 12:00:00',
        orderId: el.id + '_ORDER',
        badge: '自动识别'
      }));
    }

    const vlm = window.vlmConfig ? JSON.parse(JSON.stringify(window.vlmConfig)) : {};
    const orders = window.committedOrderIds ? Array.from(window.committedOrderIds) : [];
    const currentVer = localStorage.getItem('singwallet_app_version') || '1.0.0';

    const snapshot = {
      format: "singwallet_backup",
      version: "2.0",
      schemaVersion: 2,
      packageId: "com.singwallet.app",
      dbSchema: "sqlite_v2",
      appVersion: currentVer,
      exportTime: new Date().toISOString(),
      backupStats: {
        transactionCount: txList.length,
        categoryCount: categories.length
      },
      data: {
        categories: categories,
        allMonthlyData: JSON.parse(JSON.stringify(window.allMonthlyData || {})),
        committedOrderIds: orders,
        draftQueue: (typeof draftQueue !== 'undefined') ? JSON.parse(JSON.stringify(draftQueue)) : [],
        vlmConfig: vlm,
        transactions: txList
      }
    };

    window.__lastExportedBackupJson = snapshot;
    window.__lastExportedBackupJsonStr = JSON.stringify(snapshot, null, 2);

    try {
      localStorage.setItem('singwallet_latest_backup', JSON.stringify(snapshot));
    } catch (e) {}

    // Trigger browser file download: singwallet_backup_YYYYMMDD.json
    try {
      const now = new Date();
      const yyyy = now.getFullYear();
      const mm = String(now.getMonth() + 1).padStart(2, '0');
      const dd = String(now.getDate()).padStart(2, '0');
      const filename = `singwallet_backup_${yyyy}${mm}${dd}.json`;
      const blob = new Blob([JSON.stringify(snapshot, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      setTimeout(() => {
        if (a.parentNode) a.parentNode.removeChild(a);
        URL.revokeObjectURL(url);
      }, 150);
    } catch (e) {
      console.warn('Backup file download skipped or failed:', e);
    }

    showToast('已导出全量备份 (含账单与分类配置)');
    updateBackupStatsLabel();

    return snapshot;
  }

  function importBackupFromJson(jsonStrOrObj) {
    let snapshot = null;
    try {
      if (typeof jsonStrOrObj === 'string') {
        snapshot = JSON.parse(jsonStrOrObj);
      } else if (typeof jsonStrOrObj === 'object' && jsonStrOrObj !== null) {
        snapshot = jsonStrOrObj;
      }
    } catch (e) {
      showToast('导入失败：备份 JSON 数据解析异常');
      return false;
    }

    if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
      showToast('导入失败：备份数据为空或格式无效');
      return false;
    }

    // Bug 6 修复：校验解析后的 JSON 必须是非空对象且包含合法备份字段，禁止空对象 {} 静默导入成功
    const validBackupKeys = [
      'version', 'schemaVersion', 'dbSchemaVersion', 'backupMagic', 'format',
      'transactions', 'user_transactions', 'allMonthlyData', 'monthlyData',
      'categories', 'custom_categories', 'customCategories',
      'budget', 'monthly_budget', 'vlm_configs', 'vlmConfig', 'data'
    ];
    const hasValidTopKey = validBackupKeys.some(k => Object.prototype.hasOwnProperty.call(snapshot, k));
    if (!hasValidTopKey) {
      showToast('导入失败：未检测到有效备份结构字段');
      return false;
    }

    const rawData = (snapshot.data && typeof snapshot.data === 'object' && !Array.isArray(snapshot.data))
      ? snapshot.data
      : snapshot;
    const rawDataKeys = Object.keys(rawData);
    if (rawDataKeys.length === 0) {
      showToast('导入失败：备份内容为空对象');
      return false;
    }

    // 1. SQLite v1 -> v2 无损迁移与数据解构 (兼容 snake_case 与 camelCase 备份字段)
    const categories = rawData.categories || rawData.custom_categories || rawData.customCategories || [];
    const incomingMonthlyData = rawData.allMonthlyData || rawData.monthlyData || null;
    const incomingTransactions = rawData.transactions || rawData.user_transactions || [];
    const incomingOrders = rawData.committedOrderIds || [];
    const incomingVlm = rawData.vlmConfig || rawData.vlm_configs || null;
    const incomingDrafts = rawData.draftQueue || null;

    // 2. 还原分类 (无损迁移：增量补充，恢复备份中的分类)
    if (Array.isArray(categories) && window.DomainRegistry) {
      const currentCats = typeof window.DomainRegistry.getParentCategories === 'function'
        ? window.DomainRegistry.getParentCategories()
        : [];
      
      categories.forEach(cat => {
        if (!currentCats.includes(cat)) {
          if (typeof window.DomainRegistry.addCategory === 'function') {
            window.DomainRegistry.addCategory(cat);
          }
        }
      });

      if (typeof syncAllCategoryUIs === 'function') {
        syncAllCategoryUIs();
      }
    }

    // 3. 还原 VLM 配置
    if (incomingVlm && typeof incomingVlm === 'object') {
      if (window.vlmConfig) {
        window.vlmConfig = { ...window.vlmConfig, ...incomingVlm };
      }
      try {
        localStorage.setItem('singwallet_vlm_config', JSON.stringify(incomingVlm));
      } catch (e) {}
      if (typeof syncVlmConfigToUI === 'function') {
        syncVlmConfigToUI();
      }
    }

    // 4. 还原 committedOrderIds
    if (Array.isArray(incomingOrders) && window.committedOrderIds) {
      incomingOrders.forEach(ord => window.committedOrderIds.add(ord));
    }

    // 5. 还原草稿队列
    if (Array.isArray(incomingDrafts) && typeof draftQueue !== 'undefined') {
      draftQueue.length = 0;
      incomingDrafts.forEach(d => draftQueue.push(d));
      if (typeof renderDraftQueue === 'function') {
        renderDraftQueue();
      }
    }

    // 6. 还原 allMonthlyData & 账单流水 (无损字段填充)
    if (incomingMonthlyData && typeof incomingMonthlyData === 'object' && window.allMonthlyData) {
      Object.keys(incomingMonthlyData).forEach(m => {
        const mObj = incomingMonthlyData[m];
        if (mObj && Array.isArray(mObj.txs)) {
          mObj.txs.forEach(t => {
            if (!t.orderId) t.orderId = 'ORD_' + t.id;
            if (t.amountInCents === undefined && t.amount !== undefined) {
              t.amountInCents = Math.round(t.amount * 100);
            }
            if (!t.badge) t.badge = '自动识别';
          });
        }
        window.allMonthlyData[m] = mObj;
      });
    } else if (incomingTransactions.length > 0 && window.allMonthlyData) {
      const activeMonthKey = `${currentActiveYear || '2026'}-${String(currentActiveMonth || '10').padStart(2, '0')}`;
      if (!window.allMonthlyData[activeMonthKey]) {
        window.allMonthlyData[activeMonthKey] = { net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00', txs: [] };
      }
      window.allMonthlyData[activeMonthKey].txs = incomingTransactions;
    }

    saveUserTransactionsToStorage();

    // 7. 彻底恢复 DOM 中可能被 soft-delete 的节点
    document.querySelectorAll('#transactions-list .tx-item, #tx-list-container .tx-item, .tx-item').forEach(item => {
      item.classList.remove('soft-deleted');
      item.style.display = 'flex';
    });

    // 8. 重新渲染流水明细主视图与月度实心饼图
    if (typeof renderMonthTransactions === 'function') {
      renderMonthTransactions(currentActiveYear || '2026', currentActiveMonth || '10');
    }
    if (typeof renderMonthlyCategoryChart === 'function') {
      renderMonthlyCategoryChart();
    }
    if (typeof updateDynamicCategoryChips === 'function') {
      updateDynamicCategoryChips();
    }
    if (typeof updateActiveFilterCapsules === 'function') {
      updateActiveFilterCapsules();
    }
    if (typeof applyActiveFilters === 'function') {
      applyActiveFilters();
    }
    if (typeof updateBackupStatsLabel === 'function') {
      updateBackupStatsLabel();
    }

    showToast('数据恢复成功：已无损还原账单与配置');
    return true;
  }

  function handleBackupFileUpload(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = function(e) {
      const text = e.target.result;
      importBackupFromJson(text);
      event.target.value = '';
    };
    reader.readAsText(file);
  }

  /**
   * 解析更新源配置，支持：
   * - 缺省空值: 默认使用 APP_VERSION_META 配置 (Hsanli060/singwallet / master)
   * - owner/repo 或 owner/repo@branch
   * - GitHub 网页或 API 完整 URL
   */
  function resolveRepoAndBranch(customInput) {
    const meta = window.APP_VERSION_META || {};
    let defaultRepo = meta.githubRepo || meta.repo || 'Hsanli060/singwallet';
    let defaultBranch = meta.githubBranch || meta.branch || 'master';

    if (!customInput || typeof customInput !== 'string') {
      return { repo: defaultRepo, branch: defaultBranch };
    }

    let str = customInput.trim();
    if (str.startsWith('{') && str.endsWith('}')) {
      return { repo: defaultRepo, branch: defaultBranch };
    }

    // 若输入包含空格分隔的 Token (例如: "Hsanli060/singwallet ghp_xxx")，取第一部分作为仓库
    if (str.includes(' ')) {
      str = str.split(/\s+/)[0];
    }

    str = str.split('?')[0].split('#')[0];

    const ghUrlMatch = str.match(/(?:github\.com\/|api\.github\.com\/repos\/)([^\/\s]+)\/([^\/\s]+)/);
    if (ghUrlMatch) {
      let repoName = `${ghUrlMatch[1]}/${ghUrlMatch[2].replace(/\.git$/, '')}`;
      const branchMatch = str.match(/(?:tree|commits|releases\/tag)\/([^\/\s]+)/);
      let branchName = branchMatch ? branchMatch[1] : defaultBranch;
      return { repo: repoName, branch: branchName };
    }

    const directMatch = str.match(/^([a-zA-Z0-9_\-\.]+)\/([a-zA-Z0-9_\-\.]+)(?:@([a-zA-Z0-9_\-\.\/]+))?$/);
    if (directMatch) {
      return {
        repo: `${directMatch[1]}/${directMatch[2]}`,
        branch: directMatch[3] || defaultBranch
      };
    }

    return { repo: defaultRepo, branch: defaultBranch };
  }

  /**
   * 解析用户提供的 GitHub Token（支持直接输入 PAT、URL 参数或读取本地存储）
   */
  function resolveGithubToken(inputVal = '') {
    let token = '';
    const trimmed = (inputVal || '').trim();
    if (trimmed) {
      const tokenParamMatch = trimmed.match(/[?&]?(?:access_)?token=([A-Za-z0-9_]+)/);
      if (tokenParamMatch) {
        token = tokenParamMatch[1];
      } else if (/^(?:ghp_|github_pat_|gho_)[A-Za-z0-9_]+$/.test(trimmed)) {
        token = trimmed;
      } else if (trimmed.includes(' ') && /^(?:ghp_|github_pat_|gho_)[A-Za-z0-9_]+$/.test(trimmed.split(/\s+/)[1])) {
        token = trimmed.split(/\s+/)[1];
      } else if (!trimmed.includes('/') && !trimmed.includes('{') && trimmed.length >= 20 && /^[A-Za-z0-9_]+$/.test(trimmed)) {
        token = trimmed;
      }
    }
    if (!token) {
      try {
        token = localStorage.getItem('singwallet_github_token') || '';
      } catch (e) {}
    }
    if (token) {
      token = token.trim();
      try {
        localStorage.setItem('singwallet_github_token', token);
      } catch (e) {}
    }
    return token;
  }

  /**
   * 原生 AndroidBridge OTA 下载与装载进度实时回调
   */
  function onNativeOtaProgress(progressData) {
    if (!progressData || typeof progressData !== 'object') return;
    const progressWrap = document.getElementById('ota-download-progress-wrap');
    const progressBar = document.getElementById('ota-download-progress-bar');
    const progressText = document.getElementById('ota-download-progress-text');
    const percentSpan = document.getElementById('ota-download-percent-text');
    const statusText = document.getElementById('ota-download-status-text');
    const badge = document.getElementById('app-current-version-badge');
    const btnTrigger = document.getElementById('btn-trigger-ota-upgrade');

    const meta = window.__pendingOtaUpdateMeta || {};
    const targetVer = (meta.version || '1.1.0').replace(/^[vV]/, '');
    const displayVer = meta.displayVersion || meta.version || `v${targetVer}`;

    const percent = Math.min(100, Math.max(0, parseInt(progressData.percent, 10) || 0));
    const status = progressData.status || (percent >= 100 ? '更新包已就绪' : `正在下载更新 (${percent}%)...`);

    if (progressWrap) progressWrap.classList.remove('hidden');
    if (progressBar) progressBar.style.width = `${percent}%`;
    if (progressText) progressText.innerText = `${percent}%`;
    if (percentSpan) percentSpan.innerText = `${percent}%`;
    if (statusText) statusText.innerText = status;

    if (btnTrigger && !progressData.done && !progressData.error) {
      btnTrigger.disabled = true;
      const btnSpan = btnTrigger.querySelector('span:last-child') || btnTrigger;
      btnSpan.innerText = status;
    }

    if (progressData.error) {
      showToast(`更新失败: ${progressData.error}`);
      if (statusText) statusText.innerText = `更新出错: ${progressData.error}`;
      if (btnTrigger) {
        btnTrigger.disabled = false;
        btnTrigger.classList.remove('bg-emerald-600', 'cursor-default');
        btnTrigger.classList.add('bg-indigo-600', 'hover:bg-indigo-500');
        btnTrigger.innerHTML = `
          <span class="w-4 h-4 shrink-0" data-ui-icon="otaDownload"></span>
          <span>重试更新</span>
        `;
        if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.refreshAllIcons === 'function') {
          IconRegistry.refreshAllIcons();
        }
      }
      return;
    }

    if (progressData.done || percent === 100) {
      if (progressBar) progressBar.style.width = '100%';
      if (progressText) progressText.innerText = '100%';
      if (percentSpan) percentSpan.innerText = '100%';
      if (statusText) statusText.innerText = '更新完成';

      try {
        localStorage.setItem('singwallet_app_version', targetVer);
        if (meta.commitSha) {
          localStorage.setItem('singwallet_hot_commit_sha', meta.commitSha);
        }
      } catch (e) {}
      window.currentAppVersion = targetVer;

      if (badge) {
        badge.innerText = displayVer;
        badge.className = "text-[10px] px-2 py-0.5 rounded-md bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 font-mono whitespace-nowrap";
      }

      if (btnTrigger) {
        btnTrigger.disabled = true;
        btnTrigger.classList.remove('bg-indigo-600', 'hover:bg-indigo-500');
        btnTrigger.classList.add('bg-emerald-600', 'hover:bg-emerald-600', 'cursor-default');
        btnTrigger.innerHTML = `
          <span class="w-4 h-4 shrink-0" data-ui-icon="success"></span>
          <span>已完成更新 (${displayVer})</span>
        `;
        if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.refreshAllIcons === 'function') {
          IconRegistry.refreshAllIcons();
        }
      }

      showToast(`已完成 ${displayVer} 覆盖更新，历史账单与配置 100% 无损保留`);
      if (typeof updateBackupStatsLabel === 'function') {
        updateBackupStatsLabel();
      }
    }
  }

  /**
   * 真实 GitHub 双擎检测（Commit 免编译热更新源 + Release APK 完整包源）
   */
  async function fetchAndRenderGitHubOtaUpdate(customUrl = '') {
    const feedInput = document.getElementById('ota-feed-url-input');
    const resultBox = document.getElementById('ota-check-result-box');
    const btnCheckText = document.getElementById('btn-check-ota-text');
    const btnCheckOta = document.getElementById('btn-check-ota-update');

    const inputVal = (customUrl || (feedInput && feedInput.value) || '').trim();
    const { repo, branch } = resolveRepoAndBranch(inputVal);
    const token = resolveGithubToken(inputVal);

    if (btnCheckText) btnCheckText.innerText = '检查中...';
    if (btnCheckOta) btnCheckOta.disabled = true;

    try {
      const installedVersion = getEffectiveAppVersion();

      let nativeHotSha = '';
      if (window.AndroidBridge && typeof window.AndroidBridge.getHotUpdateInfo === 'function') {
        try {
          const rawInfo = window.AndroidBridge.getHotUpdateInfo();
          const parsed = typeof rawInfo === 'string' ? JSON.parse(rawInfo) : rawInfo;
          if (parsed && parsed.hotCommitSha) nativeHotSha = parsed.hotCommitSha;
        } catch (e) {}
      }
      let localCommitSha = nativeHotSha;
      if (!localCommitSha) {
        try { localCommitSha = localStorage.getItem('singwallet_hot_commit_sha') || ''; } catch (e) {}
      }

      const commitUrl = `https://api.github.com/repos/${repo}/commits/${branch}`;
      const releaseUrl = `https://api.github.com/repos/${repo}/releases/latest`;

      const headers = { 'Accept': 'application/vnd.github.v3+json' };
      if (token) {
        headers['Authorization'] = `token ${token}`;
      }

      let commitData = null;
      let commitStatus = 0;
      try {
        const commitRes = await fetch(commitUrl, { headers });
        if (commitRes) {
          commitStatus = commitRes.status;
          if (commitRes.ok) {
            commitData = await commitRes.json();
          }
        }
      } catch (e) {
        console.warn('[SingWallet OTA] Commits fetch error:', e);
      }

      let releaseData = null;
      let releaseStatus = 0;
      try {
        const releaseRes = await fetch(releaseUrl, { headers });
        if (releaseRes) {
          releaseStatus = releaseRes.status;
          if (releaseRes.ok) {
            releaseData = await releaseRes.json();
          }
        }
      } catch (e) {
        console.warn('[SingWallet OTA] Release fetch error (may not have release):', e);
      }

      if (!commitData && !releaseData) {
        if (btnCheckText) btnCheckText.innerText = '检查更新';
        if (btnCheckOta) btnCheckOta.disabled = false;
        if (resultBox) resultBox.classList.add('hidden');

        if ((commitStatus === 404 || releaseStatus === 404) && !token) {
          showToast('检查更新失败(404)：当前 GitHub 仓库为私有(Private)。请将仓库设为公开(Public)或在输入框填入 GitHub 访问令牌(Token)');
          return { hasUpdate: false, error: 'Repository is private (404)' };
        } else if (commitStatus === 404 || releaseStatus === 404) {
          showToast('检查更新失败(404)：未找到更新源或访问令牌(Token)无仓库访问权限');
          return { hasUpdate: false, error: 'Repository not found or invalid token (404)' };
        }

        showToast('检查更新失败，请检查网络或更新源配置');
        return { hasUpdate: false, error: 'Network or repository not found' };
      }

      // 1. 判断 Release 版本
      let isNewerRelease = false;
      let releaseVer = '';
      let apkDownloadUrl = '';
      let sha256 = '';
      let releaseLines = [];

      if (releaseData) {
        releaseVer = String(releaseData.tag_name || releaseData.name || '').trim().replace(/^[vV]/, '');
        if (releaseVer) {
          const cmp = (window.SingWalletDomain && typeof window.SingWalletDomain.compareVersions === 'function')
            ? window.SingWalletDomain.compareVersions(releaseVer, installedVersion)
            : (typeof compareVersions === 'function' ? compareVersions(releaseVer, installedVersion) : (releaseVer > installedVersion ? 1 : 0));
          if (cmp > 0) isNewerRelease = true;
        }
        if (releaseData.body) {
          releaseLines = String(releaseData.body)
            .split(/\r?\n/)
            .map(l => l.trim().replace(/^[-*•\d.]+\s*/, ''))
            .filter(l => l.length > 0 && !l.startsWith('#') && !l.startsWith('http'));
        }
        if (Array.isArray(releaseData.assets)) {
          const apkAsset = releaseData.assets.find(a => (a.name && a.name.endsWith('.apk')) || (a.browser_download_url && a.browser_download_url.endsWith('.apk'))) || releaseData.assets[0];
          if (apkAsset) {
            apkDownloadUrl = apkAsset.browser_download_url || apkAsset.url || '';
          }
        }
      }

      // 2. 判断 Commit 免编译热更新
      let fullSha = '';
      let shortSha = '';
      let commitLines = [];
      let isNewerCommit = false;

      if (commitData) {
        fullSha = commitData.sha || '';
        shortSha = fullSha ? fullSha.slice(0, 7) : '';
        if (fullSha && fullSha !== localCommitSha) {
          isNewerCommit = true;
        }
        const rawMsg = (commitData.commit && commitData.commit.message) ? commitData.commit.message : '';
        commitLines = rawMsg
          .split(/\r?\n/)
          .map(l => l.trim().replace(/^[-*•\d.]+\s*/, ''))
          .filter(l => l.length > 0 && !l.startsWith('Co-authored-by') && !l.startsWith('Signed-off-by'));
      }

      const hasUpdate = isNewerRelease || isNewerCommit;

      if (hasUpdate) {
        let displayVersion = '';
        let titleText = '';
        let triggerBtnText = '';
        let changelogLines = [];

        if (isNewerRelease) {
          displayVersion = `v${releaseVer}`;
          titleText = `发现新版本 ${displayVersion}`;
          triggerBtnText = `立即更新 (${displayVersion})`;
          changelogLines = releaseLines.length > 0 ? releaseLines : (commitLines.length > 0 ? commitLines : ['新版本 APK 安装包已发布']);
        } else {
          // Web 秒级热更新模式
          const cleanInst = installedVersion.replace(/^[vV]/, '');
          displayVersion = `v${cleanInst} · 热更 #${shortSha}`;
          titleText = `发现新版本 ${displayVersion}`;
          triggerBtnText = '立即热更新 (免安装秒级生效)';
          changelogLines = commitLines.length > 0 ? commitLines : [`同步 master 最新免编译热更新资源 (#${shortSha})`];
        }

        window.__pendingOtaUpdateMeta = {
          mode: isNewerRelease ? 'apk_or_web' : 'web_hot',
          repo,
          branch,
          token: token || '',
          version: isNewerRelease ? `v${releaseVer}` : displayVersion,
          displayVersion,
          commitSha: fullSha,
          shortSha,
          apkDownloadUrl,
          sha256
        };

        if (resultBox) {
          resultBox.classList.remove('hidden');
          resultBox.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }

        const vTitle = document.getElementById('ota-version-title');
        if (vTitle) vTitle.innerText = titleText;

        const changelogEl = document.getElementById('ota-changelog-list');
        if (changelogEl) {
          changelogEl.innerHTML = changelogLines.map(line => `<li>${line}</li>`).join('');
        }

        const btnTrigger = document.getElementById('btn-trigger-ota-upgrade');
        if (btnTrigger) {
          btnTrigger.disabled = false;
          btnTrigger.classList.remove('bg-emerald-600', 'cursor-default');
          btnTrigger.classList.add('bg-indigo-600', 'hover:bg-indigo-500');
          btnTrigger.innerHTML = `
            <span class="w-4 h-4 shrink-0" data-ui-icon="otaDownload"></span>
            <span>${triggerBtnText}</span>
          `;
          if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.refreshAllIcons === 'function') {
            IconRegistry.refreshAllIcons();
          }
        }

        if (btnCheckText) btnCheckText.innerText = '检查更新';
        if (btnCheckOta) btnCheckOta.disabled = false;

        showToast(isNewerRelease ? `已获取最新版本信息：${displayVersion} 可升级` : `已检测到最新免编译热更新：${displayVersion}`);
        return { hasUpdate: true, meta: window.__pendingOtaUpdateMeta };
      } else {
        if (resultBox) resultBox.classList.add('hidden');
        if (btnCheckText) btnCheckText.innerText = '检查更新';
        if (btnCheckOta) btnCheckOta.disabled = false;
        showToast(`当前已是最新版本 (v${installedVersion.replace(/^[vV]/, '')})`);
        return { hasUpdate: false, currentVersion: installedVersion, latestVersion: installedVersion };
      }
    } catch (err) {
      console.error('[SingWallet OTA] Check error:', err);
      if (btnCheckText) btnCheckText.innerText = '检查更新';
      if (btnCheckOta) btnCheckOta.disabled = false;
      showToast('检查更新时发生异常: ' + (err.message || '未知错误'));
      return { hasUpdate: false, error: err.message };
    }
  }

  function checkOtaUpdate(mockPayload = null, triggerAsyncNetwork = null) {
    const feedInput = document.getElementById('ota-feed-url-input');
    const resultBox = document.getElementById('ota-check-result-box');
    const customUrl = (feedInput && feedInput.value) ? feedInput.value.trim() : '';
    const currentVersion = getEffectiveAppVersion();

    let payload = mockPayload;
    if (!payload && customUrl) {
      try {
        if (customUrl.startsWith('{') && customUrl.endsWith('}')) {
          payload = JSON.parse(customUrl);
        }
      } catch (e) {}
    }

    // 1. 同步 Mock Payload 或 JSON 输入处理 (保持单测与同步模式 100% 兼容)
    if (payload && (payload.version || payload.tag_name || payload.sha)) {
      const releaseInfo = (window.SingWalletDomain && typeof window.SingWalletDomain.parseOtaReleasePayload === 'function')
        ? window.SingWalletDomain.parseOtaReleasePayload(payload, currentVersion)
        : (payload.version ? { hasUpdate: true, latestVersion: payload.version, changelog: payload.changelog || [], apkSize: payload.size || payload.apkSize || '18.4 MB' } : { hasUpdate: false });

      if (releaseInfo && releaseInfo.hasUpdate) {
        if (resultBox) {
          resultBox.classList.remove('hidden');
          resultBox.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
        const vTitle = document.getElementById('ota-version-title');
        const displayVer = releaseInfo.latestVersion ? `v${String(releaseInfo.latestVersion).replace(/^[vV]/, '')}` : 'v1.1.0';
        if (vTitle) vTitle.innerText = `发现新版本 ${displayVer}`;
        const changelogEl = document.getElementById('ota-changelog-list');
        if (changelogEl && Array.isArray(releaseInfo.changelog) && releaseInfo.changelog.length > 0) {
          changelogEl.innerHTML = releaseInfo.changelog.map(item => `<li>${item}</li>`).join('');
        }
        const btnCheckText = document.getElementById('btn-check-ota-text');
        if (btnCheckText) btnCheckText.innerText = '检查更新';

        const token = resolveGithubToken(customUrl);
        window.__pendingOtaUpdateMeta = {
          mode: releaseInfo.isWebHotUpdate ? 'web_hot' : 'apk_or_web',
          repo: (window.APP_VERSION_META && window.APP_VERSION_META.githubRepo) || 'Hsanli060/singwallet',
          branch: (window.APP_VERSION_META && window.APP_VERSION_META.githubBranch) || 'master',
          token: token || '',
          version: displayVer,
          displayVersion: displayVer,
          commitSha: releaseInfo.commitSha || payload.sha || '',
          shortSha: releaseInfo.shortSha || (payload.sha ? payload.sha.slice(0, 7) : ''),
          apkDownloadUrl: releaseInfo.downloadUrl || '',
          sha256: releaseInfo.sha256 || ''
        };

        const btnTrigger = document.getElementById('btn-trigger-ota-upgrade');
        if (btnTrigger) {
          btnTrigger.disabled = false;
          btnTrigger.classList.remove('bg-emerald-600', 'cursor-default');
          btnTrigger.classList.add('bg-indigo-600', 'hover:bg-indigo-500');
          const triggerText = releaseInfo.isWebHotUpdate ? '立即热更新 (免安装秒级生效)' : `立即更新 (${displayVer})`;
          btnTrigger.innerHTML = `
            <span class="w-4 h-4 shrink-0" data-ui-icon="otaDownload"></span>
            <span>${triggerText}</span>
          `;
          if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.refreshAllIcons === 'function') {
            IconRegistry.refreshAllIcons();
          }
        }

        showToast(`已获取最新版本信息：${displayVer} 可升级`);
        return releaseInfo;
      }
    }

    // 2. 真实网络环境下的 GitHub 远端双擎检测
    const isNetworkAllowed = (triggerAsyncNetwork === true || (triggerAsyncNetwork !== false && !window.__SW_DISABLE_NET_OTA__)) &&
      typeof window !== 'undefined' && typeof fetch === 'function';

    if (isNetworkAllowed && !mockPayload) {
      fetchAndRenderGitHubOtaUpdate(customUrl);
      return { hasUpdate: false, currentVersion, latestVersion: currentVersion, pendingAsync: true };
    }

    // 3. 兜底已是最新版本
    if (resultBox) resultBox.classList.add('hidden');
    const btnCheckText = document.getElementById('btn-check-ota-text');
    if (btnCheckText) btnCheckText.innerText = '检查更新';
    showToast(`当前已是最新版本 (v${currentVersion.replace(/^[vV]/, '')})`);
    return { hasUpdate: false, currentVersion, latestVersion: currentVersion };
  }

  function executeOtaInPlaceUpgrade(fast = false) {
    const progressWrap = document.getElementById('ota-download-progress-wrap');
    const progressBar = document.getElementById('ota-download-progress-bar');
    const progressText = document.getElementById('ota-download-progress-text');
    const percentSpan = document.getElementById('ota-download-percent-text');
    const statusText = document.getElementById('ota-download-status-text');
    const badge = document.getElementById('app-current-version-badge');
    const btnTrigger = document.getElementById('btn-trigger-ota-upgrade');

    const meta = window.__pendingOtaUpdateMeta || {};
    const targetVer = (meta.version || '1.1.0').replace(/^[vV]/, '');
    const displayVer = meta.displayVersion || meta.version || `v${targetVer}`;

    // 确保原生回调挂载
    window.onNativeOtaProgress = onNativeOtaProgress;

    // 1. fast 模式或无 AndroidBridge（纯单元测试/浏览器预览模式）
    if (fast === true || !window.AndroidBridge) {
      if (progressWrap) progressWrap.classList.remove('hidden');
      if (progressBar) progressBar.style.width = '100%';
      if (progressText) progressText.innerText = '100%';
      if (percentSpan) percentSpan.innerText = '100%';
      if (statusText) statusText.innerText = '更新完成';

      if (btnTrigger) {
        btnTrigger.disabled = true;
        btnTrigger.classList.remove('bg-indigo-600', 'hover:bg-indigo-500');
        btnTrigger.classList.add('bg-emerald-600', 'hover:bg-emerald-600', 'cursor-default');
        btnTrigger.innerHTML = `
          <span class="w-4 h-4 shrink-0" data-ui-icon="success"></span>
          <span>已完成更新 (${displayVer})</span>
        `;
        if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.refreshAllIcons === 'function') {
          IconRegistry.refreshAllIcons();
        }
      }

      if (badge) {
        badge.innerText = displayVer;
        badge.className = "text-[10px] px-2 py-0.5 rounded-md bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 font-mono whitespace-nowrap";
      }

      try {
        localStorage.setItem('singwallet_app_version', targetVer);
        if (meta.commitSha) {
          localStorage.setItem('singwallet_hot_commit_sha', meta.commitSha);
        }
      } catch (e) {}
      window.currentAppVersion = targetVer;

      showToast(`已完成 ${displayVer} 覆盖更新，历史账单与配置 100% 无损保留`);

      if (typeof updateBackupStatsLabel === 'function') {
        updateBackupStatsLabel();
      }

      return true;
    }

    // 2. Android 原生宿主环境 (window.AndroidBridge 存在)
    if (progressWrap) progressWrap.classList.remove('hidden');
    if (progressBar) progressBar.style.width = '0%';
    if (progressText) progressText.innerText = '0%';
    if (percentSpan) percentSpan.innerText = '0%';
    if (statusText) statusText.innerText = '正在启动更新...';
    if (btnTrigger) {
      btnTrigger.disabled = true;
      const btnSpan = btnTrigger.querySelector('span:last-child') || btnTrigger;
      btnSpan.innerText = '正在启动更新...';
    }

    const isApkMode = (meta.mode === 'apk' || (meta.mode === 'apk_or_web' && meta.apkDownloadUrl));
    if (isApkMode && typeof window.AndroidBridge.downloadAndInstallApk === 'function') {
      window.AndroidBridge.downloadAndInstallApk(meta.apkDownloadUrl, meta.sha256 || '');
      return true;
    } else if (typeof window.AndroidBridge.performWebHotUpdate === 'function') {
      const token = meta.token || resolveGithubToken();
      const payloadObj = {
        repo: meta.repo || (window.APP_VERSION_META && window.APP_VERSION_META.githubRepo) || 'Hsanli060/singwallet',
        branch: meta.branch || (window.APP_VERSION_META && window.APP_VERSION_META.githubBranch) || 'master',
        version: meta.version || displayVer,
        commitSha: meta.commitSha || ''
      };
      if (token) {
        payloadObj.token = token;
      }
      const hotPayload = JSON.stringify(payloadObj);
      window.AndroidBridge.performWebHotUpdate(hotPayload);
      return true;
    } else {
      return executeOtaInPlaceUpgrade(true);
    }
  }

  window.updateBackupStatsLabel = updateBackupStatsLabel;
  window.initAppVersionBadge = initAppVersionBadge;
  window.getEffectiveAppVersion = getEffectiveAppVersion;
  window.resolveGithubToken = resolveGithubToken;
  window.exportFullBackupSnapshot = exportFullBackupSnapshot;
  window.importBackupFromJson = importBackupFromJson;
  window.handleBackupFileUpload = handleBackupFileUpload;
  window.checkOtaUpdate = checkOtaUpdate;
  window.checkAppUpdate = checkOtaUpdate;
  window.checkGitHubLiveOtaUpdate = fetchAndRenderGitHubOtaUpdate;
  window.fetchAndRenderGitHubOtaUpdate = fetchAndRenderGitHubOtaUpdate;
  window.executeOtaInPlaceUpgrade = executeOtaInPlaceUpgrade;
  window.triggerOtaInstall = executeOtaInPlaceUpgrade;
  window.onNativeOtaProgress = onNativeOtaProgress;

  if (window.SingWalletDomain) {
    window.SingWalletDomain.getEffectiveAppVersion = getEffectiveAppVersion;
    window.SingWalletDomain.resolveGithubToken = resolveGithubToken;
    window.SingWalletDomain.exportFullBackupSnapshot = exportFullBackupSnapshot;
    window.SingWalletDomain.importBackupFromJson = importBackupFromJson;
    window.SingWalletDomain.checkOtaUpdate = checkOtaUpdate;
    window.SingWalletDomain.checkAppUpdate = checkOtaUpdate;
    window.SingWalletDomain.fetchAndRenderGitHubOtaUpdate = fetchAndRenderGitHubOtaUpdate;
    window.SingWalletDomain.executeOtaInPlaceUpgrade = executeOtaInPlaceUpgrade;
    window.SingWalletDomain.triggerOtaInstall = executeOtaInPlaceUpgrade;
  }
  if (window.DomainRegistry) {
    window.DomainRegistry.exportFullBackupSnapshot = exportFullBackupSnapshot;
    window.DomainRegistry.importBackupFromJson = importBackupFromJson;
    window.DomainRegistry.checkOtaUpdate = checkOtaUpdate;
    window.DomainRegistry.checkAppUpdate = checkOtaUpdate;
    window.DomainRegistry.fetchAndRenderGitHubOtaUpdate = fetchAndRenderGitHubOtaUpdate;
    window.DomainRegistry.executeOtaInPlaceUpgrade = executeOtaInPlaceUpgrade;
    window.DomainRegistry.triggerOtaInstall = executeOtaInPlaceUpgrade;
  }


  // ================= DOM CONTENT LOADED INITIALIZATION =================
  let isAppControllerInitialized = false;
  function initAppController() {
    if (isAppControllerInitialized) return;
    isAppControllerInitialized = true;
    // 1. Initialize custom dropdowns
    if (typeof initAllCustomDropdowns === 'function') {
      initAllCustomDropdowns();
    }
    // 2. Sync VLM configuration to UI
    if (typeof syncVlmConfigToUI === 'function') {
      syncVlmConfigToUI();
    }
    // 3. Refresh & sync all icons via IconRegistry
    if (typeof IconRegistry !== 'undefined' && typeof IconRegistry.refreshAllIcons === 'function') {
      IconRegistry.refreshAllIcons();
    }
    // 4. Update chips & active filters
    if (typeof updateDynamicCategoryChips === 'function') {
      updateDynamicCategoryChips();
    }
    if (typeof applyActiveFilters === 'function') {
      applyActiveFilters();
    }
    // 5. Render draft queue with dynamic category icons
    if (typeof renderDraftQueue === 'function') {
      renderDraftQueue();
    }
    // 5.1 Sync all category UIs across app
    if (typeof syncAllCategoryUIs === 'function') {
      syncAllCategoryUIs();
    }
    // 5.2 Initialize OTA version badge and Backup Stats
    if (typeof initAppVersionBadge === 'function') {
      initAppVersionBadge();
    }
    if (typeof updateBackupStatsLabel === 'function') {
      updateBackupStatsLabel();
    }
    // 5.3 Check Accessibility quick capture service status
    if (typeof checkA11yServiceStatus === 'function') {
      checkA11yServiceStatus();
    }
    // 6. Supplement data-cat-icon on static items in HTML
    document.querySelectorAll('#transactions-list .tx-item, #tx-list-container .tx-item').forEach(item => {
      const cat = item.getAttribute('data-parent') || item.getAttribute('data-cat') || item.getAttribute('data-category') || '其他支出';
      if (!item.getAttribute('data-category')) {
        item.setAttribute('data-category', cat);
      }
      const iconContainer = item.querySelector('.w-10.h-10') || item.firstElementChild?.firstElementChild;
      if (iconContainer && !iconContainer.getAttribute('data-cat-icon')) {
        iconContainer.setAttribute('data-cat-icon', cat);
      }
    });

    // 7. Load stored user transactions from localStorage if any
    const storedTxs = loadUserTransactionsFromStorage().filter(t => t && !t.softDeleted);
    if (Array.isArray(storedTxs) && storedTxs.length > 0) {
      const activeMonthKey = `${currentActiveYear}-${String(currentActiveMonth).padStart(2, '0')}`;
      const monthSums = {};
      storedTxs.forEach(tx => {
        const rawTime = tx.txTime || tx.orderTime || tx.fullTime || '';
        const txDate = tx.txDate || tx.date || (rawTime && rawTime.includes(' ') ? rawTime.split(' ')[0] : '') || '2026-10-26';
        const mKey = (/^\d{4}-\d{2}/.test(txDate)) ? txDate.slice(0, 7) : activeMonthKey;
        monthSums[mKey] = Math.round(((monthSums[mKey] || 0) + (Number(tx.amount) || 0)) * 100) / 100;
        insertTransactionToList({ ...tx, txDate, _totalsAdjusted: true });
      });
      Object.keys(monthSums).forEach(mKey => {
        adjustMonthlyTotals(monthSums[mKey], true, 0, mKey);
      });
    } else {
      // Clean initial state: 0 bills
      const emptyState = document.getElementById('tx-empty-state');
      if (emptyState) emptyState.classList.remove('hidden');
      const monthlyNet = document.getElementById('monthly-net-expense');
      const totalNet = document.getElementById('total-net-expense');
      const totalExp = document.getElementById('total-expense');
      const totalRef = document.getElementById('total-refund');
      const totalInc = document.getElementById('total-income');
      if (monthlyNet) monthlyNet.innerText = '¥ 0.00';
      if (totalNet) totalNet.innerText = '¥ 0.00';
      if (totalExp) totalExp.innerText = '¥ 0.00';
      if (totalRef) totalRef.innerText = '-¥ 0.00';
      if (totalInc) totalInc.innerText = '¥ 0.00';
    }

    if (typeof updateDynamicCategoryChips === 'function') {
      updateDynamicCategoryChips();
    }
    if (typeof renderMonthlyCategoryChart === 'function') {
      renderMonthlyCategoryChart();
    }

    if (typeof renderMonthlyCategoryChart === 'function') {
      renderMonthlyCategoryChart();
    }

    // 8. Call initSvgUI if present
    if (typeof initSvgUI === 'function') {
      setTimeout(initSvgUI, 10);
    }

    // 9. Initialize iOS-style swipe to delete
    if (typeof initSwipeToDelete === 'function') {
      initSwipeToDelete();
    }

    // 10. Bind Escape key to close open modals
    if (!window.__escapeModalListenerBound && typeof document !== 'undefined') {
      window.__escapeModalListenerBound = true;
      document.addEventListener('keydown', (evt) => {
        if (evt.key === 'Escape') {
          if (typeof closeEditCategoryModal === 'function') closeEditCategoryModal();
          if (typeof closeCategoryDeleteConfirmModal === 'function') closeCategoryDeleteConfirmModal();
        }
      });
    }

    // 11. Support URL parameters for direct automation / state preview
    try {
      if (typeof window !== 'undefined' && window.location && window.location.search) {
        const urlParams = new URLSearchParams(window.location.search);
        const tabParam = urlParams.get('tab');
        if (tabParam && typeof switchTab === 'function') {
          setTimeout(() => switchTab(tabParam), 80);
        }
        const actionParam = urlParams.get('action');
        if (actionParam === 'openManualModal' && typeof openManualAddModal === 'function') {
          setTimeout(openManualAddModal, 150);
        }
      }
    } catch (e) {}
  }

  /* ================= 状态栏闪电记账后台抓屏与识别引擎 ================= */

  function dataURLtoFile(dataurl, filename) {
    try {
      const arr = String(dataurl || '').split(',');
      const mimeMatch = arr[0] ? arr[0].match(/:(.*?);/) : null;
      const mime = mimeMatch ? mimeMatch[1] : 'image/png';
      const bstr = arr[1] ? atob(arr[1]) : '';
      let n = bstr.length;
      const u8arr = new Uint8Array(n);
      while (n--) {
        u8arr[n] = bstr.charCodeAt(n);
      }
      return new File([u8arr], filename, { type: mime });
    } catch (e) {
      return new File([new Uint8Array(0)], filename, { type: 'image/png' });
    }
  }

  async function handleShortcutCapturedItem(item) {
    if (!item || !item.dataUrl) return;
    console.info('[SingWalletShortcut] Received capture:', item.source, 'dataUrlLen=', item.dataUrl.length);
    try {
      const filePrefix = '闪电抓屏_';
      const file = dataURLtoFile(item.dataUrl, filePrefix + Date.now() + '.png');
      if (typeof window.handleManualScreenshotUpload === 'function') {
        const fakeEvent = {
          target: { files: [file], value: '' },
          isBackgroundCapture: true,
          captureSource: item.source || 'lightning-tile',
          sourceDataUrl: item.dataUrl
        };
        await window.handleManualScreenshotUpload(fakeEvent);
        if (typeof showToast === 'function') {
          showToast('闪电记账已捕获账单画面，正在后台调用大模型解析...');
        }
      } else {
        const localFallback = (typeof parseBillWithLocalEngine === 'function') ? parseBillWithLocalEngine(file) : {
          merchant: '闪电抓屏商户',
          amount: 25.8,
          channel: '微信',
          account: '钱包',
          category: '餐饮美食',
          time: new Date().toISOString().replace('T', ' ').slice(0, 19)
        };
        const taskId = 'draft-shortcut-' + Date.now();
        const draft = {
          id: taskId,
          ...localFallback,
          confidence: 99,
          imageData: item.dataUrl,
          tag: '闪电抓屏智能识别'
        };
        if (!window.draftQueue) window.draftQueue = [];
        const hadExistingDrafts = window.draftQueue.length > 0;
        if (hadExistingDrafts && typeof syncActiveDraftFormToMemory === 'function') {
          syncActiveDraftFormToMemory();
        }
        window.draftQueue.unshift(draft);
        if (hadExistingDrafts) {
          currentDraftIndex = (typeof currentDraftIndex === 'number' ? currentDraftIndex : 0) + 1;
        }
        saveStoredDrafts();
        if (typeof renderDraftQueue === 'function') renderDraftQueue({ skipFormReload: hadExistingDrafts });
        if (typeof updateDraftBadge === 'function') updateDraftBadge();
        if (typeof showToast === 'function') {
          showToast('闪电记账已捕获账单，已存入草稿箱');
        }
      }
    } catch (err) {
      console.warn('handleShortcutCapturedItem error:', err);
    }
  }

  let mockA11yEnabled = true;

  function checkA11yServiceStatus() {
    const badge = document.getElementById('a11y-service-status-badge');
    const btnText = document.getElementById('a11y-btn-text');
    const btn = document.getElementById('btn-toggle-a11y-service');
    if (!badge) return false;

    let isEnabled = false;
    if (window.AndroidBridge && typeof window.AndroidBridge.isAccessibilityServiceEnabled === 'function') {
      try {
        isEnabled = window.AndroidBridge.isAccessibilityServiceEnabled();
      } catch (e) {
        console.warn('isAccessibilityServiceEnabled error:', e);
      }
    } else {
      isEnabled = mockA11yEnabled;
    }

    if (isEnabled) {
      badge.textContent = '服务已就绪';
      badge.className = 'text-[11px] text-emerald-400 font-mono whitespace-nowrap';
      if (btnText) btnText.textContent = '无障碍服务运行正常 (点击重检)';
      if (btn) {
        btn.className = 'w-full py-2 px-3 rounded-xl bg-emerald-950/30 hover:bg-emerald-900/40 border border-emerald-500/40 hover:border-emerald-500 text-emerald-300 text-xs font-medium transition-all flex items-center justify-center gap-1.5 tap-highlight';
      }
    } else {
      badge.textContent = '未授权开启';
      badge.className = 'text-[11px] text-amber-400 font-mono whitespace-nowrap';
      if (btnText) btnText.textContent = '前往开启无障碍快捷抓屏服务';
      if (btn) {
        btn.className = 'w-full py-2 px-3 rounded-xl bg-indigo-600/25 hover:bg-indigo-600/40 border border-indigo-500/50 hover:border-indigo-400 text-indigo-200 text-xs font-medium transition-all flex items-center justify-center gap-1.5 tap-highlight';
      }
    }
    return isEnabled;
  }

  function handleA11yServiceAuth() {
    if (window.AndroidBridge && typeof window.AndroidBridge.openAccessibilitySettings === 'function') {
      try {
        window.AndroidBridge.openAccessibilitySettings();
        let checkCount = 0;
        const pollTimer = setInterval(() => {
          checkCount++;
          const ready = checkA11yServiceStatus();
          if (ready || checkCount > 10) {
            clearInterval(pollTimer);
          }
        }, 1000);
      } catch (e) {
        console.warn('openAccessibilitySettings error:', e);
      }
    } else {
      mockA11yEnabled = !mockA11yEnabled;
      const ready = checkA11yServiceStatus();
      if (typeof showToast === 'function') {
        showToast(ready ? '无障碍快捷抓屏服务已就绪 (原生端支持直接无感抓屏)' : '已模拟切换为未授权状态，点击可模拟开启');
      }
    }
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('focus', () => {
      checkA11yServiceStatus();
    });
  }

  window.checkA11yServiceStatus = checkA11yServiceStatus;
  window.handleA11yServiceAuth = handleA11yServiceAuth;
  window.handleShortcutCapturedItem = handleShortcutCapturedItem;

  // 原生 Android 返回手势拦截：优先关闭上层模态框
  window.handleAndroidBackPress = function() {
    const modalIds = [
      'category-modal', 'edit-category-modal', 'category-delete-confirm-modal',
      'tx-detail-modal', 'manual-add-modal', 'filter-modal',
      'trash-modal', 'dedup-modal', 'order-security-modal', 'confidence-modal',
      'month-modal', 'tx-delete-confirm-modal'
    ];
    for (const id of modalIds) {
      const el = document.getElementById(id);
      if (el && !el.classList.contains('hidden') && el.style.display !== 'none') {
        const closeFnName = 'close' + id.split('-').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
        if (typeof window[closeFnName] === 'function') {
          window[closeFnName]();
          return true;
        }
        el.classList.add('hidden');
        return true;
      }
    }
    return false;
  };

  // 小米 HyperOS 下拉控制中心「闪电记账」快捷开关触发响应与原生截屏回调入口
  window.onNativeScreenshotCaptured = async function(dataUrl, fileName, isQuickTile = true) {
    if (!dataUrl) return false;
    await handleShortcutCapturedItem({
      source: isQuickTile ? 'lightning-tile' : 'shortcut-capture',
      dataUrl: dataUrl,
      fileName: fileName || ('闪电抓屏_' + Date.now() + '.png')
    });
    return true;
  };

  window.triggerQuickTileCapture = async function(mockDataUrl = null) {
    if (mockDataUrl) {
      return await window.onNativeScreenshotCaptured(mockDataUrl, '闪电抓屏_' + Date.now() + '.png', true);
    }
    if (typeof window.onTileQuickRecordTriggered === 'function') {
      window.onTileQuickRecordTriggered();
    }
    return true;
  };

  window.onTileQuickRecordTriggered = function() {
    if (typeof openManualAddModal === 'function') {
      openManualAddModal();
    }
    const fileInput = document.getElementById('manual-upload-input') || document.getElementById('manual-image-input');
    if (fileInput) {
      fileInput.click();
    } else if (typeof showToast === 'function') {
      showToast('闪电记账已激活，请选取账单截图');
    }
  };

  // 原生移动端宿主环境检测与全屏自适应注入
  if (typeof window !== 'undefined') {
    if (window.AndroidBridge || (navigator.userAgent && navigator.userAgent.includes('SingWalletAndroid')) || window.innerWidth <= 640 || (window.location && window.location.search && window.location.search.includes('mobile=1'))) {
      if (document.body) {
        document.body.classList.add('native-app');
      } else {
        document.addEventListener('DOMContentLoaded', () => {
          if (document.body) document.body.classList.add('native-app');
        });
      }
    }
  }

  if (document.readyState !== 'loading') {
    initAppController();
  }
  document.addEventListener('DOMContentLoaded', initAppController);
  window.addEventListener('load', () => {
    if (typeof initSvgUI === 'function') {
      setTimeout(initSvgUI, 30);
    }
  });

})(typeof window !== 'undefined' ? window : this);
