import re

path = 'singwallet_preview.html'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update simulateIncomingAutoCommit
old_sim = '''      // Insert to Today's group
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
          <div class="w-10 h-10 rounded-xl bg-purple-500/20 text-purple-400 flex items-center justify-center font-bold text-lg shrink-0 border border-purple-500/30">${catIcon}</div>
          <div>
            <div class="flex items-center space-x-1.5">
              <span class="font-semibold text-sm text-white">${merchant}</span>
              <span class="text-[10px] px-1.5 py-0.2 rounded bg-emerald-500/20 text-emerald-300 font-semibold font-mono">🤖 免确认 99%</span>
            </div>
            <div class="text-xs text-slate-400 mt-0.5 flex items-center space-x-1.5">
              <span>刚刚</span><span>•</span><span>${channel}</span><span>•</span><span class="text-emerald-400">自动入账</span>
            </div>
          </div>
        </div>
        <div class="text-right">
          <span class="font-bold text-base text-white">-¥ ${amount.toFixed(2)}</span>
          <button onclick="event.stopPropagation(); deleteTransaction('${newTx.id}', '${merchant}', ${amount})" class="block text-[11px] text-red-400 hover:text-red-300 hover:underline mt-0.5 ml-auto">滑动删除</button>
        </div>
      `;
      let todayGroup = document.getElementById('group-today') || document.querySelector('.day-group');
      if (todayGroup) todayGroup.prepend(newTx);'''

new_sim = '''      insertTransactionToList({
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
      });'''

assert old_sim in content, "Could not find old_sim"
content = content.replace(old_sim, new_sim, 1)

# 2. Update confirmManualAdd
old_manual_full = '''      const curExpense = 3556.50 + amount;
      const curNet = 3428.50 + amount;
      document.getElementById('total-expense').innerText = `¥ ${curExpense.toFixed(2)}`;
      document.getElementById('total-net-expense').innerText = `¥ ${curNet.toFixed(2)}`;

      const parentCat = resolveParentCategory(cat);
      const icon = parentCategoryIcons[parentCat] || '📝';

      const newTx = document.createElement('div');
      newTx.className = "tx-item flex items-center justify-between p-3.5 rounded-2xl bg-slate-800/90 border border-slate-700/80 shadow-md hover:border-indigo-500 transition-all cursor-pointer tap-highlight animate-fadeIn";
      newTx.setAttribute('data-cat', cat);
      newTx.setAttribute('data-parent', parentCat);
      newTx.setAttribute('data-type', 'expense');
      newTx.setAttribute('data-date', `${currentActiveYear}-${currentActiveMonth}-26`);
      newTx.setAttribute('data-account', acc);
      newTx.setAttribute('data-channel', acc);
      newTx.id = "item-tx-" + Date.now();
      newTx.onclick = () => viewTransactionDetail(merchant, amount.toFixed(2), `${parentCat}（${cat}）`, acc, '刚刚', 'MANUAL_' + Date.now());
      newTx.innerHTML = `
        <div class="flex items-center space-x-3">
          <div class="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center font-bold text-lg shrink-0 border border-indigo-500/30">${icon}</div>
          <div>
            <div class="flex items-center space-x-1.5">
              <span class="font-semibold text-sm text-white">${merchant}</span>
              <span class="text-[11px] px-1.5 py-0.2 rounded bg-indigo-500/20 text-indigo-300 font-medium">${parentCat}</span>
            </div>
            <div class="text-xs text-slate-400 mt-0.5 flex items-center space-x-1.5">
              <span>刚刚</span><span>•</span><span>${acc}</span><span>•</span><span class="text-emerald-400">手动录入</span>
            </div>
          </div>
        </div>
        <div class="text-right">
          <span class="font-bold text-base text-white">-¥ ${amount.toFixed(2)}</span>
          <button onclick="event.stopPropagation(); deleteTransaction('${newTx.id}', '${merchant}', ${amount})" class="block text-[11px] text-red-400 hover:text-red-300 hover:underline mt-0.5 ml-auto">滑动删除</button>
        </div>
      `;
      const firstGroup = document.querySelector('.day-group');
      if (firstGroup) {
        firstGroup.appendChild(newTx);
      }'''

new_manual_full = '''      const curExpEl = document.getElementById('total-expense');
      const curNetEl = document.getElementById('total-net-expense');
      const curExpense = (curExpEl ? parseFloat(curExpEl.innerText.replace(/[¥\\s,]/g, '') || 0) : 0) + amount;
      const curNet = (curNetEl ? parseFloat(curNetEl.innerText.replace(/[¥\\s,]/g, '') || 0) : 0) + amount;
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
      });'''

assert old_manual_full in content, "Could not find old_manual_full"
content = content.replace(old_manual_full, new_manual_full, 1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("SUCCESSFULLY APPLIED BOTH AUTO & MANUAL REPLACEMENTS!")
