with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Update Monthly card totals to 0.00
c = c.replace('<p id="total-expense" class="font-bold text-sm text-white">¥ 3,556.50</p>',
              '<p id="total-expense" class="font-bold text-sm text-white">¥ 0.00</p>')

c = c.replace('<p id="total-refund" class="font-bold text-emerald-300">-¥ 128.00</p>',
              '<p id="total-refund" class="font-bold text-emerald-300">-¥ 0.00</p>')

c = c.replace('<p id="total-income" class="font-bold text-emerald-300">¥ 18,500.00</p>',
              '<p id="total-income" class="font-bold text-emerald-300">¥ 0.00</p>')

# 2. Rename the filter mismatch container to tx-no-match-state
old_filter_empty = '''          <!-- Empty State Container -->
          <div id="tx-empty-state" class="hidden text-center py-10 space-y-3 bg-slate-800/40 border border-slate-700/50 rounded-2xl p-6">
            <div class="w-12 h-12 rounded-full bg-slate-800 text-slate-400 flex items-center justify-center mx-auto text-xl">
              🔍
            </div>
            <div>
              <p class="font-semibold text-sm text-slate-300">未找到符合筛选条件的流水</p>
              <p class="text-xs text-slate-500 mt-1">请尝试放宽筛选条件或切换月份查看</p>
            </div>
            <button onclick="resetFilter()" class="px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold tap-highlight">
              重置全部筛选
            </button>
          </div>'''

new_filter_empty = '''          <!-- Filter Mismatch Empty State Container -->
          <div id="tx-no-match-state" class="hidden text-center py-10 space-y-3 bg-slate-800/40 border border-slate-700/50 rounded-2xl p-6">
            <div class="w-12 h-12 rounded-full bg-slate-800 text-slate-400 flex items-center justify-center mx-auto text-xl">
              🔍
            </div>
            <div>
              <p class="font-semibold text-sm text-slate-300">未找到符合筛选条件的流水</p>
              <p class="text-xs text-slate-500 mt-1">请尝试放宽筛选条件或切换月份查看</p>
            </div>
            <button onclick="resetFilter()" class="px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold tap-highlight">
              重置全部筛选
            </button>
          </div>'''

assert old_filter_empty in c, "old_filter_empty not found"
c = c.replace(old_filter_empty, new_filter_empty, 1)

# 3. Update applyActiveFilters to distinguish tx-empty-state (0 total transactions) vs tx-no-match-state (filter filtered out all)
old_empty_logic = '''      // Empty State Display
      const emptyState = document.getElementById('tx-empty-state');
      if (emptyState) {
        if (totalVisible === 0) {
          emptyState.classList.remove('hidden');
        } else {
          emptyState.classList.add('hidden');
        }
      }'''

new_empty_logic = '''      // Empty State Display: distinguish 0 total transactions vs filter mismatch
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
      }'''

assert old_empty_logic in c, "old_empty_logic not found"
c = c.replace(old_empty_logic, new_empty_logic, 1)

with open('singwallet_preview.html', 'w', encoding='utf-8') as f:
    f.write(c)

# Verify script syntax
script_start = c.find('<script>')
script_end = c.rfind('</script>')
script = c[script_start+8:script_end]

with open('scratch/test_syntax.js', 'w', encoding='utf-8') as f:
    f.write(script)

print("FIXED TOTALS AND EMPTY STATE LOGIC!")
