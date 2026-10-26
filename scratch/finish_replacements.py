import sys

path = 'singwallet_preview.html'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 4. Replace resetDemoDrafts with the 4 real bills
idx_reset_start = content.find('function resetDemoDrafts() {')
idx_reset_end = content.find('let currentDraftCategory =', idx_reset_start)
assert idx_reset_start != -1 and idx_reset_end != -1, "Could not find resetDemoDrafts boundaries"

new_reset_code = """function resetDemoDrafts() {
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

    """

content = content[:idx_reset_start] + new_reset_code + content[idx_reset_end:]
print("Replaced resetDemoDrafts")

# 5. Replace confirmTransaction with insertTransactionToList & confirmTransaction
idx_confirm_start = content.find('function confirmTransaction() {')
idx_confirm_end = content.find('function deleteTransaction(itemId', idx_confirm_start)
assert idx_confirm_start != -1 and idx_confirm_end != -1, "Could not find confirmTransaction boundaries"

new_confirm_block = """// Shared Transaction Insertion Engine with Dynamic Date Grouping & Exact Time Tracking
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
    }

    """

content = content[:idx_confirm_start] + new_confirm_block + content[idx_confirm_end:]
print("Replaced confirmTransaction & added insertTransactionToList")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("ALL PREVIEW REPLACEMENTS COMPLETE!")
