path = 'singwallet_preview.html'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update loadDraftData to populate input-time and make ocrTime clickable
old_load = '''      // Inputs
      const inAmt = document.getElementById('input-amount');
      const inMer = document.getElementById('input-merchant');
      const selChan = document.getElementById('select-channel');
      const selAcc = document.getElementById('select-account');
      if (inAmt) inAmt.value = draft.amount.toFixed(2);
      if (inMer) inMer.value = draft.merchant;
      if (selChan) selChan.value = draft.channel;
      if (selAcc) selAcc.value = draft.account;'''

new_load = '''      // Inputs
      const inAmt = document.getElementById('input-amount');
      const inMer = document.getElementById('input-merchant');
      const inTime = document.getElementById('input-time');
      const selChan = document.getElementById('select-channel');
      const selAcc = document.getElementById('select-account');
      if (inAmt) inAmt.value = draft.amount.toFixed(2);
      if (inMer) inMer.value = draft.merchant;
      if (inTime) inTime.value = draft.time || '';
      if (selChan) selChan.value = draft.channel;
      if (selAcc) selAcc.value = draft.account;'''

assert old_load in content, "Could not find old_load"
content = content.replace(old_load, new_load, 1)

old_ocr_time = '''      if (ocrTime) ocrTime.innerText = `支付时间: ${draft.time}`;'''
new_ocr_time = '''      if (ocrTime) {
        ocrTime.innerText = `支付时间: ${draft.time}`;
        ocrTime.style.cursor = 'pointer';
        ocrTime.title = '点击回填此交易时间';
        ocrTime.onclick = () => fillTime(draft.time);
      }'''

assert old_ocr_time in content, "Could not find old_ocr_time"
content = content.replace(old_ocr_time, new_ocr_time, 1)

# Add fillTime right after fillMerchant
old_fill = '''    function fillMerchant(merchant) {
      document.getElementById('input-merchant').value = merchant;
      highlightInput('input-merchant');
      showToast(`✨ OCR商户名已自动提取回填: ${merchant}`);
    }'''

new_fill = '''    function fillMerchant(merchant) {
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
    }'''

assert old_fill in content, "Could not find old_fill"
content = content.replace(old_fill, new_fill, 1)

# 2. Update batchConfirmHighConfidenceDrafts
old_batch = '''    function batchConfirmHighConfidenceDrafts() {
      const highList = draftQueue.filter(d => d.confidence >= autoCommitThreshold);
      if (highList.length === 0) {
        showToast(`当前待确认队列中没有 ≥${autoCommitThreshold}% 的高置信度草稿`);
        return;
      }
      let totalAmt = 0;
      highList.forEach(draft => {
        totalAmt += draft.amount;
        const newTx = document.createElement('div');
        newTx.className = "tx-item flex items-center justify-between p-3.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 shadow-md hover:border-indigo-500 transition-all cursor-pointer tap-highlight animate-fadeIn";
        newTx.setAttribute('data-cat', draft.categoryName);
        newTx.setAttribute('data-parent', resolveParentCategory(draft.categoryName));
        newTx.setAttribute('data-type', 'expense');
        newTx.setAttribute('data-date', '2026-10-26');
        newTx.setAttribute('data-account', draft.account);
        newTx.setAttribute('data-channel', draft.channel);
        newTx.id = "item-tx-" + Date.now() + Math.random().toString(36).slice(2, 6);
        newTx.onclick = () => viewTransactionDetail(draft.merchant, draft.amount.toFixed(2), `${resolveParentCategory(draft.categoryName)}（${draft.categoryName}）`, draft.channel, '刚刚', draft.orderId);
        newTx.innerHTML = `
          <div class="flex items-center space-x-3">
            <div class="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center font-bold text-lg shrink-0 border border-indigo-500/30">${draft.categoryIcon}</div>
            <div>
              <div class="flex items-center space-x-1.5">
                <span class="font-semibold text-sm text-white">${draft.merchant}</span>
                <span class="text-[11px] px-1.5 py-0.2 rounded bg-amber-500/20 text-amber-300 font-medium">${draft.categoryName}</span>
              </div>
              <div class="text-xs text-slate-400 mt-0.5 flex items-center space-x-1.5">
                <span>刚刚</span><span>•</span><span>${draft.channel}</span><span>•</span><span class="text-emerald-400">批量一键入账</span>
              </div>
            </div>
          </div>
          <div class="text-right">
            <span class="font-bold text-base text-white">-¥ ${draft.amount.toFixed(2)}</span>
            <button onclick="event.stopPropagation(); deleteTransaction('${newTx.id}', '${draft.merchant}', ${draft.amount})" class="block text-[11px] text-red-400 hover:text-red-300 hover:underline mt-0.5 ml-auto">滑动删除</button>
          </div>
        `;
        let todayGroup = document.getElementById('group-today') || document.querySelector('.day-group');
        if (todayGroup) todayGroup.prepend(newTx);
      });

      // Update total
      const curExpense = parseFloat(document.getElementById('total-expense').innerText.replace(/[¥\s,]/g, '')) + totalAmt;
      const curNet = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, '')) + totalAmt;
      document.getElementById('total-expense').innerText = `¥ ${curExpense.toFixed(2)}`;
      document.getElementById('total-net-expense').innerText = `¥ ${curNet.toFixed(2)}`;

      // Remove highList from draftQueue
      draftQueue = draftQueue.filter(d => d.confidence < 95);
      currentDraftIndex = 0;
      renderDraftQueue();
      applyActiveFilters();
    }'''

