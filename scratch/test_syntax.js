
    // Tab Switching
    function switchTab(tabId) {
      if (typeof closeAllCustomDropdowns === 'function') closeAllCustomDropdowns();
      document.getElementById('view-transactions').classList.add('hidden');
      document.getElementById('view-drafts').classList.add('hidden');
      document.getElementById('view-rules').classList.add('hidden');

      document.getElementById('nav-btn-transactions').className = "flex flex-col items-center justify-center h-full text-slate-400 hover:text-white tap-highlight";
      document.getElementById('nav-btn-drafts').className = "relative flex flex-col items-center justify-center h-full text-slate-400 hover:text-white tap-highlight";
      document.getElementById('nav-btn-rules').className = "flex flex-col items-center justify-center h-full text-slate-400 hover:text-white tap-highlight";

      if (tabId === 'transactions') {
        document.getElementById('view-transactions').classList.remove('hidden');
        document.getElementById('nav-btn-transactions').className = "flex flex-col items-center justify-center h-full text-indigo-400 font-semibold tap-highlight";
      } else if (tabId === 'drafts') {
        document.getElementById('view-drafts').classList.remove('hidden');
        document.getElementById('nav-btn-drafts').className = "relative flex flex-col items-center justify-center h-full text-indigo-400 font-semibold tap-highlight";
      } else if (tabId === 'rules') {
        document.getElementById('view-rules').classList.remove('hidden');
        document.getElementById('nav-btn-rules').className = "flex flex-col items-center justify-center h-full text-indigo-400 font-semibold tap-highlight";
      }
    }

    // Touch-to-Fill OCR Boxes
    function fillAmount(amount) {
      document.getElementById('input-amount').value = amount;
      highlightInput('input-amount');
      showToast(`✨ OCR金额已自动提取回填: ¥${amount}`);
    }

    function fillMerchant(merchant) {
      document.getElementById('input-merchant').value = merchant;
      highlightInput('input-merchant');
      showToast(`✨ OCR商户名已自动提取回填: ${merchant}`);
    }

    function fillTime(time) {
      const el = document.getElementById('input-time');
      if (el) {
        el.value = time;
        highlightInput('input-time');
        showToast(`⏱️ OCR已填入交易时间: ${time}`);
      }
    }

    function highlightInput(id) {
      const el = document.getElementById(id);
      el.classList.add('ring-4', 'ring-emerald-400');
      setTimeout(() => el.classList.remove('ring-4', 'ring-emerald-400'), 800);
    }

    // Category Picker Modal with Active Highlighting
