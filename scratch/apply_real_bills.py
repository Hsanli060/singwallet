import re
import shutil

preview_path = r'c:\Other\Projects\singwallet\singwallet_preview.html'
brain_path = r'C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\singwallet_preview.html'

with open(preview_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Replace draftQueue
new_draft_queue = """    let draftQueue = [
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
      ];"""

content = re.sub(
    r'let draftQueue = \[\s*\{[\s\S]*?\}\s*\];',
    new_draft_queue,
    content,
    count=1
)

# 2. Clear all mock monthly data
content = re.sub(
    r'const allMonthlyData = \{[\s\S]*?\n    \};',
    """const allMonthlyData = {
        '2026-10': {
          net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00',
          txs: []
        }
      };""",
    content,
    count=1
)

# 3. In getMonthlyData, return empty default txs
content = re.sub(
    r'const sampleTxs = \[\s*\{[\s\S]*?\}\s*\];\s*return \{[\s\S]*?\};',
    """return {
        net: '0.00',
        exp: '0.00',
        ref: '0.00',
        inc: '0.00',
        txs: []
      };""",
    content,
    count=1
)

# 4. In renderTransactionList, if txs is empty, show clean empty state
empty_state_html = """        if (filtered.length === 0) {
          container.innerHTML = `
            <div class="py-16 text-center text-slate-400 space-y-3">
              <div class="w-14 h-14 mx-auto rounded-full bg-slate-800/80 border border-slate-700/80 flex items-center justify-center text-2xl shadow-inner">
                🧾
              </div>
              <p class="text-sm font-semibold text-slate-300">暂无交易流水记录</p>
              <p class="text-xs text-slate-500 max-w-[240px] mx-auto">所有测试数据已全部清空。您可以前往草稿箱确认 4 笔真实账单入账，或点击下方手动快速记一笔。</p>
            </div>
          `;
          return;
        }"""

content = re.sub(
    r'if \(filtered\.length === 0\) \{[\s\S]*?return;\s*\}',
    empty_state_html,
    content,
    count=1
)

with open(preview_path, 'w', encoding='utf-8') as f:
    f.write(content)

with open(brain_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Updated singwallet_preview.html in both locations successfully!")
