with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Reset initial Monthly Card totals to 0.00
c = c.replace('id="total-net-expense" class="text-3xl font-black tracking-tight text-white mt-0.5">¥ 3,428.50</h2>',
              'id="total-net-expense" class="text-3xl font-black tracking-tight text-white mt-0.5">¥ 0.00</h2>')

c = c.replace('<span id="total-expense" class="font-bold text-white text-sm">¥ 3,556.50</span>',
              '<span id="total-expense" class="font-bold text-white text-sm">¥ 0.00</span>')

c = c.replace('<span id="total-refund" class="font-bold text-purple-200 text-sm">-¥ 128.00</span>',
              '<span id="total-refund" class="font-bold text-purple-200 text-sm">-¥ 0.00</span>')

c = c.replace('<span id="total-income" class="font-bold text-emerald-300 text-sm">¥ 18,500.00</span>',
              '<span id="total-income" class="font-bold text-emerald-300 text-sm">¥ 0.00</span>')

# 2. Wipe static mock transactions from #transactions-list
idx_tx_start = c.find('<!-- Transactions Grouped by Date -->')
idx_tx_end = c.find('<!-- Floating Bottom Quick Action Capsule', idx_tx_start)
assert idx_tx_start != -1 and idx_tx_end != -1, "Could not find transactions-list boundaries"

clean_tx_list = '''<!-- Transactions Grouped by Date -->
          <div class="space-y-3" id="transactions-list">
            <!-- Clean Empty State (Waiting for drafts confirmation) -->
            <div id="tx-empty-state" class="py-16 text-center space-y-3">
              <div class="w-16 h-16 rounded-3xl bg-slate-800/80 border border-slate-700/80 text-indigo-400 flex items-center justify-center text-2xl mx-auto shadow-inner">
                📋
              </div>
              <div class="space-y-1">
                <h4 class="text-white font-bold text-sm">暂无正式入账流水</h4>
                <p class="text-xs text-slate-400 max-w-xs mx-auto">请点击下方「草稿箱」确认 4 笔识别账单入账，或点击底部按钮快速记一笔</p>
              </div>
            </div>
          </div>

        </div>

        '''

c = c[:idx_tx_start] + clean_tx_list + c[idx_tx_end:]

with open('singwallet_preview.html', 'w', encoding='utf-8') as f:
    f.write(c)

# Verify script syntax
script_start = c.find('<script>')
script_end = c.rfind('</script>')
script = c[script_start+8:script_end]

with open('scratch/test_syntax.js', 'w', encoding='utf-8') as f:
    f.write(script)

print("PURGED ALL STATIC MOCK DATA!")