// ================= 多待确认草稿队列 & 高置信度免确认入账机制 =================
        let draftQueue = [
        {
          id: 'draft-bill-1',
          merchant: '杭州市拱墅区世臻便利店',
          merchantHeader: '世纪华购',
          amount: 70.00,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '日常购物',
          categoryIcon: '🛒',
          confidence: 95,
          rule: '智能分类 "日常购物" (置信度 95%)',
          orderId: '4200003143202610252738865252',
          time: '2026-10-25 13:29:53',
          imgSrc: 'bill_1.jpg',
          imgTitle: '📷 微信支付 · 世纪华购 (-¥70.00)',
          tag: '离线引擎识别'
        },
        {
          id: 'draft-bill-2',
          merchant: '淘宝平台商户',
          merchantHeader: '淘宝平台商户',
          amount: 15.77,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '日常购物',
          categoryIcon: '🛒',
          confidence: 98,
          rule: '规则命中 "淘宝*" -> 日常购物',
          orderId: '4500000566202610259735455478',
          merchantOrderNo: '1318060072610254387125221313',
          time: '2026-10-25 18:41:54',
          imgSrc: 'bill_2.jpg',
          imgTitle: '📷 微信支付 · 淘宝平台商户 (-¥15.77)',
          tag: '离线引擎识别'
        },
        {
          id: 'draft-bill-3',
          merchant: '杭州市拱墅区辰市早餐店',
          merchantHeader: '辰市早餐店',
          amount: 4.00,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '餐饮美食',
          categoryIcon: '🍔',
          confidence: 98,
          rule: '规则命中 "早餐店*" -> 餐饮美食',
          orderId: '4500000527202610268642917303',
          merchantOrderNo: 'SPS20261026080118661907348642',
          time: '2026-10-26 08:01:25',
          imgSrc: 'bill_3.jpg',
          imgTitle: '📷 微信支付 · 辰市早餐店 (-¥4.00)',
          tag: '离线引擎识别'
        },
        {
          id: 'draft-bill-4',
          merchant: '拼多多',
          merchantHeader: '拼多多',
          amount: 14.75,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '日常购物',
          categoryIcon: '🛒',
          confidence: 96,
          rule: '规则命中 "拼多多*" -> 日常购物',
          orderId: '4500000570202610254022722547',
          merchantOrderNo: 'XP1926102514101861805207000558',
          time: '2026-10-25 14:19:38',
          imgSrc: 'bill_4.jpg',
          imgTitle: '📷 微信支付 · 拼多多 (-¥14.75)',
          tag: '离线引擎识别'
        }
      ];
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
        showToast(`✅ 已开启高置信度免确认自动入账 (阈值: ≥${autoCommitThreshold}%)`);
      } else {
        showToast(`ℹ️ 已关闭自动入账，所有识别账单均需人工确认`);
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
      if (!autoCommitEnabled) {
        showToast(`⚠️ 当前未开启自动入账！账单已推入「草稿箱」待人工确认。`);
        draftQueue.push({
          id: 'draft-' + Date.now(),
          merchant: '星巴克甄选（国贸店）',
          amount: 38.00,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '休闲娱乐',
          categoryIcon: '☕',
          confidence: 99,
          rule: '内置商户规则 "星巴克*"',
          orderId: '420000' + Date.now(),
          time: '2026-10-26 15:45:00',
          imgTitle: '📷 微信支付截图预览',
          tag: '置信度 99%'
        });
        renderDraftQueue();
        updateDraftBadge();
        return;
      }

      // Auto-commit directly
      const merchant = '星巴克甄选（国贸店）';
      const amount = 38.00;
      const channel = '微信支付';
      const account = '微信钱包';
      const catName = '休闲娱乐';
      const catIcon = '☕';
      const parentCat = '休闲娱乐';
      const orderId = '420000' + Date.now();
      
      showToast(`🤖 [自动入账成功] 置信度 99% ≥ ${autoCommitThreshold}%，${merchant} ¥${amount.toFixed(2)} 已免人工确认直接记入账本！`);
      
      // Update totals
      const curExpense = parseFloat(document.getElementById('total-expense').innerText.replace(/[¥\s,]/g, '')) + amount;
      const curNet = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, '')) + amount;
      document.getElementById('total-expense').innerText = `¥ ${curExpense.toFixed(2)}`;
      document.getElementById('total-net-expense').innerText = `¥ ${curNet.toFixed(2)}`;

      insertTransactionToList({
        id: "item-tx-" + Date.now(),
        merchant: merchant,
        amount: amount,
        catName: catName,
        catIcon: catIcon,
        parentCat: parentCat,
        channel: channel,
        account: account,
        txTime: '2026-10-26 15:45:00',
        txDate: '2026-10-26',
        timeOnly: '15:45:00',
        orderId: orderId,
        badge: '🤖 自动入账 99%'
      });
      applyActiveFilters();
      updateDynamicCategoryChips();
      updateActiveFilterCapsules();
    }

    function renderDraftQueue() {
      const container = document.getElementById('draft-pills-container');
      const countEl = document.getElementById('draft-queue-count');
      const batchCountEl = document.getElementById('batch-high-count');
      const emptyState = document.getElementById('draft-empty-state');
      const draftContent = document.getElementById('draft-content-container');

      if (countEl) countEl.innerText = draftQueue.length;
      updateDraftBadge();

      if (draftQueue.length === 0) {
        if (container) container.innerHTML = '';
        if (emptyState) emptyState.classList.remove('hidden');
        if (draftContent) draftContent.classList.add('hidden');
        return;
      }

      if (emptyState) emptyState.classList.add('hidden');
      if (draftContent) draftContent.classList.remove('hidden');

      let highCount = draftQueue.filter(d => d.confidence >= autoCommitThreshold).length;
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
          return `
            <button onclick="switchDraft(${idx})" class="flex-shrink-0 px-3 py-1.5 rounded-xl ${borderClass} text-left transition-all tap-highlight flex items-center space-x-2">
              <span class="text-base">${draft.categoryIcon}</span>
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

      // Load current draft details into UI
      loadDraftData(draftQueue[currentDraftIndex]);
    }

    function switchDraft(idx) {
      if (idx >= 0 && idx < draftQueue.length) {
        currentDraftIndex = idx;
        renderDraftQueue();
      }
    }

    function loadDraftData(draft) {
      if (!draft) return;
      currentDraftCategory = {
        name: draft.categoryName,
        icon: draft.categoryIcon,
        tag: draft.categoryName.slice(0, 2)
      };

      // Screenshot canvas elements
      const ocrAmount = document.getElementById('draft-ocr-amount');
      const ocrMerchant = document.getElementById('draft-ocr-merchant');
      const ocrOrder = document.getElementById('draft-ocr-order');
      const ocrTime = document.getElementById('draft-ocr-time');
      const imgTitle = document.getElementById('draft-img-title');
      const imgStatus = document.getElementById('draft-img-status');

      if (ocrAmount) ocrAmount.innerText = `¥ ${draft.amount.toFixed(2)}`;
      if (ocrMerchant) ocrMerchant.innerText = `收款商户：${draft.merchant}`;
      if (ocrOrder) {
        ocrOrder.innerText = `单号: ${draft.orderId} (点此验真防重)`;
        ocrOrder.onclick = () => openOrderSecurityModal(draft.orderId);
      }
      if (ocrTime) {
        ocrTime.innerText = `支付时间: ${draft.time}`;
        ocrTime.style.cursor = 'pointer';
        ocrTime.title = '点击回填此交易时间';
        ocrTime.onclick = () => fillTime(draft.time);
      }
      if (imgTitle) imgTitle.innerText = draft.imgTitle;
      if (imgStatus) {
        imgStatus.innerText = draft.tag;
        imgStatus.className = draft.confidence >= 95 
          ? "text-emerald-400 font-mono text-[10px] bg-emerald-500/10 px-1.5 py-0.5 rounded border border-emerald-500/30"
          : "text-amber-400 font-mono text-[10px] bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/30";
      }

      // Inputs
      const inAmt = document.getElementById('input-amount');
      const inMer = document.getElementById('input-merchant');
      const inTime = document.getElementById('input-time');
      const selChan = document.getElementById('select-channel');
      const selAcc = document.getElementById('select-account');
      if (inAmt) inAmt.value = draft.amount.toFixed(2);
      if (inMer) inMer.value = draft.merchant;
      if (inTime) inTime.value = draft.time || '';
      if (selChan) selChan.value = draft.channel;
      if (selAcc) selAcc.value = draft.account;

      // Category card
      const sugIcon = document.getElementById('suggested-icon');
      const sugName = document.getElementById('suggested-name');
      const sugConf = document.getElementById('suggested-confidence-badge');
      const sugRule = document.getElementById('suggested-rule');
      if (sugIcon) sugIcon.innerText = draft.categoryIcon;
      if (sugName) sugName.innerText = `推荐分类：${draft.categoryName}`;
      if (sugConf) {
        sugConf.innerText = `置信度 ${draft.confidence}%`;
        sugConf.className = draft.confidence >= 95
          ? "text-[10px] bg-indigo-500 text-white px-1.5 py-0.2 rounded font-mono"
          : "text-[10px] bg-amber-500 text-white px-1.5 py-0.2 rounded font-mono";
      }
      if (sugRule) sugRule.innerText = `匹配规则：${draft.rule}`;
    }

    function updateDraftBadge() {
      const badge = document.getElementById('draft-badge');
      const dot = document.getElementById('draft-nav-dot');
      const count = draftQueue.length;
      if (badge) {
        if (count > 0) {
          badge.innerText = `待确认 ${count} 笔`;
          badge.className = "px-2.5 py-1 text-xs font-semibold rounded-full bg-amber-500/20 text-amber-300 border border-amber-500/30";
          if (dot) dot.style.display = 'block';
        } else {
          badge.innerText = `待确认 0 笔`;
          badge.className = "px-2.5 py-1 text-xs font-semibold rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30";
          if (dot) dot.style.display = 'none';
        }
      }
    }

    function discardCurrentDraft() {
      if (draftQueue.length === 0) return;
      const discarded = draftQueue[currentDraftIndex];
      draftQueue.splice(currentDraftIndex, 1);
      if (currentDraftIndex >= draftQueue.length) {
        currentDraftIndex = Math.max(0, draftQueue.length - 1);
      }
      showToast(`🗑️ 已丢弃草稿: ${discarded.merchant} (已移入草稿回收站)`);
      renderDraftQueue();
    }

    function batchConfirmHighConfidenceDrafts() {
      const highList = draftQueue.filter(d => d.confidence >= autoCommitThreshold);
      if (highList.length === 0) {
        showToast("当前待确认队列中没有 ≥" + autoCommitThreshold + "% 的高置信度草稿");
        return;
      }
      let totalAmt = 0;
      highList.forEach(draft => {
        totalAmt += draft.amount;
        const txTime = draft.time || '2026-10-26 12:00:00';
        const txDate = txTime.split(' ')[0] || '2026-10-26';
        const timeOnly = txTime.includes(' ') ? txTime.split(' ')[1] : txTime;
        const parentCat = resolveParentCategory(draft.categoryName);

        insertTransactionToList({
          id: 'item-tx-' + Date.now() + Math.random().toString(36).slice(2, 6),
          merchant: draft.merchant,
          amount: draft.amount,
          catName: draft.categoryName,
          catIcon: draft.categoryIcon,
          parentCat: parentCat,
          channel: draft.channel,
          account: draft.account,
          txTime: txTime,
          txDate: txDate,
          timeOnly: timeOnly,
          orderId: draft.orderId,
          badge: '批量入账'
        });
      });

      // Update total
      const curExpEl = document.getElementById('total-expense');
      const curNetEl = document.getElementById('total-net-expense');
      const curExpense = (curExpEl ? parseFloat(curExpEl.innerText.replace(/[¥\s,]/g, '') || 0) : 0) + totalAmt;
      const curNet = (curNetEl ? parseFloat(curNetEl.innerText.replace(/[¥\s,]/g, '') || 0) : 0) + totalAmt;
      if (curExpEl) curExpEl.innerText = '¥ ' + curExpense.toFixed(2);
      if (curNetEl) curNetEl.innerText = '¥ ' + curNet.toFixed(2);

      // Remove highList from draftQueue
      draftQueue = draftQueue.filter(d => d.confidence < autoCommitThreshold);
      currentDraftIndex = 0;
      renderDraftQueue();
      applyActiveFilters();
      updateDynamicCategoryChips();
      updateActiveFilterCapsules();
      showToast(`🎉 成功将 ${highList.length} 笔高置信度账单入账 (共 ¥${totalAmt.toFixed(2)})！`);
    }

    function resetDemoDrafts() {
      draftQueue = [
        {
          id: 'draft-bill-1',
          merchant: '杭州市拱墅区世臻便利店',
          merchantHeader: '世纪华购',
          amount: 70.00,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '日常购物',
          categoryIcon: '🛒',
          confidence: 95,
          rule: '智能分类 "日常购物" (置信度 95%)',
          orderId: '4200003143202610252738865252',
          time: '2026-10-25 13:29:51',
          imgSrc: 'bill_1.jpg',
          imgTitle: '📱 微信支付 • 世纪华购 (-¥70.00)',
          tag: '真实识别'
        },
        {
          id: 'draft-bill-2',
          merchant: '淘宝平台商户',
          merchantHeader: '淘宝平台商户',
          amount: 15.77,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '日常购物',
          categoryIcon: '🛒',
          confidence: 98,
          rule: '规则命中 "淘宝*" -> 日常购物',
          orderId: '4500000566202610259735455478',
          merchantOrderNo: '1318060072610254387125221313',
          time: '2026-10-25 18:41:54',
          imgSrc: 'bill_2.jpg',
          imgTitle: '📷 微信支付 · 淘宝平台商户 (-¥15.77)',
          tag: '离线引擎识别'
        },
        {
          id: 'draft-bill-3',
          merchant: '杭州市拱墅区辰市早餐店',
          merchantHeader: '辰市早餐店',
          amount: 4.00,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '餐饮美食',
          categoryIcon: '🍔',
          confidence: 98,
          rule: '规则命中 "早餐店*" -> 餐饮美食',
          orderId: '4500000527202610268642917303',
          merchantOrderNo: 'SPS20261026080118661907348642',
          time: '2026-10-26 08:01:25',
          imgSrc: 'bill_3.jpg',
          imgTitle: '📷 微信支付 · 辰市早餐店 (-¥4.00)',
          tag: '离线引擎识别'
        },
        {
          id: 'draft-bill-4',
          merchant: '拼多多',
          merchantHeader: '拼多多',
          amount: 14.75,
          channel: '微信支付',
          account: '微信钱包',
          categoryName: '日常购物',
          categoryIcon: '🛒',
          confidence: 96,
          rule: '规则命中 "拼多多*" -> 日常购物',
          orderId: '4500000570202610254022722547',
          merchantOrderNo: 'XP1926102514101861805207000558',
          time: '2026-10-25 14:19:38',
          imgSrc: 'bill_4.jpg',
          imgTitle: '📷 微信支付 · 拼多多 (-¥14.75)',
          tag: '离线引擎识别'
        }
      ];
      currentDraftIndex = 0;
      renderDraftQueue();
      showToast('🔄 已重置为 4 笔真实离线识别账单草稿');
    }

    let currentDraftCategory = {
      name: '餐饮美食',
      icon: '🍔',
      tag: '餐饮'
    };

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
      document.getElementById('category-modal').classList.add('hidden');
    }

    function selectCategory(icon, name, ruleText) {
      currentDraftCategory = {
        name: name,
        icon: icon,
        tag: name === '餐饮美食' ? '餐饮' : (name === '日常购物' ? '购物' : (name === '生活缴费' ? '缴费' : name.slice(0, 2)))
      };
      if (draftQueue[currentDraftIndex]) {
        draftQueue[currentDraftIndex].categoryName = name;
        draftQueue[currentDraftIndex].categoryIcon = icon;
        draftQueue[currentDraftIndex].rule = `用户指定分类: ${name}`;
      }
      document.getElementById('suggested-icon').innerText = icon;
      document.getElementById('suggested-name').innerText = `推荐分类：${name}`;
      document.getElementById('suggested-rule').innerText = `已手动指定：${name} (${ruleText})`;
      closeCategoryModal();
      showToast(`已更换分类为：${name}`);
      renderDraftQueue();
    }

    // Order ID Security Modal
    function openOrderSecurityModal(order) {
      document.getElementById('sec-order-val').innerText = order;
      document.getElementById('order-security-modal').classList.remove('hidden');
    }

    function closeOrderSecurityModal() {
      document.getElementById('order-security-modal').classList.add('hidden');
    }

    // 8 Core Parent Categories & Subcategory Mapping
    const subToParentCategoryMap = {
      // 餐饮美食
      '餐饮美食': '餐饮美食',
      '餐饮': '餐饮美食',
      '快餐简餐': '餐饮美食',
      '快餐': '餐饮美食',
      '咖啡饮品': '餐饮美食',
      '咖啡': '餐饮美食',
      '奶茶': '餐饮美食',
      '外卖': '餐饮美食',
      '小吃': '餐饮美食',
      '火锅': '餐饮美食',

      // 日常购物
      '日常购物': '日常购物',
      '日常超市': '日常购物',
      '超市': '日常购物',
      '便利店': '日常购物',
      '生鲜百货': '日常购物',
      '网购': '日常购物',
      '服饰数码': '日常购物',

      // 交通出行
      '交通出行': '交通出行',
      '交通': '交通出行',
      '打车出行': '交通出行',
      '打车': '交通出行',
      '地铁公交': '交通出行',
      '加油停车': '交通出行',

      // 休闲娱乐
      '休闲娱乐': '休闲娱乐',
      '娱乐': '休闲娱乐',
      '游戏充值': '休闲娱乐',
      '视频会员': '休闲娱乐',
      '电影演出': '休闲娱乐',

      // 生活缴费
      '生活缴费': '生活缴费',
      '缴费': '生活缴费',
      '水电气费': '生活缴费',
      '话费宽带': '生活缴费',
      '房租物业': '生活缴费',

      // 医疗健康
      '医疗健康': '医疗健康',
      '医疗': '医疗健康',
      '药品门诊': '医疗健康',
      '挂号体检': '医疗健康',

      // 其他支出
      '其他支出': '其他支出',
      '其他': '其他支出',

      // 工资收入
      '工资收入': '工资收入',
      '收入': '工资收入'
    };

    const parentCategoryIcons = {
      '餐饮美食': '🍔',
      '日常购物': '🛒',
      '交通出行': '🚗',
      '休闲娱乐': '🎮',
      '生活缴费': '⚡',
      '医疗健康': '💊',
      '其他支出': '📦',
      '工资收入': '💰'
    };

    function resolveParentCategory(cat) {
      if (!cat) return '其他支出';
      return subToParentCategoryMap[cat] || cat;
    }

    // Dynamic Filter Chips based strictly on PARENT Categories
    // Filter State Management
    let currentFilterKey = 'all'; // top chips filter key
    let quickDateFilter = 'all_month'; // 'today', 'yesterday', 'before_yesterday', '7days', 'all_month'
    let activeDayFilter = null; // 'YYYY-MM-DD' when day focus is active
    let activeDayLabel = ''; // e.g. '10月26日 今天'

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

    // Multi-dimensional Filter Modal State
    let selectedFilterType = 'all'; // 'all', 'expense', 'income'
    let selectedFilterCats = new Set(['all']); // Set of parent categories, 'all' means all
    let selectedFilterAccount = 'all'; // 'all', '微信支付', '支付宝', '招商银行卡', '现金钱包'
    let selectedDatePreset = 'all'; // 'all', 'today', 'yesterday', 'week', 'month', 'custom'

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
        document.getElementById('day-focus-label').innerText = label;
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
            <span>📅 ${activeDayLabel || activeDayFilter}</span>
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
          const icon = parentCategoryIcons[cat] || '🏷️';
          html += `
            <span class="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-indigo-900/80 text-indigo-200 border border-indigo-600/60 shrink-0">
              <span>${icon} ${cat}</span>
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
        const parentCat = resolveParentCategory(rawCat);
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
        <span onclick="filterTransactions('all', this)" class="chip-item px-3 py-1.5 rounded-xl ${isAll ? 'bg-indigo-600 text-white font-medium' : 'bg-slate-800 border border-slate-700 text-slate-300'} shrink-0 cursor-pointer tap-highlight shadow-sm">全部流水</span>
      `;

      // 2. 仅看支出
      const isExpense = (currentFilterKey === 'expense' || selectedFilterType === 'expense');
      html += `
        <span onclick="filterTransactions('expense', this)" class="chip-item px-3 py-1.5 rounded-xl ${isExpense ? 'bg-indigo-600 text-white font-medium' : 'bg-slate-800 border border-slate-700 text-slate-300'} shrink-0 cursor-pointer tap-highlight hover:text-white">仅看支出</span>
      `;

      // 4. 8大顶级父类中该月存在的分类
      for (const [parentCat, count] of Object.entries(parentCount)) {
        if (parentCat === '工资收入') continue;
        const icon = parentCategoryIcons[parentCat] || '🏷️';
        const isSelected = (currentFilterKey === parentCat || selectedFilterCats.has(parentCat));
        html += `
          <span onclick="filterTransactions('${parentCat}', this)" class="chip-item px-3 py-1.5 rounded-xl ${isSelected ? 'bg-indigo-600 text-white font-medium' : 'bg-slate-800 border border-slate-700 text-slate-300'} shrink-0 cursor-pointer tap-highlight hover:text-white">
            ${icon} ${parentCat} <span class="opacity-70 text-[10px]">(${count})</span>
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
        const itemParent = item.dataset.parent || resolveParentCategory(item.dataset.cat);
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
      document.getElementById('filter-modal').classList.remove('hidden');
    }

    function closeFilterModal() {
      document.getElementById('filter-modal').classList.add('hidden');
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
        startInput.value = '';
        endInput.value = '';
        summary.innerText = '全部日期';
      } else if (preset === 'today') {
        startInput.value = '2026-10-26';
        endInput.value = '2026-10-26';
        summary.innerText = '今天 (2026-10-26)';
      } else if (preset === 'yesterday') {
        startInput.value = '2026-10-25';
        endInput.value = '2026-10-25';
        summary.innerText = '昨天 (2026-10-25)';
      } else if (preset === 'before_yesterday') {
        startInput.value = '2026-10-24';
        endInput.value = '2026-10-24';
        summary.innerText = '前天 (2026-10-24)';
      } else if (preset === 'week') {
        startInput.value = '2026-10-20';
        endInput.value = '2026-10-26';
        summary.innerText = '近7天 (10-20 ~ 10-26)';
      } else if (preset === 'month') {
        const lastDay = getLastDayOfMonth(currentActiveYear, currentActiveMonth).toString().padStart(2, '0');
        startInput.value = `${currentActiveYear}-${currentActiveMonth}-01`;
        endInput.value = `${currentActiveYear}-${currentActiveMonth}-${lastDay}`;
        summary.innerText = `本月 (${currentActiveYear}-${currentActiveMonth})`;
      } else if (preset === 'custom') {
        summary.innerText = '自定义区间';
        startInput.focus();
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

      const s = document.getElementById('filter-start-date').value;
      const e = document.getElementById('filter-end-date').value;
      const summary = document.getElementById('filter-date-summary');
      if (s || e) {
        summary.innerText = `${s || '...'} ~ ${e || '...'}`;
      } else {
        summary.innerText = '自定义区间';
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
        badge.innerText = '全部';
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
        badge.innerText = '全部';
      } else {
        badge.innerText = `已选 ${selectedFilterCats.size} 类`;
      }
    }

    // Modal Account Selector
    function selectModalAccount(btn, acc) {
      selectedFilterAccount = acc;
      const btns = document.querySelectorAll('.modal-acc-btn');
      btns.forEach(b => b.classList.remove('active-tag'));
      btn.classList.add('active-tag');
      document.getElementById('filter-acc-badge').innerText = acc === 'all' ? '全部' : acc;
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
        document.getElementById('filter-cat-badge').innerText = '全部';
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

    // Deduplication Modal
    function simulateDedupWarning() {
      document.getElementById('dedup-modal').classList.remove('hidden');
    }

    function closeDedupModal() {
      document.getElementById('dedup-modal').classList.add('hidden');
    }

    function forceConfirm() {
      closeDedupModal();
      confirmTransaction();
    }

    // Confirm & Commit with Dynamic Category, Channel and Account
    // Shared Transaction Insertion Engine with Dynamic Date Grouping & Exact Time Tracking
    function insertTransactionToList(txData) {
      const emptyState = document.getElementById('tx-empty-state');
      if (emptyState) emptyState.classList.add('hidden');

      const txDate = txData.txDate || '2026-10-26';
      const txTime = txData.txTime || (txDate + ' 12:00:00');
      const timeOnly = txData.timeOnly || (txTime.includes(' ') ? txTime.split(' ')[1] : txTime);

      let groupName = `${parseInt(txDate.slice(5, 7))}月${parseInt(txDate.slice(8, 10))}日`;
      if (txDate === '2026-10-26') groupName += ' 今天';
      else if (txDate === '2026-10-25') groupName += ' 昨天';

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
      newTx.setAttribute('data-cat', txData.catName);
      newTx.setAttribute('data-parent', txData.parentCat);
      newTx.setAttribute('data-type', 'expense');
      newTx.setAttribute('data-date', txDate);
      newTx.setAttribute('data-account', txData.account || txData.channel);
      newTx.setAttribute('data-channel', txData.channel);
      newTx.id = txData.id;
      newTx.onclick = () => viewTransactionDetail(txData.merchant, txData.amount.toFixed(2), `${txData.parentCat}（${txData.catName}）`, txData.channel, txTime, txData.orderId);
      newTx.innerHTML = `
        <div class="flex items-center space-x-3">
          <div class="w-10 h-10 rounded-xl bg-orange-500/20 text-orange-400 flex items-center justify-center font-bold text-lg shrink-0 border border-orange-500/30">${txData.catIcon}</div>
          <div>
            <div class="flex items-center space-x-1.5">
              <span class="font-semibold text-sm text-white">${txData.merchant}</span>
              <span class="text-[11px] px-1.5 py-0.2 rounded bg-amber-500/20 text-amber-300 font-medium">${txData.catName}</span>
            </div>
            <div class="text-xs text-slate-400 mt-0.5 flex items-center space-x-1.5">
              <span>${timeOnly}</span><span>•</span><span>${txData.channel}</span><span>•</span><span class="text-emerald-400">${txData.badge || '已入账'}</span>
            </div>
          </div>
        </div>
        <div class="text-right">
          <span class="font-bold text-base text-white">-¥ ${txData.amount.toFixed(2)}</span>
          <button onclick="event.stopPropagation(); deleteTransaction('${newTx.id}', '${txData.merchant}', ${txData.amount})" class="block text-[11px] text-red-400 hover:text-red-300 hover:underline mt-0.5 ml-auto">滑动删除</button>
        </div>
      `;
      if (dayGroup) {
        dayGroup.appendChild(newTx);
        // Recalculate day subtotal
        const items = dayGroup.querySelectorAll('.tx-item:not(.soft-deleted)');
        let dayTotal = 0;
        items.forEach(el => {
          const amtStr = el.querySelector('.text-base')?.innerText?.replace(/[^\d.]/g, '') || '0';
          dayTotal += parseFloat(amtStr);
        });
        const subEl = dayGroup.querySelector('.day-subtotal');
        if (subEl) subEl.innerText = `小计: -¥ ${dayTotal.toFixed(2)}`;
      }

      // Synchronize into allMonthlyData
      if (!allMonthlyData['2026-10']) {
        allMonthlyData['2026-10'] = { net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00', txs: [] };
      }
      allMonthlyData['2026-10'].txs.unshift({
        id: txData.id,
        name: txData.merchant,
        cat: txData.catName,
        icon: txData.catIcon,
        channel: txData.channel,
        amount: txData.amount,
        date: txDate,
        dateGroup: groupName,
        time: timeOnly,
        fullTime: txTime,
        badge: txData.badge,
        orderId: txData.orderId
      });
    }

    function confirmTransaction() {
      if (draftQueue.length === 0) return;
      const amount = parseFloat(document.getElementById('input-amount').value || "0");
      const merchant = document.getElementById('input-merchant').value || "日常消费";
      const channel = document.getElementById('select-channel')?.value || "微信支付";
      const account = document.getElementById('select-account')?.value || "微信支付";
      const catName = currentDraftCategory.name || "餐饮美食";
      const catIcon = currentDraftCategory.icon || "🍔";
      const parentCat = resolveParentCategory(catName);
      const curDraft = draftQueue[currentDraftIndex];
      const orderId = curDraft ? curDraft.orderId : ('420000' + Date.now());

      const inputTime = document.getElementById('input-time')?.value?.trim();
      const txTime = inputTime || (curDraft ? curDraft.time : '2026-10-26 12:00:00');
      const txDate = txTime.split(' ')[0] || '2026-10-26';
      const timeOnly = txTime.includes(' ') ? txTime.split(' ')[1] : txTime;

      showToast(`✅ 入账成功: ${merchant} ¥${amount.toFixed(2)}`);
      
      // Update Monthly Dashboard
      const curExpEl = document.getElementById('total-expense');
      const curNetEl = document.getElementById('total-net-expense');
      const curExpense = (curExpEl ? parseFloat(curExpEl.innerText.replace(/[¥\s,]/g, '') || 0) : 0) + amount;
      const curNet = (curNetEl ? parseFloat(curNetEl.innerText.replace(/[¥\s,]/g, '') || 0) : 0) + amount;
      if (curExpEl) curExpEl.innerText = `¥ ${curExpense.toFixed(2)}`;
      if (curNetEl) curNetEl.innerText = `¥ ${curNet.toFixed(2)}`;

      insertTransactionToList({
        id: "item-tx-" + Date.now(),
        merchant: merchant,
        amount: amount,
        catName: catName,
        catIcon: catIcon,
        parentCat: parentCat,
        channel: channel,
        account: account,
        txTime: txTime,
        txDate: txDate,
        timeOnly: timeOnly,
        orderId: orderId,
        badge: '刚刚入账'
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
    }

    function deleteTransaction(itemId, name, amount) {
      const item = document.getElementById(itemId);
      if (item) {
        item.classList.add('soft-deleted');
        item.style.display = 'none';
        lastDeletedId = itemId;
        deletedItems.push({ id: itemId, name, amount });

        const bar = document.getElementById('undo-snackbar');
        document.getElementById('snackbar-text').innerText = `已移入回收站: ${name} (-¥${amount.toFixed(2)})`;
        bar.classList.remove('hidden');

        document.getElementById('trash-badge').classList.remove('hidden');
        applyActiveFilters();
        updateDynamicCategoryChips();

        setTimeout(() => {
          bar.classList.add('hidden');
        }, 4000);
      }
    }

    function undoDelete() {
      if (lastDeletedId) {
        const item = document.getElementById(lastDeletedId);
        if (item) {
          item.classList.remove('soft-deleted');
          item.style.display = 'flex';
        }
        document.getElementById('undo-snackbar').classList.add('hidden');
        deletedItems.pop();
        if (deletedItems.length === 0) {
          document.getElementById('trash-badge').classList.add('hidden');
        }
        lastDeletedId = null;
        applyActiveFilters();
        updateDynamicCategoryChips();
        showToast("已成功撤回删除");
      }
    }

    function openTrashDialog() {
      const container = document.getElementById('trash-items');
      if (deletedItems.length === 0) {
        container.innerHTML = '<p class="text-center py-4 text-slate-500">回收站暂无数据 (30天内自动清理)</p>';
      } else {
        container.innerHTML = deletedItems.map(item => `
          <div class="flex items-center justify-between p-2.5 rounded-xl bg-slate-800 border border-slate-700">
            <span>${item.name} (-¥${item.amount.toFixed(2)})</span>
            <span class="text-emerald-400 font-semibold cursor-pointer hover:underline" onclick="restoreTrash('${item.id}')">恢复账目</span>
          </div>
        `).join('');
      }
      document.getElementById('trash-modal').classList.remove('hidden');
    }

    function restoreTrash(id) {
      const item = document.getElementById(id);
      if (item) {
        item.classList.remove('soft-deleted');
        item.style.display = 'flex';
      }
      deletedItems = deletedItems.filter(i => i.id !== id);
      if (deletedItems.length === 0) {
        document.getElementById('trash-badge').classList.add('hidden');
      }
      openTrashDialog();
      applyActiveFilters();
      updateDynamicCategoryChips();
      showToast("账目已还原到流水");
    }

    function closeTrashModal() {
      document.getElementById('trash-modal').classList.add('hidden');
    }

    // Manual Add Modal
    function openManualAddModal() {
      closeAllCustomDropdowns();
      document.getElementById('manual-add-modal').classList.remove('hidden');
    }

    function closeManualAddModal() {
      closeAllCustomDropdowns();
      document.getElementById('manual-add-modal').classList.add('hidden');
    }

    function saveManualTransaction() {
      const amount = parseFloat(document.getElementById('manual-amount').value || "0");
      const merchant = document.getElementById('manual-merchant').value || "日常消费";
      const cat = document.getElementById('manual-category').value;
      const acc = document.getElementById('manual-account').value;

      if (amount <= 0 || isNaN(amount)) {
        showToast("⚠️ 请输入大于 0 的有效金额");
        return;
      }

      closeManualAddModal();
      showToast(`记账成功: ${merchant} -¥${amount.toFixed(2)}`);

      const curExpEl = document.getElementById('total-expense');
      const curNetEl = document.getElementById('total-net-expense');
      const curExpense = (curExpEl ? parseFloat(curExpEl.innerText.replace(/[¥\s,]/g, '') || 0) : 0) + amount;
      const curNet = (curNetEl ? parseFloat(curNetEl.innerText.replace(/[¥\s,]/g, '') || 0) : 0) + amount;
      if (curExpEl) curExpEl.innerText = `¥ ${curExpense.toFixed(2)}`;
      if (curNetEl) curNetEl.innerText = `¥ ${curNet.toFixed(2)}`;

      const parentCat = resolveParentCategory(cat);
      const icon = parentCategoryIcons[parentCat] || '📝';

      insertTransactionToList({
        id: "item-tx-" + Date.now(),
        merchant: merchant,
        amount: amount,
        catName: cat,
        catIcon: icon,
        parentCat: parentCat,
        channel: acc,
        account: acc,
        txTime: `${currentActiveYear}-${currentActiveMonth}-26 16:30:00`,
        txDate: `${currentActiveYear}-${currentActiveMonth}-26`,
        timeOnly: '16:30:00',
        orderId: 'MANUAL_' + Date.now(),
        badge: '手动录入'
      });
      applyActiveFilters();
      updateDynamicCategoryChips();
    }

    // Transaction Detail Modal
    function viewTransactionDetail(merchant, amount, cat, channel, time, order) {
      document.getElementById('detail-merchant').innerText = merchant;
      document.getElementById('detail-amount').innerText = `-¥ ${amount}`;
      document.getElementById('detail-cat').innerText = cat;
      document.getElementById('detail-channel').innerText = channel;
      document.getElementById('detail-time').innerText = time;
      document.getElementById('detail-order').innerText = order;
      document.getElementById('tx-detail-modal').classList.remove('hidden');
    }

    function closeTxDetailModal() {
      document.getElementById('tx-detail-modal').classList.add('hidden');
    }

    // Rules Management
    function openAddRuleModal() {
      closeAllCustomDropdowns();
      const patternInput = document.getElementById('rule-pattern-input');
      if (patternInput) patternInput.value = '';
      const matchTypeInput = document.getElementById('rule-match-type');
      if (matchTypeInput) matchTypeInput.value = 'prefix';
      const targetCatInput = document.getElementById('rule-target-cat');
      if (targetCatInput) targetCatInput.value = '餐饮美食';
      document.getElementById('add-rule-modal').classList.remove('hidden');
    }

    function closeAddRuleModal() {
      closeAllCustomDropdowns();
      document.getElementById('add-rule-modal').classList.add('hidden');
    }

    function saveNewRule() {
      const pattern = document.getElementById('rule-pattern-input').value.trim();
      const targetCat = document.getElementById('rule-target-cat').value;
      const matchType = document.getElementById('rule-match-type')?.value || 'prefix';
      if (!pattern) {
        showToast("⚠️ 请输入匹配关键词或通配符");
        return;
      }
      closeAddRuleModal();
      showToast(`规则 "${pattern}" (${matchType}) 已添加至 6 级决策链，优先级 4`);

      const container = document.getElementById('rules-list-container');
      const newRuleDiv = document.createElement('div');
      newRuleDiv.className = "flex items-center justify-between p-3 rounded-xl bg-slate-800/90 border border-slate-700 animate-fadeIn";
      newRuleDiv.innerHTML = `
        <div class="flex items-center space-x-2.5">
          <span class="w-5 h-5 rounded-full bg-purple-500/20 text-purple-400 font-bold text-[11px] flex items-center justify-center">4</span>
          <div>
            <div class="flex items-center space-x-1.5">
              <span class="font-semibold text-xs text-white">${pattern}</span>
              <span class="text-[10px] px-1 rounded bg-purple-500/20 text-purple-300 font-medium">${targetCat}</span>
            </div>
            <p class="text-[11px] text-slate-400">自定义商户规则</p>
          </div>
        </div>
        <input type="checkbox" checked onchange="toggleRule(this, '${pattern}')" class="w-4 h-4 rounded text-indigo-600 cursor-pointer">
      `;
      container.appendChild(newRuleDiv);
    }

    function toggleRule(cb, ruleName) {
      showToast(`规则 [${ruleName}] 已${cb.checked ? '启用' : '停用'}`);
    }

    function triggerRerunRules() {
      showToast("🔄 已依 6 级规则对未确认草稿执行重算 (0笔变更)");
    }

    // Accounts Edit (Custom Modal without prompt)
    let currentEditingAccount = null;

    function editAccountBalance(accName, curVal) {
      currentEditingAccount = accName;
      document.getElementById('acc-edit-title').innerText = `修改 [${accName}] 余额`;
      document.getElementById('acc-edit-input').value = curVal;
      document.getElementById('acc-edit-modal').classList.remove('hidden');
    }

    function closeAccEditModal() {
      document.getElementById('acc-edit-modal').classList.add('hidden');
    }

    function saveAccountBalance() {
      const val = parseFloat(document.getElementById('acc-edit-input').value || "0");
      if (isNaN(val)) {
        showToast("⚠️ 请输入合法的数值");
        return;
      }
      if (currentEditingAccount.includes('微信')) document.getElementById('acc-wechat').innerText = `¥ ${val.toFixed(2)}`;
      if (currentEditingAccount.includes('支付宝')) document.getElementById('acc-alipay').innerText = `¥ ${val.toFixed(2)}`;
      if (currentEditingAccount.includes('招行')) document.getElementById('acc-cmb').innerText = `¥ ${val.toFixed(2)}`;
      if (currentEditingAccount.includes('现金')) document.getElementById('acc-cash').innerText = `¥ ${val.toFixed(2)}`;
      closeAccEditModal();
      showToast(`已更新 ${currentEditingAccount} 余额为 ¥${val.toFixed(2)}`);
    }

    function openAddAccountModal() {
      closeAllCustomDropdowns();
      document.getElementById('acc-add-name').value = '';
      document.getElementById('acc-add-bal').value = '';
      const typeInput = document.getElementById('acc-add-type');
      if (typeInput) typeInput.value = 'bank_card';
      document.getElementById('acc-add-modal').classList.remove('hidden');
    }

    function closeAccAddModal() {
      closeAllCustomDropdowns();
      document.getElementById('acc-add-modal').classList.add('hidden');
    }

    function saveNewAccount() {
      const name = document.getElementById('acc-add-name').value.trim();
      const bal = parseFloat(document.getElementById('acc-add-bal').value || "0");
      const type = document.getElementById('acc-add-type')?.value || "bank_card";
      if (!name) {
        showToast("⚠️ 请输入账户名称");
        return;
      }
      closeAccAddModal();

      const grid = document.getElementById('accounts-grid');
      const card = document.createElement('div');
      card.className = "p-3 rounded-xl bg-slate-800/90 border border-slate-700 cursor-pointer hover:border-indigo-500 tap-highlight transition-all animate-fadeIn";
      card.onclick = () => editAccountBalance(name, bal.toFixed(2));
      card.innerHTML = `
        <span class="text-slate-400">${name}</span>
        <p class="text-base font-bold text-white mt-1">¥ ${bal.toFixed(2)}</p>
      `;
      grid.appendChild(card);
      showToast(`已成功添加新账户: ${name}`);
    }

    // Refund Linking Modal
    function openRefundDemoModal() {
      document.getElementById('refund-demo-modal').classList.remove('hidden');
    }

    function closeRefundDemoModal() {
      document.getElementById('refund-demo-modal').classList.add('hidden');
    }

    function executeRefundLinkDemo() {
      closeRefundDemoModal();
      // Update totals
      const curRefund = -128.00 - 50.00;
      const curNet = 3428.50 - 50.00;
      document.getElementById('total-refund').innerText = `-¥ ${Math.abs(curRefund).toFixed(2)}`;
      document.getElementById('total-net-expense').innerText = `¥ ${curNet.toFixed(2)}`;
      showToast("✅ 已成功挂载 ¥50.00 退款至原消费！月度净支出已联动扣减");
    }

    // Month Picker Modal & Full 12-Month Grid Engine
    let currentActiveYear = '2026';
    let currentActiveMonth = '10';
    let pickerYear = 2026;

    // Full 12-Month Realistic Financial Dataset Engine
    const allMonthlyData = {
        '2026-10': {
          net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00',
          txs: []
        }
      };

    function getMonthlyData(year, month) {
      const key = `${year}-${month}`;
      if (allMonthlyData[key]) return allMonthlyData[key];

      // Dynamic generator with realistic diverse transactions across standard categories
      const m = parseInt(month);
      const y = parseInt(year);
      const netVal = 2600 + ((m * 310 + y * 73) % 2400);
      const expVal = netVal + ((m % 2 === 0) ? 120 : 0);
      const refVal = (m % 2 === 0) ? '-120.00' : '0.00';
      const incVal = '18,500.00';

      const channels = ['微信支付', '支付宝', '招商银行卡', '现金钱包'];
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
      document.getElementById('month-modal').classList.remove('hidden');
    }

    function closeMonthModal() {
      document.getElementById('month-modal').classList.add('hidden');
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

      document.getElementById('label-current-month').innerText = `${currentActiveYear} 年 ${currentActiveMonth} 月`;
      document.getElementById('total-net-expense').innerText = `¥ ${data.net}`;
      document.getElementById('total-expense').innerText = `¥ ${data.exp}`;
      document.getElementById('total-refund').innerText = data.ref.startsWith('-') ? data.ref : `-¥ ${data.ref}`;
      document.getElementById('total-income').innerText = `¥ ${data.inc}`;

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
      const list = data.txs || [];
      const container = document.getElementById('transactions-list');
      if (!container) return;

      // Group transactions by dateGroup
      const groups = {};
      list.forEach(tx => {
        if (!groups[tx.dateGroup]) groups[tx.dateGroup] = [];
        groups[tx.dateGroup].push(tx);
      });

      let html = '';
      for (const [groupName, items] of Object.entries(groups)) {
        const subtotal = items.reduce((acc, cur) => acc + cur.amount, 0);
        const groupDate = items[0]?.date || '';
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
          const parentCat = resolveParentCategory(tx.cat);
          const icon = parentCategoryIcons[parentCat] || tx.icon || '📦';
          html += `
            <div data-cat="${tx.cat}" data-parent="${parentCat}" data-type="expense" data-date="${tx.date}" data-account="${tx.channel}" data-channel="${tx.channel}" class="tx-item flex items-center justify-between p-3.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 shadow-md hover:border-indigo-500 transition-all cursor-pointer tap-highlight animate-fadeIn" id="${tx.id}" onclick="viewTransactionDetail('${tx.name}', '${tx.amount.toFixed(2)}', '${parentCat}（${tx.cat}）', '${tx.channel}', '${groupName} ${tx.time}', '${tx.id}_ORDER')">
              <div class="flex items-center space-x-3">
                <div class="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center font-bold text-lg shrink-0 border border-indigo-500/30">
                  ${icon}
                </div>
                <div>
                  <div class="flex items-center space-x-1.5">
                    <span class="font-semibold text-sm text-white">${tx.name}</span>
                    <span class="text-[11px] px-1.5 py-0.2 rounded bg-indigo-500/20 text-indigo-300 font-medium">${parentCat}</span>
                    ${tx.cat !== parentCat ? `<span class="text-[10px] text-slate-400">${tx.cat}</span>` : ''}
                  </div>
                  <div class="text-xs text-slate-400 mt-0.5 flex items-center space-x-1.5">
                    <span>${tx.time}</span>
                    <span>•</span>
                    <span>${tx.channel}</span>
                    ${tx.badge ? `<span>•</span><span class="text-emerald-400">${tx.badge}</span>` : ''}
                    ${tx.refund ? `<span>•</span><span class="text-purple-300 font-medium bg-purple-500/20 px-1 rounded border border-purple-500/30">已挂载退款</span>` : ''}
                  </div>
                </div>
              </div>
              <div class="text-right">
                <span class="font-bold text-base text-white">-¥ ${tx.amount.toFixed(2)}</span>
                <button onclick="event.stopPropagation(); deleteTransaction('${tx.id}', '${tx.name}', ${tx.amount})" class="block text-[11px] text-red-400 hover:text-red-300 hover:underline mt-0.5 ml-auto">滑动删除</button>
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
    }

    // ==========================================
    // 全量自定义无原生 Win32 下拉浮层驱动引擎
    // ==========================================
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

    function isOptionMatch(id, optVal, targetVal) {
      if (optVal === String(targetVal)) return true;
      if (id === 'select-channel') {
        if ((targetVal === '招行卡' && optVal === '招商银行卡') || (targetVal === '招商银行卡' && optVal === '招行卡')) return true;
      }
      if (id === 'select-account') {
        if ((targetVal === '招商银行储蓄卡' && optVal === '招商银行储蓄卡(1234)') || (targetVal === '招商银行储蓄卡(1234)' && optVal === '招商银行储蓄卡')) return true;
      }
      if (id === 'rule-match-type') {
        if ((targetVal === '前缀匹配' && optVal === 'prefix') || (targetVal === 'prefix' && optVal === '前缀匹配')) return true;
        if ((targetVal === '通配符' || targetVal === '模糊包含') && optVal === 'contains') return true;
        if ((targetVal === '全词' || targetVal === '全词匹配') && optVal === 'exact') return true;
        if ((targetVal === '正则' || targetVal === '安全正则表达式') && optVal === 'regex') return true;
      }
      if (id === 'acc-add-type') {
        if ((targetVal === '银行储蓄卡' || targetVal === '储蓄卡') && optVal === 'bank_card') return true;
        if ((targetVal === '信用卡' || targetVal === '银行信用卡') && optVal === 'credit_card') return true;
        if (targetVal === '微信钱包' && optVal === 'wechat') return true;
        if (targetVal === '支付宝余额' && optVal === 'alipay') return true;
        if ((targetVal === '现金钱包' || targetVal === '现金') && optVal === 'cash') return true;
        if ((targetVal === '其他' || targetVal === '其他账户') && optVal === 'other') return true;
      }
      return false;
    }

    function selectCustomDropdownOption(id, value, event) {
      if (event) {
        event.stopPropagation();
      }
      const input = document.getElementById(id);
      const menu = document.getElementById('menu-' + id);
      const label = document.getElementById('label-' + id);

      if (!menu) return;

      // Update options selected state
      const options = menu.querySelectorAll('.custom-dropdown-option');
      let displayLabel = value;
      options.forEach(opt => {
        const optVal = opt.getAttribute('data-value');
        if (isOptionMatch(id, optVal, value)) {
          opt.classList.add('selected');
          const span = opt.querySelector('.truncate') || opt.querySelector('span');
          if (span) {
            displayLabel = (span.textContent || span.innerText || '').trim();
          }
        } else {
          opt.classList.remove('selected');
        }
      });

      // Update trigger label
      if (label) {
        label.textContent = displayLabel;
      }

      // Update underlying input value
      if (input) {
        const protoDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        if (protoDescriptor && protoDescriptor.set) {
          protoDescriptor.set.call(input, value);
        } else {
          input.value = value;
        }
        if (typeof input.dispatchEvent === 'function') {
          input.dispatchEvent(new Event('change', { bubbles: true }));
          input.dispatchEvent(new Event('input', { bubbles: true }));
        }
        if (typeof input.onchange === 'function') {
          try { input.onchange(new Event('change')); } catch(e) {}
        }
      }

      // Close menu
      closeAllCustomDropdowns();

      // Specific callbacks
      if (id === 'quick-date-dropdown' && typeof onQuickDateDropdownChanged === 'function') {
        onQuickDateDropdownChanged(value);
      }
    }

    function syncCustomDropdownFromValue(id, value) {
      const menu = document.getElementById('menu-' + id);
      const label = document.getElementById('label-' + id);
      if (!menu) return;

      const options = menu.querySelectorAll('.custom-dropdown-option');
      let found = false;
      let displayLabel = value;
      options.forEach(opt => {
        const optVal = opt.getAttribute('data-value');
        if (isOptionMatch(id, optVal, value)) {
          opt.classList.add('selected');
          const span = opt.querySelector('.truncate') || opt.querySelector('span');
          if (span) {
            displayLabel = (span.textContent || span.innerText || '').trim();
          }
          found = true;
        } else {
          opt.classList.remove('selected');
        }
      });

      if (label && (found || displayLabel)) {
        label.textContent = displayLabel;
      }
    }

    function initAllCustomDropdowns() {
      const dropdownIds = [
        'quick-date-dropdown',
        'select-channel',
        'select-account',
        'rule-match-type',
        'rule-target-cat',
        'manual-category',
        'manual-account',
        'acc-add-type'
      ];

      dropdownIds.forEach(id => {
        const input = document.getElementById(id);
        if (!input) return;

        const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        Object.defineProperty(input, 'value', {
          get() {
            return descriptor.get.call(this);
          },
          set(newVal) {
            descriptor.set.call(this, newVal);
            syncCustomDropdownFromValue(id, newVal);
          },
          configurable: true
        });

        // Initial sync of label from current value
        syncCustomDropdownFromValue(id, input.value);
      });

      // Global click handler to close on outside click (attach only once)
      if (!window.__dropdownListenersAttached) {
        window.__dropdownListenersAttached = true;

        document.addEventListener('click', function(e) {
          if (!e.target.closest('.custom-dropdown-container')) {
            closeAllCustomDropdowns();
          }
        });

        // Escape key to close
        document.addEventListener('keydown', function(e) {
          if (e.key === 'Escape') {
            closeAllCustomDropdowns();
          }
        });
      }
    }

    // Initialize custom dropdowns, chips & default today filter on load
    initAllCustomDropdowns();
    updateDynamicCategoryChips();
    applyActiveFilters();
    renderDraftQueue();

    // Toast helper
    function showToast(msg) {
      const t = document.createElement('div');
      t.className = "fixed top-12 left-1/2 -translate-x-1/2 bg-slate-800/95 text-white border border-slate-700 px-4 py-2.5 rounded-2xl text-xs shadow-2xl z-50 flex items-center space-x-2 animate-fadeIn backdrop-blur-md max-w-[360px] text-center";
      t.innerHTML = `<span>${msg}</span>`;
      document.body.appendChild(t);
      setTimeout(() => {
        t.style.opacity = '0';
        t.style.transition = 'opacity 0.25s ease';
        setTimeout(() => t.remove(), 250);
      }, 2000);
    }
  