new_batch = '''    function batchConfirmHighConfidenceDrafts() {
      const highList = draftQueue.filter(d => d.confidence >= autoCommitThreshold);
      if (highList.length === 0) {
        showToast(`当前待确认队列中没有 ≥${autoCommitThreshold}% 的高置信度草稿`);
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
          id: "item-tx-" + Date.now() + Math.random().toString(36).slice(2, 6),
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
          badge: '批量一键入账'
        });
      });

      // Update total
      const curExpEl = document.getElementById('total-expense');
      const curNetEl = document.getElementById('total-net-expense');
      const curExpense = (curExpEl ? parseFloat(curExpEl.innerText.replace(/[¥\\s,]/g, '') || 0) : 0) + totalAmt;
      const curNet = (curNetEl ? parseFloat(curNetEl.innerText.replace(/[¥\\s,]/g, '') || 0) : 0) + totalAmt;
      if (curExpEl) curExpEl.innerText = `¥ ${curExpense.toFixed(2)}`;
      if (curNetEl) curNetEl.innerText = `¥ ${curNet.toFixed(2)}`;

      // Remove highList from draftQueue
      draftQueue = draftQueue.filter(d => d.confidence < autoCommitThreshold);
      currentDraftIndex = 0;
      renderDraftQueue();
      applyActiveFilters();
      showToast(`🎉 成功将 ${highList.length} 笔高置信度账单入账！`);
    }'''

assert old_batch in content, "Could not find old_batch"
content = content.replace(old_batch, new_batch, 1)

# 3. Add insertTransactionToList before confirmTransaction, and update confirmTransaction
old_confirm = '''    // Confirm & Commit with Dynamic Category, Channel and Account
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

      showToast(`✅ 入账成功: ${merchant} ¥${amount.toFixed(2)}`);
      
      // Update Monthly Dashboard
      const curExpense = parseFloat(document.getElementById('total-expense').innerText.replace(/[¥\s,]/g, '')) + amount;
      const curNet = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, '')) + amount;
      document.getElementById('total-expense').innerText = `¥ ${curExpense.toFixed(2)}`;
      document.getElementById('total-net-expense').innerText = `¥ ${curNet.toFixed(2)}`;

      // Insert new transaction to Today's group
      const newTx = document.createElement('div');
      newTx.className = "tx-item flex items-center justify-between p-3.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 shadow-md hover:border-indigo-500 transition-all cursor-pointer tap-highlight animate-fadeIn";
      newTx.setAttribute('data-cat', catName);
      newTx.setAttribute('data-parent', parentCat);
      newTx.setAttribute('data-type', 'expense');
      newTx.setAttribute('data-date', '2026-10-26');
      newTx.setAttribute('data-account', account);
      newTx.setAttribute('data-channel', channel);
      newTx.id = "item-tx-" + Date.now();
      newTx.onclick = () => viewTransactionDetail(merchant, amount.toFixed(2), `${parentCat}（${catName}）`, channel, '刚刚', orderId);
      newTx.innerHTML = `
        <div class="flex items-center space-x-3">
          <div class="w-10 h-10 rounded-xl bg-orange-500/20 text-orange-400 flex items-center justify-center font-bold text-lg shrink-0 border border-orange-500/30">${catIcon}</div>
          <div>
            <div class="flex items-center space-x-1.5">
              <span class="font-semibold text-sm text-white">${merchant}</span>
              <span class="text-[11px] px-1.5 py-0.2 rounded bg-amber-500/20 text-amber-300 font-medium">${catName}</span>
            </div>
            <div class="text-xs text-slate-400 mt-0.5 flex items-center space-x-1.5">
              <span>刚刚</span><span>•</span><span>${channel}</span><span>•</span><span class="text-emerald-400">刚刚入账</span>
            </div>
          </div>
        </div>
        <div class="text-right">
          <span class="font-bold text-base text-white">-¥ ${amount.toFixed(2)}</span>
          <button onclick="event.stopPropagation(); deleteTransaction('${newTx.id}', '${merchant}', ${amount})" class="block text-[11px] text-red-400 hover:text-red-300 hover:underline mt-0.5 ml-auto">滑动删除</button>
        </div>
      `;
      let todayGroup = document.getElementById('group-today');
      if (!todayGroup) {
        todayGroup = document.querySelector('.day-group');
      }
      if (todayGroup) {
        todayGroup.prepend(newTx);
      }
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
    }'''

new_confirm = '''    // Shared Transaction Insertion Engine with Dynamic Date Grouping & Exact Time Tracking
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
          const amtStr = el.querySelector('.text-base')?.innerText?.replace(/[^\\d.]/g, '') || '0';
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

    // Confirm & Commit with Dynamic Category, Channel and Account
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
      const curExpense = (curExpEl ? parseFloat(curExpEl.innerText.replace(/[¥\\s,]/g, '') || 0) : 0) + amount;
      const curNet = (curNetEl ? parseFloat(curNetEl.innerText.replace(/[¥\\s,]/g, '') || 0) : 0) + amount;
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
    }'''

assert old_confirm in content, "Could not find old_confirm"
content = content.replace(old_confirm, new_confirm, 1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("SUCCESSFULLY APPLIED ALL REST REPLACEMENTS!")
