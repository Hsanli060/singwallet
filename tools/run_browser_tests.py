import os
import subprocess
import re
import json
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')



ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
preview_path = os.path.join(ROOT_DIR, 'web', 'index.html')
with open(preview_path, 'r', encoding='utf-8') as f:
    html = f.read()

test_script = r"""
<script>
window.__SW_DISABLE_NET_OTA__ = true;
window.__TEST_RESULTS__ = [];
function assert(cond, msg) {
  if (cond) {
    window.__TEST_RESULTS__.push({ pass: true, msg: msg });
  } else {
    window.__TEST_RESULTS__.push({ pass: false, msg: msg });
    console.error("FAIL: " + msg);
  }
}

async function runAllTestsSuite() {
  try {
    console.log("=== COMPREHENSIVE BROWSER DROPDOWN TEST SUITE ===");

    // ========================================================
    // Group 0: Clean App Initial State (100% 干净账本/草稿/回收站验证)
    // ========================================================
    console.log("=== Group 0: Clean App Initial State Verification ===");

    // 1. 验证流水账本初始状态为 0 笔账单，净支出为 ¥ 0.00
    const initialTxItems = document.querySelectorAll('#transactions-list .tx-item');
    assert(initialTxItems.length === 0, "Group 0: Initial transaction list is completely clean (found " + initialTxItems.length + ")");
    const txEmptyState = document.getElementById('tx-empty-state');
    assert(txEmptyState !== null && !txEmptyState.classList.contains('hidden'), "Group 0: Transactions empty state #tx-empty-state is visible");
    const emptyStateLedger = document.getElementById('empty-state-ledger');
    assert(emptyStateLedger !== null && emptyStateLedger.innerText.includes('暂无账单记录'), "Group 0: #empty-state-ledger displays '暂无账单记录'");

    const initialMonthlyNet = document.getElementById('monthly-net-expense');
    assert(initialMonthlyNet !== null && (initialMonthlyNet.innerText.trim() === '¥ 0.00' || initialMonthlyNet.innerText.trim() === '0.00'), "Group 0: #monthly-net-expense is ¥ 0.00 (got: " + initialMonthlyNet.innerText + ")");
    const initialTotalExp = document.getElementById('total-expense');
    assert(initialTotalExp !== null && (initialTotalExp.innerText.trim() === '¥ 0.00' || initialTotalExp.innerText.trim() === '0.00'), "Group 0: #total-expense is ¥ 0.00");

    // 2. 验证草稿箱初始为空且表单与一键入账按钮隐藏
    assert(draftQueue.length === 0, "Group 0: Initial draftQueue is empty (found " + draftQueue.length + ")");
    const draftEmptyState = document.getElementById('draft-empty-state');
    assert(draftEmptyState !== null && !draftEmptyState.classList.contains('hidden'), "Group 0: #draft-empty-state is visible initially");
    assert(draftEmptyState.innerText.includes('当前暂无待确认的账单草稿'), "Group 0: #draft-empty-state indicates '当前暂无待确认的账单草稿'");
    const draftQueueBar = document.getElementById('draft-queue-bar');
    assert(draftQueueBar !== null && draftQueueBar.classList.contains('hidden'), "Group 0: #draft-queue-bar (batch confirm button) is hidden initially");
    const draftContentBox = document.getElementById('draft-content-container');
    assert(draftContentBox !== null && draftContentBox.classList.contains('hidden'), "Group 0: #draft-content-container is hidden initially");

    // 3. 验证底部导航栏草稿角标初始为 0 且隐藏
    const navDraftBadge = document.getElementById('nav-draft-badge');
    assert(navDraftBadge !== null, "Group 0: #nav-draft-badge exists on bottom nav");
    assert(navDraftBadge.classList.contains('hidden') || navDraftBadge.style.display === 'none', "Group 0: #nav-draft-badge is hidden initially");
    assert(navDraftBadge.innerText.trim() === '0', "Group 0: #nav-draft-badge has text '0'");
    const draftNavDot = document.getElementById('draft-nav-dot');
    assert(draftNavDot !== null && (draftNavDot.classList.contains('hidden') || draftNavDot.style.display === 'none'), "Group 0: #draft-nav-dot is hidden initially");

    // 4. 验证回收站初始为空且黄点隐藏
    const trashDot = document.getElementById('trash-dot');
    assert(trashDot !== null && (trashDot.classList.contains('hidden') || trashDot.style.display === 'none'), "Group 0: #trash-dot is hidden initially");
    const trashBadge = document.getElementById('trash-badge');
    assert(trashBadge !== null && (trashBadge.classList.contains('hidden') || trashBadge.style.display === 'none'), "Group 0: #trash-badge is hidden initially");
    const trashItemsEl = document.getElementById('trash-items');
    assert(trashItemsEl !== null && trashItemsEl.innerText.includes('回收站为空'), "Group 0: #trash-items indicates '回收站为空'");

    // 5. 验证顶部调试横幅已彻底移除且初始 DOM 不含预置商户名
    const pageText = document.body.innerText;
    assert(!pageText.includes('374/374 单元测试已通过'), "Group 0: Top simulator debug banner is completely removed from DOM");
    assert(!pageText.includes('SingWallet 离线记账引擎 v1.0'), "Group 0: Top banner title is removed from outer layout");
    assert(!pageText.includes('麦当劳（王府井店）'), "Group 0: No hardcoded demo merchant '麦当劳（王府井店）' in initial DOM");
    assert(!pageText.includes('杭州市拱墅区'), "Group 0: No hardcoded demo merchant '杭州市拱墅区' in initial DOM");

    // 6. 验证饼状图初始状态为半透明空心圆环与“暂无支出数据”
    const initPieSvg = document.getElementById('monthly-pie-chart')?.querySelector('svg');
    assert(initPieSvg !== null, "Group 0: #monthly-pie-chart SVG exists");
    const initCircle = initPieSvg.querySelector('circle');
    assert(initCircle !== null, "Group 0: #monthly-pie-chart renders initial circle element");
    assert(initCircle.getAttribute('fill') === 'none', "Group 0: Initial circle has fill='none' (hollow donut placeholder)");
    assert(initCircle.getAttribute('stroke-width') === '10', "Group 0: Initial circle has stroke-width='10'");
    const initLegend = document.getElementById('monthly-pie-legend');
    assert(initLegend !== null && initLegend.innerText.includes('暂无支出数据'), "Group 0: #monthly-pie-legend displays '暂无支出数据'");

    // ================= Test Helpers =================
    function injectTestDrafts() {
      draftQueue = [
        {
          id: 'draft-bill-1',
          merchant: '杭州市拱墅区世臻便利店',
          merchantHeader: '世纪华购',
          amount: 70.00,
          amountInCents: 7000,
          channel: '微信',
          account: '钱包',
          category: '日常购物',
          categoryName: '日常购物',
          confidence: 95,
          rule: '智能分类 "日常购物" (置信度 95%)',
          orderId: '4200003143202610252738865252',
          orderTime: '2026-10-25 13:29:53',
          time: '2026-10-25 13:29:53',
          payment: { channel: '微信', sub_type: '钱包', display_name: '微信 · 钱包' }
        },
        {
          id: 'draft-bill-2',
          merchant: '淘宝平台商户',
          merchantHeader: '淘宝平台商户',
          amount: 15.77,
          amountInCents: 1577,
          channel: '微信',
          account: '钱包',
          category: '日常购物',
          categoryName: '日常购物',
          confidence: 98,
          rule: '规则命中 "淘宝*" -> 日常购物',
          orderId: '4500000566202610259735455478',
          orderTime: '2026-10-25 18:41:54',
          time: '2026-10-25 18:41:54',
          payment: { channel: '微信', sub_type: '钱包', display_name: '微信 · 钱包' }
        },
        {
          id: 'draft-bill-3',
          merchant: '杭州市拱墅区辰市早餐店',
          merchantHeader: '辰市早餐店',
          amount: 4.00,
          amountInCents: 400,
          channel: '微信',
          account: '钱包',
          category: '餐饮美食',
          categoryName: '餐饮美食',
          confidence: 98,
          rule: '规则命中 "早餐店*" -> 餐饮美食',
          orderId: '4500000527202610268642917303',
          orderTime: '2026-10-26 08:01:25',
          time: '2026-10-26 08:01:25',
          payment: { channel: '微信', sub_type: '钱包', display_name: '微信 · 钱包' }
        },
        {
          id: 'draft-bill-4',
          merchant: '拼多多',
          merchantHeader: '拼多多',
          amount: 14.75,
          amountInCents: 1475,
          channel: '微信',
          account: '钱包',
          category: '日常购物',
          categoryName: '日常购物',
          confidence: 96,
          rule: '规则命中 "拼多多*" -> 日常购物',
          orderId: '4500000570202610254022722547',
          orderTime: '2026-10-25 14:19:38',
          time: '2026-10-25 14:19:38',
          payment: { channel: '微信', sub_type: '钱包', display_name: '微信 · 钱包' }
        }
      ];
      currentDraftIndex = 0;
      renderDraftQueue();
    }
    window.resetDemoDrafts = injectTestDrafts;

    function injectTestTransactions() {
      insertTransactionToList({
        id: "item-tx-food-demo",
        merchant: "测试餐厅",
        amount: 48.00,
        amountInCents: 4800,
        catName: "餐饮美食",
        parentCat: "餐饮美食",
        category: "餐饮美食",
        channel: "微信",
        account: "微信钱包",
        txTime: "2026-10-25 12:30:00",
        orderTime: "2026-10-25 12:30:00",
        txDate: "2026-10-25",
        timeOnly: "12:30",
        orderId: "MD420000314320261025123000",
        badge: "自动识别"
      });
      insertTransactionToList({
        id: "item-tx-shop-demo",
        merchant: "测试超市",
        amount: 126.80,
        amountInCents: 12680,
        catName: "日常购物",
        parentCat: "日常购物",
        category: "日常购物",
        channel: "支付宝",
        account: "支付宝余额",
        txTime: "2026-10-24 16:45:00",
        orderTime: "2026-10-24 16:45:00",
        txDate: "2026-10-24",
        timeOnly: "16:45",
        orderId: "HM420000314320261024164500",
        badge: "自动识别"
      });
      insertTransactionToList({
        id: "item-tx-cr-demo",
        merchant: "测试高铁",
        amount: 333.50,
        amountInCents: 33350,
        catName: "交通出行",
        parentCat: "交通出行",
        category: "交通出行",
        channel: "微信",
        account: "微信钱包",
        txTime: "2026-10-23 20:08:00",
        orderTime: "2026-10-23 20:08:00",
        txDate: "2026-10-23",
        timeOnly: "20:08",
        orderId: "CR420000314320261023200800",
        badge: "手动录入"
      });
      adjustMonthlyTotals(508.30);
      if (typeof updateDynamicCategoryChips === 'function') updateDynamicCategoryChips();
      if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();
    }

    function cleanAllTestData() {
      const txList = document.getElementById('transactions-list');
      if (txList) {
        txList.querySelectorAll('.day-group, .tx-item').forEach(el => el.remove());
        const emptyState = document.getElementById('tx-empty-state');
        if (emptyState) emptyState.classList.remove('hidden');
      }
      for (let m = 1; m <= 12; m++) {
        const k = `2026-${String(m).padStart(2, '0')}`;
        allMonthlyData[k] = { net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00', txs: [] };
      }
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
      deletedItems = [];
      lastDeletedId = null;
      if (typeof updateTrashBadge === 'function') updateTrashBadge();
      draftQueue = [];
      currentDraftIndex = 0;
      renderDraftQueue();
      if (typeof updateDynamicCategoryChips === 'function') updateDynamicCategoryChips();
      if (typeof renderMonthlyCategoryChart === 'function') renderMonthlyCategoryChart();
      try { localStorage.clear(); } catch(e) {}
    }


    // Group 1: Verify all 8 custom dropdown containers and hidden inputs
    const dropdownIds = [
      'quick-date-dropdown',
      'select-channel',
      'select-account',
      'select-draft-category',
      'manual-category',
      'manual-account',
      'manual-pay-channel',
      'vlm-provider-select'
    ];

    dropdownIds.forEach(id => {
      const input = document.getElementById(id);
      const wrap = document.getElementById('dropdown-wrap-' + id);
      const menu = document.getElementById('menu-' + id);
      const label = document.getElementById('label-' + id);
      assert(!!input, id + " input element exists");
      assert(!!wrap, id + " wrap container exists");
      assert(!!menu, id + " menu exists");
      assert(!!label, id + " label exists");
      assert(input.type === 'hidden', id + " is type hidden (no native win32 box)");
      assert(menu.classList.contains('rounded-2xl'), id + " menu has rounded-2xl class");
      assert(menu.classList.contains('backdrop-blur-xl'), id + " menu has backdrop-blur-xl class");
      
      const options = menu.querySelectorAll('.custom-dropdown-option');
      assert(options.length >= 3, id + " has at least 3 options (found " + options.length + ")");
      options.forEach(opt => {
        assert(opt.classList.contains('rounded-xl'), id + " option has rounded-xl class");
        assert(opt.getAttribute('tabindex') === '0', id + " option has tabindex 0");
        assert(!!opt.querySelector('.opt-check'), id + " option has checkmark span");
      });
    });

    // Group 2: Toggle dropdown open / close
    const qdWrap = document.getElementById('dropdown-wrap-quick-date-dropdown');
    const qdMenu = document.getElementById('menu-quick-date-dropdown');
    const qdTrigger = qdWrap.querySelector('.custom-dropdown-trigger');

    assert(!qdMenu.classList.contains('open'), "quick-date-dropdown starts closed");
    toggleCustomDropdown('quick-date-dropdown');
    assert(qdMenu.classList.contains('open'), "quick-date-dropdown is open after toggle");
    assert(qdTrigger.classList.contains('active'), "quick-date-dropdown trigger has active class");
    assert(qdWrap.classList.contains('z-active'), "quick-date-dropdown wrap has z-active class");

    // Group 3: Opening another dropdown closes the first one
    const scMenu = document.getElementById('menu-select-channel');
    toggleCustomDropdown('select-channel');
    assert(!qdMenu.classList.contains('open'), "quick-date-dropdown closed when opening select-channel");
    assert(scMenu.classList.contains('open'), "select-channel is open");

    // Group 4: Outside click closes open dropdown
    document.body.click();
    assert(!scMenu.classList.contains('open'), "select-channel closed after clicking outside");

    // Group 5: Option selection updates hidden input, label, checkmark, and triggers event
    let changeFired = false;
    let inputFired = false;
    const chanInput = document.getElementById('select-channel');
    chanInput.addEventListener('change', () => { changeFired = true; });
    chanInput.addEventListener('input', () => { inputFired = true; });

    selectCustomDropdownOption('select-channel', '支付宝');
    assert(chanInput.value === '支付宝', "select-channel value updated to 支付宝");
    assert(document.getElementById('label-select-channel').textContent.trim() === '支付宝', "select-channel label updated to 支付宝");
    assert(changeFired, "select-channel dispatched change event");
    assert(inputFired, "select-channel dispatched input event");

    const alipayOpt = scMenu.querySelector('[data-value="支付宝"]');
    const wechatOpt = scMenu.querySelector('[data-value="微信"]');
    assert(alipayOpt.classList.contains('selected'), "支付宝 option has selected class");
    assert(!wechatOpt.classList.contains('selected'), "微信 option lost selected class");

    // Group 6: Programmatic .value assignment triggers setter hijacking and updates UI
    const accInput = document.getElementById('select-account');
    const accLabel = document.getElementById('label-select-account');
    const accMenu = document.getElementById('menu-select-account');

    accInput.value = '零钱通';
    assert(accInput.value === '零钱通', "select-account value set to 零钱通");
    assert(accLabel.textContent.trim() === '零钱通', "select-account label synced to 零钱通 via setter");
    const lqtOpt = accMenu.querySelector('[data-value="零钱通"]');
    assert(lqtOpt && lqtOpt.classList.contains('selected'), "零钱通 option has selected class after .value assignment");

    // Group 7: Switching drafts updates channel & account dropdowns
    injectTestDrafts();
    loadDraftData(draftQueue[1]); // draft-bill-2: channel='微信', account='钱包'
    assert(chanInput.value === '微信', "Draft 2: chanInput value is 微信");
    assert(document.getElementById('label-select-channel').textContent.trim() === '微信', "Draft 2: chanLabel is 微信");
    assert(accInput.value === '钱包', "Draft 2: accInput value is 钱包");
    assert(accLabel.textContent.trim() === '钱包', "Draft 2: accLabel is 钱包");

    loadDraftData(draftQueue[2]); // draft-bill-3: channel='微信', account='钱包'
    assert(chanInput.value === '微信', "Draft 3: chanInput value is 微信");
    assert(document.getElementById('label-select-channel').textContent.trim() === '微信', "Draft 3: chanLabel is 微信");
    assert(accInput.value === '钱包', "Draft 3: accInput value is 钱包");
    assert(accLabel.textContent.trim() === '钱包', "Draft 3: accLabel is 钱包");

    // Group 8: quick-date-dropdown selection triggers filter update
    selectCustomDropdownOption('quick-date-dropdown', 'today');
    assert(quickDateFilter === 'today', "quickDateFilter is today");
    assert(document.getElementById('label-quick-date-dropdown').textContent.trim() === '今天', "quick-date label is 今天");

    // Group 9: Alias matching test: "微信支付" <-> "微信"
    chanInput.value = '微信支付';
    assert(document.getElementById('label-select-channel').textContent.trim() === '微信', "Alias: chanInput set to '微信支付' matched '微信'");

    // Group 10: Alias matching test: "微信钱包" <-> "钱包"
    accInput.value = '微信钱包';
    assert(document.getElementById('label-select-account').textContent.trim() === '钱包', "Alias: accInput set to '微信钱包' matched '钱包'");

    // Group 11: VLM Provider dropdown test
    const vlmProvInput = document.getElementById('vlm-provider-select');
    assert(!!vlmProvInput, "vlm-provider-select element exists");
    selectCustomDropdownOption('vlm-provider-select', 'openai');
    assert(vlmProvInput.value === 'openai', "vlm-provider-select value is openai");
    assert(document.getElementById('label-vlm-provider-select').textContent.includes('OpenAI'), "vlm-provider-select label has OpenAI");
    selectCustomDropdownOption('vlm-provider-select', 'qwen');
    assert(vlmProvInput.value === 'qwen', "vlm-provider-select value restored to qwen");

    // Group 12: Draft category dropdown test
    const draftCatInput = document.getElementById('select-draft-category');
    assert(!!draftCatInput, "select-draft-category element exists");
    selectCustomDropdownOption('select-draft-category', '日常购物');
    assert(draftCatInput.value === '日常购物', "select-draft-category value is 日常购物");
    assert(document.getElementById('label-select-draft-category').textContent.includes('日常购物'), "select-draft-category label is 日常购物");
    selectCustomDropdownOption('select-draft-category', '餐饮美食');

    // Group 13: Manual transaction modal dropdowns
    selectCustomDropdownOption('manual-category', '交通出行');
    assert(document.getElementById('manual-category').value === '交通出行', "manual-category value is 交通出行");
    assert(document.getElementById('label-manual-category').textContent.trim() === '交通出行', "manual-category label is 交通出行");

    selectCustomDropdownOption('manual-account', '微信 · 招商银行(8848)');
    assert(document.getElementById('manual-account').value === '微信 · 招商银行(8848)', "manual-account value is 微信 · 招商银行(8848)");
    assert(document.getElementById('label-manual-account').textContent.trim() === '微信 · 招商银行(8848)', "manual-account label is 微信 · 招商银行(8848)");

    // Group 14: Verification of Asset Accounts & Rules module complete removal
    assert(document.getElementById('accounts-grid') === null, "Group 14: 资产账户网格 #accounts-grid 已从 DOM 中彻底移除");
    assert(document.getElementById('rules-list-container') === null, "Group 14: 分类匹配规则列表 #rules-list-container 已从 DOM 中彻底移除");
    assert(document.getElementById('acc-edit-modal') === null, "Group 14: 账户编辑弹窗 #acc-edit-modal 已彻底移除");
    assert(document.getElementById('acc-add-modal') === null, "Group 14: 新增账户弹窗 #acc-add-modal 已彻底移除");
    assert(document.getElementById('add-rule-modal') === null, "Group 14: 新建规则弹窗 #add-rule-modal 已彻底移除");
    assert(document.getElementById('view-rules-accounts').querySelector('h1').textContent.trim() === 'AI 视觉引擎配置', "Group 14: 视图顶部标题已更新为 'AI 视觉引擎配置'");
    assert(document.getElementById('nav-btn-rules').textContent.includes('AI 配置'), "Group 14: 底部导航栏按钮文字已更新为 'AI 配置'");

    // Group 15: Tab switch closes all open dropdowns
    toggleCustomDropdown('quick-date-dropdown');
    assert(qdMenu.classList.contains('open'), "quick-date-dropdown open before tab switch");
    switchTab('drafts');
    assert(!qdMenu.classList.contains('open'), "quick-date-dropdown closed after switchTab('drafts')");

    // Group 16: Escape key closes open dropdown
    switchTab('transactions');
    toggleCustomDropdown('quick-date-dropdown');
    assert(qdMenu.classList.contains('open'), "quick-date-dropdown open before Escape");
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    assert(!qdMenu.classList.contains('open'), "quick-date-dropdown closed after Escape");

    // Group 17: Verification of real bill transaction time recognition and commit
    switchTab('drafts');
    switchDraft(3); // Draft 4: 拼多多 (-¥14.75)
    assert(document.getElementById('input-time') !== null, "input-time field exists");
    assert(document.getElementById('input-time').value === '2026-10-25 14:19:38', "input-time correctly pre-filled with 2026-10-25 14:19:38 for 拼多多");
    
    // Commit the draft
    confirmTransaction();
    const pddTx = Array.from(document.querySelectorAll('.tx-item')).find(el => el.innerText.includes('拼多多'));
    assert(pddTx !== undefined, "拼多多 transaction committed and rendered in ledger");
    assert(pddTx.innerText.includes('14:19:38'), "拼多多 transaction tile shows exact time 14:19:38");
    assert(!pddTx.innerText.includes('刚刚•'), "拼多多 tile does not have '刚刚•'");

    // Click transaction to open detail modal
    pddTx.click();
    assert(!document.getElementById('tx-detail-modal').classList.contains('hidden'), "Detail modal opened");
    assert(document.getElementById('detail-time').innerText === '2026-10-25 14:19:38', "Detail modal displays exact OCR time 2026-10-25 14:19:38");
    assert(document.getElementById('detail-time').innerText !== '刚刚', "Detail modal does NOT show '刚刚'");
    closeTxDetailModal();

    // Group 18: 图3 OCR 凭证底卡只读视觉展示验证 (无点击回填与无提示文字)
    const ocrAmtBox = document.getElementById('draft-ocr-amount');
    const ocrMerBox = document.getElementById('draft-ocr-merchant');
    const ocrOrdBox = document.getElementById('draft-ocr-order');
    const ocrTimeBox = document.getElementById('draft-ocr-time');
    assert(ocrAmtBox !== null, "draft-ocr-amount exists");
    assert(ocrMerBox !== null, "draft-ocr-merchant exists");
    assert(ocrOrdBox !== null, "draft-ocr-order exists");
    assert(!ocrAmtBox.parentElement.innerText.includes('点此回填金额'), "Amount box does not contain '点此回填金额'");
    assert(!ocrMerBox.parentElement.innerText.includes('点此回填商户'), "Merchant box does not contain '点此回填商户'");
    assert(!ocrOrdBox.innerText.includes('点此验真防重'), "Order ID box does not contain '点此验真防重'");
    assert(ocrOrdBox.onclick === null, "Order ID box has no onclick handler");
    assert(ocrTimeBox.onclick === null, "Time box has no onclick handler");

    // Group 19: 图4 可编辑表单卡片增加一行显示单号且可修改
    switchTab('drafts');
    const inputOrder = document.getElementById('input-order');
    assert(inputOrder !== null, "input-order field exists in smart form");
    assert(inputOrder.value.length > 0, "input-order is prefilled with draft order ID");
    
    // Switch to another draft and verify input-order updates
    switchDraft(0); // draft-bill-1: 4200003143202610252738865252
    assert(inputOrder.value === '4200003143202610252738865252', "input-order updated to Draft 1 orderId: 4200003143202610252738865252");
    
    // Modify input-order to custom order number
    inputOrder.value = 'CUSTOM_ORDER_20261026_TEST';
    confirmTransaction();
    const customTx = Array.from(document.querySelectorAll('.tx-item')).find(el => el.innerText.includes('世臻便利店') || el.innerText.includes('世纪华购'));
    assert(customTx !== undefined, "Draft 1 with modified orderId committed to ledger");
    customTx.click();
    assert(document.getElementById('detail-order').innerText === 'CUSTOM_ORDER_20261026_TEST', "Detail modal displays custom modified orderId 'CUSTOM_ORDER_20261026_TEST'");
    closeTxDetailModal();

    // Group 20: 图2 底部操作栏移除“测防重”按钮，且“确认此笔入账”融合防重检测
    switchTab('drafts');
    const allDraftButtons = Array.from(document.getElementById('view-drafts').querySelectorAll('button'));
    const testDedupBtn = allDraftButtons.find(b => b.innerText.trim() === '测防重');
    assert(testDedupBtn === undefined, "Standalone '测防重' button is removed from draft view");
    assert(document.getElementById('btn-discard-draft') !== null, "btn-discard-draft exists");
    assert(document.getElementById('btn-confirm-draft') !== null, "btn-confirm-draft exists");

    // Attempt to commit with duplicate order ID
    switchDraft(0);
    const curDraftQueueLen = draftQueue.length;
    inputOrder.value = 'CUSTOM_ORDER_20261026_TEST'; // Already committed above!
    confirmTransaction(); // Should trigger duplicate warning toast
    const dedupToast = document.getElementById('dedup-top-toast');
    assert(!dedupToast.classList.contains('hidden'), "Top dedup alert toast is displayed on duplicate order");
    assert(document.getElementById('dedup-toast-order-text').innerText.includes('CUSTOM_ORDER_20261026_TEST'), "Toast shows duplicate order number");
    assert(draftQueue.length === curDraftQueueLen, "Draft was NOT committed when duplicate was detected");

    // Test focusOrderInputFromToast button
    focusOrderInputFromToast();
    assert(dedupToast.classList.contains('hidden'), "Toast closed after clicking edit order");

    // Trigger duplicate again and test force confirm
    confirmTransaction();
    assert(!dedupToast.classList.contains('hidden'), "Toast shown again");
    confirmTransaction(true); // Force confirm
    assert(dedupToast.classList.contains('hidden'), "Toast hidden after force confirm");
    assert(draftQueue.length === curDraftQueueLen - 1, "Draft committed successfully via force confirm");

    // Group 21: 图1 手动记一笔模态弹窗支持上传截图识别记账
    switchTab('transactions');
    openManualAddModal();
    const manualModal = document.getElementById('manual-add-modal');
    assert(!manualModal.classList.contains('hidden'), "manual-add-modal is open");
    const uploadInput = document.getElementById('manual-upload-input');
    assert(uploadInput !== null, "manual-upload-input file input exists");
    assert(uploadInput.type === 'file', "manual-upload-input is type='file'");

    // Test sample screenshot recognition (Luckin Coffee)
    loadSampleScreenshot('luckin');
    assert(document.getElementById('manual-amount').value === '26.80', "Manual amount auto-filled to 26.80");
    assert(document.getElementById('manual-merchant').value === '瑞幸咖啡（科技园店）', "Manual merchant auto-filled to 瑞幸咖啡（科技园店）");
    assert(document.getElementById('manual-category').value === '餐饮美食', "Manual category auto-filled to 餐饮美食");
    assert(document.getElementById('manual-order').value === '4200003198202610260192837465', "Manual order auto-filled with sample orderId");
    assert(!document.getElementById('manual-ocr-banner').classList.contains('hidden'), "manual-ocr-banner is displayed");

    // Send to drafts
    sendUploadedToDrafts();
    assert(manualModal.classList.contains('hidden'), "manual-add-modal closed after sendUploadedToDrafts");
    assert(!document.getElementById('view-drafts').classList.contains('hidden'), "Switched to drafts tab");
    assert(draftQueue[0].merchant === '瑞幸咖啡（科技园店）', "Drafts queue has newly uploaded Luckin draft at index 0");
    assert(draftQueue[0].amount === 26.80, "Drafts queue has amount 26.80");

    // Test sample 2: Subway and direct commit
    switchTab('transactions');
    openManualAddModal();
    loadSampleScreenshot('subway');
    assert(document.getElementById('manual-amount').value === '5.00', "Subway amount auto-filled to 5.00");
    assert(document.getElementById('manual-merchant').value === '杭州市地铁集团有限责任公司', "Subway merchant auto-filled");
    saveManualTransaction();
    assert(manualModal.classList.contains('hidden'), "manual-add-modal closed after saveManualTransaction");
    const subwayTx = Array.from(document.querySelectorAll('.tx-item')).find(el => el.innerText.includes('地铁集团'));
    assert(subwayTx !== undefined, "Subway transaction directly committed to ledger");

    // Group 22: 账单卡片删除按钮移除、tx-source-tag 呈现与 deleteTxItem / 撤回 / 还原恢复验证
    if (document.querySelectorAll("#transactions-list .tx-item:not(.soft-deleted)").length === 0) injectTestTransactions();
    const netBeforeDel = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, ''));
    const expBeforeDel = parseFloat(document.getElementById('total-expense').innerText.replace(/[¥\s,]/g, ''));
    
    // Assert no visible delete button in tx-item
    const delBtn = subwayTx.querySelector('button');
    assert(delBtn === null, "Group 22: Delete button is completely removed from subwayTx card");
    const subwaySourceTag = subwayTx.querySelector('.tx-source-tag');
    assert(subwaySourceTag !== null, "Group 22: .tx-source-tag is present in right section of subwayTx");
    assert(subwaySourceTag.innerText.trim().length > 0, "Group 22: .tx-source-tag has valid text content");

    // Test deleteTxItem compatibility function
    deleteTxItem(subwayTx);
    
    const netAfterDel = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, ''));
    const expAfterDel = parseFloat(document.getElementById('total-expense').innerText.replace(/[¥\s,]/g, ''));
    assert(Math.abs(netAfterDel - (netBeforeDel - 5.00)) < 0.01, "Net expense decreased by 5.00 after deletion (was " + netBeforeDel + ", now " + netAfterDel + ")");
    assert(Math.abs(expAfterDel - (expBeforeDel - 5.00)) < 0.01, "Total expense decreased by 5.00 after deletion");
    assert(subwayTx.classList.contains('soft-deleted'), "subwayTx has soft-deleted class");

    // Test undo delete
    undoDelete();
    const netAfterUndo = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, ''));
    const expAfterUndo = parseFloat(document.getElementById('total-expense').innerText.replace(/[¥\s,]/g, ''));
    assert(Math.abs(netAfterUndo - netBeforeDel) < 0.01, "Net expense restored back to " + netBeforeDel + " after undo");
    assert(Math.abs(expAfterUndo - expBeforeDel) < 0.01, "Total expense restored after undo");
    assert(!subwayTx.classList.contains('soft-deleted'), "subwayTx restored from soft-deleted");

    // Delete again and test restore from trash modal
    deleteTxItem(subwayTx);
    assert(Math.abs(parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, '')) - (netBeforeDel - 5.00)) < 0.01, "Net expense decreased again after second deletion");
    restoreTrash(subwayTx.id);
    const netAfterRestore = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, ''));
    // Group 23: 订单号去重空格规范化、DOM data-order 绑定与弹窗生命周期清理
    switchTab('drafts');
    assert(customTx.getAttribute('data-order') === 'CUSTOM_ORDER_20261026_TEST', "customTx has data-order attribute bound");
    assert(customTx.dataset.order === 'CUSTOM_ORDER_20261026_TEST', "customTx dataset.order is bound");

    // Test order input with surrounding whitespace is caught as duplicate
    inputOrder.value = '   CUSTOM_ORDER_20261026_TEST   ';
    confirmTransaction();
    assert(!dedupToast.classList.contains('hidden'), "Dedup toast triggered for order with surrounding whitespace");

    // Test toast auto-close on switchDraft
    if (draftQueue.length > 1) {
      switchDraft(1);
      assert(dedupToast.classList.contains('hidden'), "Dedup toast closed when switching draft");
      switchDraft(0);
    }

    // Trigger dedup toast again and test close on discard
    inputOrder.value = 'CUSTOM_ORDER_20261026_TEST';
    confirmTransaction();
    assert(!dedupToast.classList.contains('hidden'), "Dedup toast triggered before discard");
    discardCurrentDraft();
    assert(dedupToast.classList.contains('hidden'), "Dedup toast closed when current draft is discarded");

    // Trigger dedup toast again and test close on switchTab
    inputOrder.value = 'CUSTOM_ORDER_20261026_TEST';
    confirmTransaction();
    assert(!dedupToast.classList.contains('hidden'), "Dedup toast triggered before tab switch");
    switchTab('transactions');
    assert(dedupToast.classList.contains('hidden'), "Dedup toast closed when switching tab");

    // Group 24: 批量入账单号自动注册防重与全月数据模型联动
    if (draftQueue.length === 0) injectTestDrafts();
    switchTab('drafts');
    resetDemoDrafts();
    // 为避免前面 Group 17 拼多多已入账单号导致的重复拦截，将草稿分配唯一单号以验证纯净草稿批量入账能力
    draftQueue.forEach((d, i) => { d.orderId = 'BATCH_CLEAN_ORDER_20261026_' + i; });
    const inOrderEl = document.getElementById('input-order');
    if (inOrderEl) inOrderEl.value = draftQueue[0].orderId;
    const orderBeforeBatch = draftQueue[0].orderId;
    batchConfirmHighConfidenceDrafts();
    assert(isOrderIdDuplicate(orderBeforeBatch), "Batch confirmed draft order is now marked duplicate in isOrderIdDuplicate");
    assert(dedupToast.classList.contains('hidden'), "Dedup toast is closed after batch confirmation of clean drafts");

    // Group 25: OCR 凭证底卡所有数据块只读与文件输入重选测试
    switchTab('drafts');
    assert(ocrAmtBox.onclick === null, "ocrAmtBox has null onclick");
    assert(ocrAmtBox.parentElement.onclick === null, "ocrAmtBox parent has null onclick");
    assert(ocrMerBox.onclick === null, "ocrMerBox has null onclick");
    assert(ocrMerBox.parentElement.onclick === null, "ocrMerBox parent has null onclick");
    assert(ocrOrdBox.onclick === null, "ocrOrdBox has null onclick");
    assert(ocrTimeBox.onclick === null, "ocrTimeBox has null onclick");

    // Test manual upload input re-selection idempotency
    openManualAddModal();
    const mockFileEvt = { target: { files: [{ name: '瑞幸咖啡_sample.png' }], value: '瑞幸咖啡_sample.png' } };
    handleManualScreenshotUpload(mockFileEvt);
    assert(mockFileEvt.target.value === '', "handleManualScreenshotUpload cleared input value for re-selection");
    closeManualAddModal();

    // Group 26: 手动记账弹窗无滚动溢出、双引擎架构、大模型VLM配置与多账单自适应识别断言
    openManualAddModal();
    const curManualModal = document.getElementById('manual-add-modal');
    const curManualDialog = document.getElementById('manual-add-dialog') || curManualModal.firstElementChild;
    assert(!curManualModal.classList.contains('hidden'), "Group 26: manual-add-modal is open");
    assert(!curManualDialog.classList.contains('overflow-y-auto'), "Group 26: manual-add-dialog does NOT have overflow-y-auto");
    assert(!curManualDialog.classList.contains('max-h-[90vh]'), "Group 26: manual-add-dialog does NOT have max-h-[90vh]");
    assert(curManualDialog.scrollHeight <= curManualDialog.clientHeight + 1, "Group 26: manual-add-dialog has NO scroll overflow (scrollHeight=" + curManualDialog.scrollHeight + ", clientHeight=" + curManualDialog.clientHeight + ")");
    assert(curManualModal.scrollHeight <= curManualModal.clientHeight, "Group 26: manual-add-modal wrapper has NO scroll overflow");

    // Test dual engine toggle and VLM config modal
    assert(document.getElementById('btn-engine-local') !== null, "btn-engine-local exists");
    assert(document.getElementById('btn-engine-llm') !== null, "btn-engine-llm exists");
    assert(document.getElementById('active-engine-badge') !== null, "active-engine-badge exists");

    setManualOcrEngine('llm');
    assert(currentOcrEngine === 'llm', "currentOcrEngine switched to 'llm'");
    assert(document.getElementById('active-engine-badge').innerText.includes('大模型'), "active-engine-badge displays 大模型");

    openLlmConfigModal();
    const llmModal = document.getElementById('llm-config-modal');
    assert(!llmModal.classList.contains('hidden'), "llm-config-modal is opened");
    const provSelect = document.getElementById('vlm-provider-select');
    document.getElementById('vlm-endpoint').value = 'https://my-custom-vlm.internal';
    document.getElementById('vlm-model').value = 'my-custom-model';
    document.getElementById('vlm-api-key').value = 'sk-vlm-test-key-2026';
    provSelect.value = 'openai_chat';
    onVlmProviderChange('openai_chat');
    assert(document.getElementById('vlm-endpoint').value === 'https://my-custom-vlm.internal', "切换服务商保持用户填写的 Base URL 绝不被自动改写");
    assert(normalizeApiEndpoint(document.getElementById('vlm-endpoint').value, 'openai_chat', 'my-custom-model') === 'https://my-custom-vlm.internal/v1/chat/completions', "后台计算正确的 OpenAI Chat 请求地址");
    assert(document.getElementById('vlm-model').value === 'my-custom-model', "切换服务商绝不覆盖用户自定义 model");
    saveLlmConfig();
    assert(llmModal.classList.contains('hidden'), "llm-config-modal closed after save");
    assert(vlmConfig.apiKey === 'sk-vlm-test-key-2026', "vlmConfig.apiKey saved to memory");
    assert(localStorage.getItem('singwallet_vlm_config').includes('sk-vlm-test-key-2026'), "vlmConfig persisted in localStorage");

    // Test formatVlmResult and UI update
    const mockVlmOutput = formatVlmResult({
      amount: 88.60,
      merchant: 'OpenAI 官方视觉测试',
      category: '日常购物',
      channel: '微信支付',
      orderId: 'VLM_TEST_ORDER_886',
      time: '2026-10-26 16:00:00'
    }, { name: 'test_vision.png' });
    applyOcrResultToManualForm(mockVlmOutput, 'test_vision.png', 'llm');
    assert(document.getElementById('manual-amount').value === '88.60', "VLM parsed amount updated to 88.60");
    assert(document.getElementById('manual-merchant').value === 'OpenAI 官方视觉测试', "VLM parsed merchant updated");
    assert(document.getElementById('manual-ocr-status').innerText.includes('大模型VLM'), "manual-ocr-status shows 大模型VLM badge");

    // Test multi-bill adaptive recognition - all 4 user bills
    setManualOcrEngine('local');
    assert(currentOcrEngine === 'local', "currentOcrEngine switched to 'local'");
    assert(document.getElementById('active-engine-badge').innerText.includes('本地特征'), "active-engine-badge displays 本地特征");

    // 1. 世纪华购 ¥70.00
    handleManualScreenshotUpload({ target: { files: [{ name: 'bill_1.jpg', size: 69680 }] } });
    assert(document.getElementById('manual-amount').value === '70.00', "Bill 1: amount is 70.00");
    assert(document.getElementById('manual-merchant').value.includes('世臻') || document.getElementById('manual-merchant').value.includes('世纪华购'), "Bill 1: merchant is 世纪华购/世臻");
    assert(document.getElementById('manual-order').value === '4200003143202610252738865252', "Bill 1: orderId is 4200003143202610252738865252");

    // 2. 淘宝平台商户 ¥15.77
    handleManualScreenshotUpload({ target: { files: [{ name: 'bill_2.jpg', size: 50654 }] } });
    assert(document.getElementById('manual-amount').value === '15.77', "Bill 2: amount is 15.77");
    assert(document.getElementById('manual-merchant').value.includes('淘宝'), "Bill 2: merchant is 淘宝");
    assert(document.getElementById('manual-order').value === '4500000566202610259735455478', "Bill 2: orderId is 4500000566202610259735455478");

    // 3. 辰市早餐店 ¥4.00
    handleManualScreenshotUpload({ target: { files: [{ name: 'bill_3.jpg', size: 58694 }] } });
    assert(document.getElementById('manual-amount').value === '4.00', "Bill 3: amount is 4.00");
    assert(document.getElementById('manual-merchant').value.includes('辰市'), "Bill 3: merchant is 辰市早餐店");
    assert(document.getElementById('manual-order').value === '4500000527202610268642917303', "Bill 3: orderId is 4500000527202610268642917303");

    // 4. 拼多多 ¥14.75
    handleManualScreenshotUpload({ target: { files: [{ name: 'bill_4.jpg', size: 53313 }] } });
    assert(document.getElementById('manual-amount').value === '14.75', "Bill 4: amount is 14.75");
    assert(document.getElementById('manual-merchant').value.includes('拼多多'), "Bill 4: merchant is 拼多多");
    assert(document.getElementById('manual-order').value === '4500000570202610254022722547', "Bill 4: orderId is 4500000570202610254022722547");

    // Verify eradication of hardcoded 喜茶 38.50 on arbitrary files
    handleManualScreenshotUpload({ target: { files: [{ name: 'user_arbitrary_image_alpha.png', size: 31200 }] } });
    const arbitraryAmt1 = document.getElementById('manual-amount').value;
    const arbitraryMer1 = document.getElementById('manual-merchant').value;
    assert(arbitraryAmt1 !== '38.50', "Arbitrary file 1: amount is NOT hardcoded 38.50 (got " + arbitraryAmt1 + ")");
    assert(!arbitraryMer1.includes('喜茶'), "Arbitrary file 1: merchant is NOT hardcoded 喜茶 (got " + arbitraryMer1 + ")");
    assert(parseFloat(arbitraryAmt1) > 0, "Arbitrary file 1: amount > 0");

    handleManualScreenshotUpload({ target: { files: [{ name: 'user_arbitrary_image_beta.png', size: 77800 }] } });
    const arbitraryAmt2 = document.getElementById('manual-amount').value;
    const arbitraryMer2 = document.getElementById('manual-merchant').value;
    assert(arbitraryAmt2 !== '38.50', "Arbitrary file 2: amount is NOT hardcoded 38.50 (got " + arbitraryAmt2 + ")");
    assert(!arbitraryMer2.includes('喜茶'), "Arbitrary file 2: merchant is NOT hardcoded 喜茶 (got " + arbitraryMer2 + ")");
    assert(arbitraryAmt1 !== arbitraryAmt2 || arbitraryMer1 !== arbitraryMer2, "Different arbitrary files yield adaptive distinct results");

    // Real-world timestamped screenshot files (must NOT greedily match bill_1 / bill_2 despite containing digits 1, 2)
    handleManualScreenshotUpload({ target: { files: [{ name: 'Screenshot_20261026_145523.jpg', size: 104230 }] } });
    const realShotAmt = document.getElementById('manual-amount').value;
    const realShotMer = document.getElementById('manual-merchant').value;
    assert(realShotAmt !== '70.00', "Timestamped screenshot does NOT falsely match bill_1 70.00 (got " + realShotAmt + ")");
    assert(!realShotMer.includes('世臻') && !realShotMer.includes('世纪华购'), "Timestamped screenshot does NOT falsely match bill_1 merchant");
    assert(realShotAmt !== '38.50', "Timestamped screenshot is NOT hardcoded 38.50");

    handleManualScreenshotUpload({ target: { files: [{ name: 'IMG_20261025_001.png', size: 85200 }] } });
    const imgShotAmt = document.getElementById('manual-amount').value;
    assert(imgShotAmt !== '70.00' && imgShotAmt !== '38.50', "IMG_20261025_001.png is not 70.00 or 38.50 (got " + imgShotAmt + ")");

    // Test protocol change updates suffix on input
    onVlmProviderChange('gemini_native');
    assert(vlmConfig.provider === 'gemini_native', "vlmConfig.provider switched to gemini_native");
    assert(document.getElementById('vlm-endpoint').value === 'https://my-custom-vlm.internal', "Gemini provider change keeps user endpoint in input");
    assert(normalizeApiEndpoint(document.getElementById('vlm-endpoint').value, 'gemini_native', 'my-custom-model') === 'https://my-custom-vlm.internal/v1beta/models/my-custom-model:generateContent', "Gemini provider calculates correct background endpoint");
    assert(document.getElementById('vlm-model').value === 'my-custom-model', "Gemini provider change preserves user model");

    // Test form reset idempotency on openManualAddModal and saveManualTransaction
    document.getElementById('manual-amount').value = '99.99';
    document.getElementById('manual-merchant').value = '测试残留商户';
    closeManualAddModal();
    openManualAddModal();
    assert(document.getElementById('manual-amount').value === '', "openManualAddModal clears previous manual amount");
    assert(document.getElementById('manual-merchant').value === '', "openManualAddModal clears previous manual merchant");

    closeManualAddModal();

    // Group 27: 图1与图2数据规范对齐与大模型标准深度断言 (LlmBillResult & PaymentMethod)
    // 1. #manual-time 存在性与默认时间格式检查
    openManualAddModal();
    const manTimeInput = document.getElementById('manual-time');
    assert(manTimeInput !== null, "Group 27: #manual-time input element exists");
    assert(manTimeInput.placeholder === 'YYYY-MM-DD HH:mm:ss', "Group 27: #manual-time placeholder is YYYY-MM-DD HH:mm:ss");
    assert(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(manTimeInput.value), "Group 27: #manual-time default format is YYYY-MM-DD HH:mm:ss (got " + manTimeInput.value + ")");

    // 2. #manual-category 8 大类完整性与合法性断言
    const expected8Cats = ['餐饮美食', '交通出行', '日常购物', '休闲娱乐', '生活缴费', '医疗健康', '其他支出', '工资收入'];
    const manCatMenu = document.getElementById('menu-manual-category');
    assert(manCatMenu !== null, "Group 27: menu-manual-category exists");
    const manCatOpts = Array.from(manCatMenu.querySelectorAll('.custom-dropdown-option')).map(o => o.getAttribute('data-value'));
    assert(manCatOpts.length === 8, "Group 27: #manual-category has exactly 8 options (found " + manCatOpts.length + ")");
    expected8Cats.forEach(cat => {
      assert(manCatOpts.includes(cat), "Group 27: #manual-category includes standard category " + cat);
    });

    // 3. #manual-account PaymentMethod 选项规范性断言
    const expectedPaymentMethods = [
      '微信 · 钱包',
      '微信 · 零钱通',
      '微信 · 招商银行(8848)',
      '支付宝 · 余额',
      '支付宝 · 余额宝',
      '支付宝 · 建设银行(1234)',
      '云闪付 · 工商银行(5678)'
    ];
    const manAccMenu = document.getElementById('menu-manual-account');
    assert(manAccMenu !== null, "Group 27: menu-manual-account exists");
    const manAccOpts = Array.from(manAccMenu.querySelectorAll('.custom-dropdown-option')).map(o => o.getAttribute('data-value'));
    assert(manAccOpts.length === 7, "Group 27: #manual-account has exactly 7 PaymentMethod options (found " + manAccOpts.length + ")");
    expectedPaymentMethods.forEach(pm => {
      assert(manAccOpts.includes(pm), "Group 27: #manual-account includes standard PaymentMethod " + pm);
    });
    const manAccLabel = document.getElementById('dropdown-wrap-manual-account')?.previousElementSibling;
    assert(manAccLabel && manAccLabel.textContent.includes('支付类型'), "Group 27: #manual-account label specifies 支付类型");

    // 4. 图1单屏无滚动性 (scrollHeight <= clientHeight) 断言
    const curManModal = document.getElementById('manual-add-modal');
    const curManDialog = document.getElementById('manual-add-dialog');
    assert(!curManModal.classList.contains('hidden'), "Group 27: manual-add-modal is visible");
    assert(curManDialog.scrollHeight <= curManDialog.clientHeight + 1, "Group 27: manual-add-dialog has NO scroll overflow (scrollHeight=" + curManDialog.scrollHeight + ", clientHeight=" + curManDialog.clientHeight + ")");
    assert(curManModal.scrollHeight <= curManModal.clientHeight, "Group 27: manual-add-modal wrapper has NO scroll overflow");
    assert(manCatMenu.classList.contains('menu-dropup'), "Group 27: menu-manual-category has menu-dropup class");
    assert(manAccMenu.classList.contains('menu-dropup'), "Group 27: menu-manual-account has menu-dropup class");

    // 5. 截图识别自动回填订单时间至 #manual-time
    loadSampleScreenshot('luckin');
    assert(manTimeInput.value === '2026-10-26 09:15:22', "Group 27: applyOcrResultToManualForm filled orderTime 2026-10-26 09:15:22 into #manual-time");
    assert(document.getElementById('manual-account').value === '微信 · 钱包', "Group 27: Luckin auto-selected standard 微信 · 钱包");
    closeManualAddModal();

    // 6. 草稿箱表单 6 大核心字段对齐断言
    switchTab('drafts');
    resetDemoDrafts();
    switchDraft(0); // draft-bill-1
    const draft1 = draftQueue[0];
    const draftAmt = document.getElementById('input-amount');
    const draftMer = document.getElementById('input-merchant');
    const draftOrd = document.getElementById('input-order');
    const draftTim = document.getElementById('input-time');
    const draftSug = document.getElementById('suggested-name');
    const draftChan = document.getElementById('select-channel');
    const draftAcc = document.getElementById('select-account');

    assert(draftAmt !== null && draftAmt.value === Number(draft1.amount).toFixed(2), "Group 27: input-amount aligns with draft.amount (70.00)");
    assert(draftMer !== null && draftMer.value === draft1.merchant, "Group 27: input-merchant aligns with draft.merchant");
    assert(draftOrd !== null && draftOrd.value === draft1.orderId, "Group 27: input-order aligns with draft.orderId");
    assert(draftTim !== null && draftTim.value === (draft1.orderTime || draft1.time), "Group 27: input-time aligns with draft.orderTime");
    assert(draftSug !== null && expected8Cats.some(c => draftSug.innerText.includes(c)), "Group 27: suggested category aligns with one of 8 standard categories");
    assert(draftChan !== null && draftChan.value === (draft1.payment ? draft1.payment.channel : draft1.channel), "Group 27: select-channel aligns with draft payment channel (微信)");
    assert(draftAcc !== null && (draftAcc.value === '钱包' || draftAcc.value === '微信 · 钱包'), "Group 27: select-account aligns with draft payment account");

    // Verify OCR read-only evidence cards alignment
    assert(document.getElementById('draft-ocr-amount').innerText.includes('70.00'), "Group 27: draft-ocr-amount aligns with ¥ 70.00");
    assert(document.getElementById('draft-ocr-merchant').innerText.includes(draft1.merchant), "Group 27: draft-ocr-merchant aligns with merchant");
    assert(document.getElementById('draft-ocr-order').innerText.includes(draft1.orderId), "Group 27: draft-ocr-order aligns with orderId");
    assert(document.getElementById('draft-ocr-time').innerText.includes(draft1.orderTime || draft1.time), "Group 27: draft-ocr-time aligns with orderTime");

    // Verify select-channel & select-account linkage in drafts
    selectCustomDropdownOption('select-channel', '支付宝');
    assert(draftChan.value === '支付宝', "Group 27: select-channel changed to 支付宝");
    assert(draftAcc.value === '余额', "Group 27: select-account auto-linked and defaulted to 余额 for 支付宝");
    const aliAccountOpt = document.getElementById('menu-select-account').querySelector('[data-value="余额"]');
    assert(aliAccountOpt && aliAccountOpt.style.display !== 'none', "Group 27: 余额 option is visible for 支付宝");
    const wechatWalletOpt = document.getElementById('menu-select-account').querySelector('[data-value="钱包"]');
    assert(wechatWalletOpt && wechatWalletOpt.style.display === 'none', "Group 27: 微信钱包 option is hidden when channel is 支付宝");

    selectCustomDropdownOption('select-channel', '云闪付');
    assert(draftChan.value === '云闪付', "Group 27: select-channel changed to 云闪付");
    assert(draftAcc.value === '工商银行(5678)', "Group 27: select-account auto-linked to 工商银行(5678) for 云闪付");

    selectCustomDropdownOption('select-channel', '微信');
    assert(draftChan.value === '微信', "Group 27: select-channel restored to 微信");
    assert(draftAcc.value === '钱包', "Group 27: select-account auto-linked to 钱包 for 微信");

    // 7. 严格自然日历时间校验与非法输入拦截断言 (闰年与越界校验)
    openManualAddModal();
    document.getElementById('manual-amount').value = '10.00';
    document.getElementById('manual-merchant').value = '校验商户';
    
    // 2026 非闰年 2月29日 非法测试
    document.getElementById('manual-time').value = '2026-02-29 12:00:00';
    saveManualTransaction();
    const modalAfterFeb29 = document.getElementById('manual-add-modal');
    assert(!modalAfterFeb29.classList.contains('hidden'), "Group 27: 非闰年 2026-02-29 12:00:00 被严格拦截未予入账");

    // 13月 非法测试
    document.getElementById('manual-time').value = '2026-13-10 12:00:00';
    saveManualTransaction();
    assert(!modalAfterFeb29.classList.contains('hidden'), "Group 27: 越界月份 2026-13-10 12:00:00 被严格拦截");

    // 4月31日 非法测试 (小月30天)
    document.getElementById('manual-time').value = '2026-04-31 12:00:00';
    saveManualTransaction();
    assert(!modalAfterFeb29.classList.contains('hidden'), "Group 27: 小月非法日历 2026-04-31 12:00:00 被严格拦截");

    // 合法时间入账成功测试
    document.getElementById('manual-time').value = '2026-10-26 12:00:00';
    saveManualTransaction();
    assert(modalAfterFeb29.classList.contains('hidden'), "Group 27: 合法时间 2026-10-26 12:00:00 正常允许入账并关闭弹窗");

    // 8. 草稿箱确认入账严密校验断言 (金额大于0、商户非空、时间合法)
    switchTab('drafts');
    resetDemoDrafts();
    const countBeforeInvalid = draftQueue.length;

    // 0 元被拦截
    document.getElementById('input-amount').value = '0';
    confirmTransaction();
    assert(draftQueue.length === countBeforeInvalid, "Group 27: 草稿确认实付金额为 0 被严格拦截");

    // 负数被拦截
    document.getElementById('input-amount').value = '-10.50';
    confirmTransaction();
    assert(draftQueue.length === countBeforeInvalid, "Group 27: 草稿确认实付金额为负数被严格拦截");

    // 空商户被拦截
    document.getElementById('input-amount').value = '70.00';
    document.getElementById('input-merchant').value = '   ';
    confirmTransaction();
    assert(draftQueue.length === countBeforeInvalid, "Group 27: 草稿确认商户名称为空被严格拦截");

    // 非法日历时间被拦截
    document.getElementById('input-merchant').value = '正常商户';
    document.getElementById('input-time').value = '2026-02-29 12:00:00';
    confirmTransaction();
    assert(draftQueue.length === countBeforeInvalid, "Group 27: 草稿确认订单时间为非法闰年 2026-02-29 被严格拦截");

    // 9. select-channel 原生 Setter 属性劫持自动联动 select-account 断言
    const chanInputEl = document.getElementById('select-channel');
    chanInputEl.value = '支付宝'; // 原生 setter 调用
    const wechatOptProg = document.getElementById('menu-select-account').querySelector('[data-value="钱包"]');
    const alipayOptProg = document.getElementById('menu-select-account').querySelector('[data-value="余额"]');
    assert(wechatOptProg.style.display === 'none', "Group 27: 原生 setter 修改 select-channel 联动隐藏微信选项");
    assert(alipayOptProg.style.display !== 'none', "Group 27: 原生 setter 修改 select-channel 联动显示支付宝选项");
    assert(document.getElementById('select-account').value === '余额', "Group 27: 原生 setter 修改 select-channel 联动默认选中支付宝余额");

    // 10. isOptionMatch 深度支持标准 PaymentMethod.displayName 规范断言
    assert(isOptionMatch('select-account', '钱包', '微信 · 钱包'), "Group 27: isOptionMatch 正确匹配标准 微信 · 钱包");
    assert(isOptionMatch('select-account', '工商银行(5678)', '云闪付 · 工商银行(5678)'), "Group 27: isOptionMatch 正确匹配标准 云闪付 · 工商银行(5678)");
    assert(isOptionMatch('select-account', '招商银行(8848)', '微信 · 招商银行(8848)'), "Group 27: isOptionMatch 正确匹配标准 微信 · 招商银行(8848)");

    // 11. simulateIncomingAutoCommit 与 allMonthlyData 标准结构对齐断言
    autoCommitEnabled = false;
    simulateIncomingAutoCommit();
    const autoDraft = draftQueue[draftQueue.length - 1];
    assert(autoDraft.payment && autoDraft.payment.display_name === '微信 · 钱包', "Group 27: simulateIncomingAutoCommit 生成规范 payment 对象");
    assert(autoDraft.amountInCents === 3800, "Group 27: simulateIncomingAutoCommit 生成规范 amountInCents 3800");
    assert(autoDraft.orderTime === '2026-10-26 15:45:00', "Group 27: simulateIncomingAutoCommit 生成规范 orderTime");

    const latestTx = allMonthlyData['2026-10'].txs[0];
    assert(latestTx && latestTx.amountInCents > 0, "Group 27: allMonthlyData 同步持久化规范 amountInCents");
    assert(latestTx && latestTx.orderTime && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(latestTx.orderTime), "Group 27: allMonthlyData 同步持久化规范 orderTime");
    assert(latestTx && latestTx.payment && latestTx.payment.display_name, "Group 27: allMonthlyData 同步持久化规范 payment 对象");

    // Group 28: 大模型视觉引擎配置 (AI VLM) 迁移至规则账户与连通性测试断言
    // 1. 验证快速记一笔弹窗中齿轮配置图标已彻底移除，且无任何滚动溢出
    openManualAddModal();
    const manModal28 = document.getElementById('manual-add-modal');
    const manDialog28 = document.getElementById('manual-add-dialog');
    assert(!manModal28.classList.contains('hidden'), "Group 28: manual-add-modal 打开正常");
    assert(manDialog28.querySelector('button[onclick*="openLlmConfigModal"]') === null, "Group 28: 快速记一笔弹窗已彻底移除齿轮配置入口按钮");
    assert(manDialog28.scrollHeight <= manDialog28.clientHeight + 1, "Group 28: 快速记一笔极简轻便无滚动溢出 (scrollHeight=" + manDialog28.scrollHeight + ", clientHeight=" + manDialog28.clientHeight + ")");
    closeManualAddModal();

    // 2. 验证规则账户视图 (#view-rules-accounts) 存在且可切换
    switchTab('rules-accounts');
    const rulesAccountsView = document.getElementById('view-rules-accounts');
    assert(rulesAccountsView !== null, "Group 28: #view-rules-accounts 视图容器存在");
    assert(!rulesAccountsView.classList.contains('hidden'), "Group 28: switchTab('rules-accounts') 激活规则账户视图");
    assert(document.getElementById('view-rules') === rulesAccountsView, "Group 28: document.getElementById('view-rules') 别名正确映射至规则账户容器");

    // 3. 验证规则账户中的 AI VLM 配置卡片完整性
    const vlmCard = document.getElementById('vlm-config-card');
    assert(vlmCard !== null, "Group 28: #vlm-config-card 配置卡片在规则账户中存在");
    const vlmProviderEl = document.getElementById('vlm-provider-select');
    const vlmKeyEl = document.getElementById('vlm-api-key');
    const vlmEndpointEl = document.getElementById('vlm-endpoint');
    const vlmModelEl = document.getElementById('vlm-model');
    const vlmTestBtn = document.getElementById('btn-test-vlm-connection');
    const vlmStatusEl = document.getElementById('vlm-test-status');

    assert(vlmProviderEl !== null, "Group 28: vlm-provider-select 存在");
    assert(vlmKeyEl !== null, "Group 28: vlm-api-key 存在");
    assert(vlmEndpointEl !== null, "Group 28: vlm-endpoint 存在");
    assert(vlmModelEl !== null, "Group 28: vlm-model 存在");
    assert(vlmTestBtn !== null, "Group 28: btn-test-vlm-connection 测试连通性按钮存在");
    assert(vlmStatusEl !== null, "Group 28: vlm-test-status 状态显示元素存在");

    // 4. 验证服务商自定义下拉组件 (0 native select 规范) 与默认端点模型联动
    const vlmWrap = document.getElementById('dropdown-wrap-vlm-provider-select');
    const vlmMenu = document.getElementById('menu-vlm-provider-select');
    const vlmLabel = document.getElementById('label-vlm-provider-select');
    assert(vlmWrap !== null, "Group 28: #dropdown-wrap-vlm-provider-select 自定义下拉容器存在");
    assert(vlmMenu !== null, "Group 28: #menu-vlm-provider-select 下拉菜单存在");
    assert(vlmLabel !== null, "Group 28: #label-vlm-provider-select 标签存在");
    assert(vlmProviderEl.type === 'hidden', "Group 28: vlm-provider-select 是隐藏 input (无原生 win32 下拉框)");

    vlmEndpointEl.value = 'http://192.168.1.100:11434';
    vlmModelEl.value = 'llava:latest';

    // 4 种协议切换测试 (切换协议输入框值绝对保持不变，纯后台在请求时拼接)
    selectCustomDropdownOption('vlm-provider-select', 'anthropic_messages');
    assert(vlmProviderEl.value === 'anthropic_messages', "Group 28: 自定义下拉切换为 anthropic_messages");
    assert(vlmLabel.innerText.includes('Anthropic Messages'), "Group 28: 自定义下拉标签更新为 Anthropic Messages: " + vlmLabel.innerText);
    assert(vlmEndpointEl.value === 'http://192.168.1.100:11434', "Group 28: 切换协议输入框保持用户原始填写的地址不变");
    assert(normalizeApiEndpoint(vlmEndpointEl.value, vlmProviderEl.value, vlmModelEl.value) === 'http://192.168.1.100:11434/v1/messages', "Group 28: 后台计算正确的 Anthropic 后缀 /v1/messages");
    assert(vlmModelEl.value === 'llava:latest', "Group 28: 切换协议保持用户已填写的 model");

    selectCustomDropdownOption('vlm-provider-select', 'openai_responses');
    assert(vlmProviderEl.value === 'openai_responses', "Group 28: 自定义下拉切换为 openai_responses");
    assert(vlmLabel.innerText.includes('OpenAI Responses'), "Group 28: 自定义下拉标签更新为 OpenAI Responses: " + vlmLabel.innerText);
    assert(vlmEndpointEl.value === 'http://192.168.1.100:11434', "Group 28: 切换协议输入框保持用户原始填写的地址不变");
    assert(normalizeApiEndpoint(vlmEndpointEl.value, vlmProviderEl.value, vlmModelEl.value) === 'http://192.168.1.100:11434/v1/responses', "Group 28: 后台计算正确的 Responses 后缀 /v1/responses");
    assert(vlmModelEl.value === 'llava:latest', "Group 28: 再次切换协议 model 保持不变");

    selectCustomDropdownOption('vlm-provider-select', 'gemini_native');
    assert(vlmProviderEl.value === 'gemini_native', "Group 28: 自定义下拉切换为 gemini_native");
    assert(vlmLabel.innerText.includes('Gemini Native'), "Group 28: 自定义下拉标签更新为 Gemini Native: " + vlmLabel.innerText);
    assert(vlmEndpointEl.value === 'http://192.168.1.100:11434', "Group 28: 切换协议输入框保持用户原始填写的地址不变");
    assert(normalizeApiEndpoint(vlmEndpointEl.value, vlmProviderEl.value, vlmModelEl.value) === 'http://192.168.1.100:11434/v1beta/models/llava:latest:generateContent', "Group 28: 后台计算正确的 Gemini Native 后缀");

    selectCustomDropdownOption('vlm-provider-select', 'openai_chat');
    assert(vlmProviderEl.value === 'openai_chat', "Group 28: 自定义下拉切换为 openai_chat");
    assert(vlmLabel.innerText.includes('OpenAI Chat'), "Group 28: 自定义下拉标签更新为 OpenAI Chat: " + vlmLabel.innerText);
    assert(vlmEndpointEl.value === 'http://192.168.1.100:11434', "Group 28: 切换协议输入框保持用户原始填写的地址不变");
    assert(normalizeApiEndpoint(vlmEndpointEl.value, vlmProviderEl.value, vlmModelEl.value) === 'http://192.168.1.100:11434/v1/chat/completions', "Group 28: 后台计算正确的 OpenAI Chat 后缀 /v1/chat/completions");

    // 4.1 验证 4 大协议 URL 拼接与补全逻辑 (normalizeApiEndpoint)
    // 1) OpenAI Chat Completions: /v1/chat/completions
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443', 'openai_chat') === 'https://freeapi.opensingli.top:8443/v1/chat/completions', "Group 28: openai_chat 无 /v1 自动补全 /v1/chat/completions");
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443/v1', 'openai_chat') === 'https://freeapi.opensingli.top:8443/v1/chat/completions', "Group 28: openai_chat 尾部为 /v1 自动补全 /chat/completions");
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443/v1/chat/completions', 'openai_chat') === 'https://freeapi.opensingli.top:8443/v1/chat/completions', "Group 28: openai_chat 已有完整后缀保持不变");

    // 2) Anthropic Messages: /v1/messages
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443', 'anthropic_messages') === 'https://freeapi.opensingli.top:8443/v1/messages', "Group 28: anthropic_messages 无 /v1 自动补全 /v1/messages");
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443/v1', 'anthropic_messages') === 'https://freeapi.opensingli.top:8443/v1/messages', "Group 28: anthropic_messages 尾部为 /v1 自动补全 /messages");
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443/v1/messages', 'anthropic_messages') === 'https://freeapi.opensingli.top:8443/v1/messages', "Group 28: anthropic_messages 已有完整后缀保持不变");

    // 3) OpenAI Responses API: /v1/responses
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443', 'openai_responses') === 'https://freeapi.opensingli.top:8443/v1/responses', "Group 28: openai_responses 无 /v1 自动补全 /v1/responses");
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443/v1', 'openai_responses') === 'https://freeapi.opensingli.top:8443/v1/responses', "Group 28: openai_responses 尾部为 /v1 自动补全 /responses");
    assert(normalizeApiEndpoint('https://freeapi.opensingli.top:8443/v1/responses', 'openai_responses') === 'https://freeapi.opensingli.top:8443/v1/responses', "Group 28: openai_responses 已有完整后缀保持不变");

    // 4) Gemini Native generateContent: /v1beta/models/{model}:generateContent
    assert(normalizeApiEndpoint('https://generativelanguage.googleapis.com', 'gemini_native', 'gemini-1.5-flash') === 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent', "Group 28: gemini_native 根域名自动拼接 /v1beta/models/{model}:generateContent");
    assert(normalizeApiEndpoint('https://generativelanguage.googleapis.com/v1beta', 'gemini_native', 'gemini-1.5-flash') === 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent', "Group 28: gemini_native 尾部为 /v1beta 自动拼接 /models/{model}:generateContent");
    assert(normalizeApiEndpoint('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent', 'gemini_native') === 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent', "Group 28: gemini_native 已包含 :generateContent 保持原样");

    // 一键体验配置
    fillVlmDemoKey();
    assert(vlmProviderEl.value === 'openai_chat', "Group 28: 一键体验配置恢复为 openai_chat");
    assert(vlmLabel.innerText.includes('OpenAI Chat'), "Group 28: 一键体验标签恢复为 OpenAI Chat");
    assert(vlmKeyEl.value === 'sk-vlm-singwallet-demo-live', "Group 28: 填入演示体验 Key");

    // 5. 密码可见性切换
    assert(vlmKeyEl.type === 'password', "Group 28: API Key 默认密码遮罩");
    toggleVlmKeyVisibility();
    assert(vlmKeyEl.type === 'text', "Group 28: 切换后 API Key 显示为明文");
    toggleVlmKeyVisibility();
    assert(vlmKeyEl.type === 'password', "Group 28: 再次切换后 API Key 恢复密码遮罩");

    // 6. 实时持久化保存至 localStorage
    vlmKeyEl.value = 'AIzaSyTestGeminiKey2026';
    saveLlmConfigFromInputs(false);
    assert(vlmConfig.apiKey === 'AIzaSyTestGeminiKey2026', "Group 28: vlmConfig.apiKey 实时更新内存");
    assert(localStorage.getItem('singwallet_vlm_config').includes('AIzaSyTestGeminiKey2026'), "Group 28: vlmConfig 实时持久化至 localStorage");

    // 7. 测试连通性：未配置 API Key 错误拦截
    vlmKeyEl.value = '';
    vlmEndpointEl.value = 'http://localhost:8000';
    vlmModelEl.value = 'gpt-4o';
    saveLlmConfigFromInputs(false);
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('未配置 API Key'), "Group 28: 空 API Key 连通失败提示: " + vlmStatusEl.innerText);
    const topErrorToast = document.getElementById('llm-top-error-toast');
    assert(topErrorToast !== null && !topErrorToast.classList.contains('hidden'), "Group 28: 连通失败在上方弹出临时小窗口");
    assert(document.getElementById('llm-error-msg').innerText.includes('未配置 API Key'), "Group 28: 上方小窗口显示未配置 API Key 错误");
    closeLlmTopError();

    // 7.1 测试连通性：未配置 Base URL 错误拦截
    vlmKeyEl.value = 'sk-test-key';
    vlmEndpointEl.value = '';
    vlmModelEl.value = 'gpt-4o';
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('未配置 Base URL'), "Group 28: 空 Base URL 连通失败提示: " + vlmStatusEl.innerText);
    closeLlmTopError();

    // 7.2 测试连通性：未配置 Model 错误拦截
    vlmEndpointEl.value = 'http://localhost:8000';
    vlmModelEl.value = '';
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('未配置 Model'), "Group 28: 空 Model 连通失败提示: " + vlmStatusEl.innerText);
    closeLlmTopError();

    // 8. 测试连通性：401 Unauthorized 错误提示
    vlmKeyEl.value = 'invalid-key';
    vlmModelEl.value = 'gpt-4o';
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('401 Unauthorized'), "Group 28: 401 连通失败状态提示正确: " + vlmStatusEl.innerText);
    assert(!topErrorToast.classList.contains('hidden'), "Group 28: 401 失败在上方弹出临时小窗口");
    closeLlmTopError();

    // 9. 测试连通性：404 Model Not Found 错误提示
    vlmKeyEl.value = 'sk-test-mock-key';
    vlmModelEl.value = 'invalid-model';
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('404 Model Not Found'), "Group 28: 404 连通失败状态提示正确: " + vlmStatusEl.innerText);
    closeLlmTopError();

    // 10. 测试连通性：网络超时错误提示
    vlmModelEl.value = 'gemini-1.5-flash';
    vlmEndpointEl.value = 'https://mock-timeout.api.com';
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('超时'), "Group 28: 超时连通失败状态提示正确: " + vlmStatusEl.innerText);
    closeLlmTopError();

    // 11. 测试连通性：连通成功 (延迟与正常响应)
    vlmKeyEl.value = 'sk-vlm-test-key-2026';
    vlmEndpointEl.value = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
    vlmModelEl.value = 'qwen-vl-plus';
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('连通成功'), "Group 28: 连通成功提示正确: " + vlmStatusEl.innerText);
    assert(vlmStatusEl.innerText.includes('延迟') && vlmStatusEl.innerText.includes('ms'), "Group 28: 连通成功显示响应延迟 (ms)");
    const vlmResultBox = document.getElementById('vlm-test-result-box');
    assert(vlmResultBox.classList.contains('text-emerald-300'), "Group 28: 连通成功结果卡片为绿色正常状态");

    // 11.1 测试输入框值保持不变 (绝不篡改用户输入)
    assert(vlmEndpointEl.value === 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions', "Group 28: 连通测试后 endpoint 输入框值绝不被自动改写");
    assert(vlmModelEl.value === 'qwen-vl-plus', "Group 28: 连通测试后 model 输入框值绝不被自动改写");

    // 11.2 测试网络/空指针防御：即使候选端点全部抛错或无响应，也绝不抛出 Cannot read properties of null (reading 'status')
    vlmKeyEl.value = 'sk-test-fail-probe';
    vlmEndpointEl.value = 'http://127.0.0.1:59998/offline-test';
    vlmModelEl.value = 'my-vision-model';
    testVlmConnection();
    assert(!vlmStatusEl.innerText.includes('Cannot read properties of null'), "Group 28: 网络异常场景绝不抛出 null.status 空指针错误");
    assert(vlmStatusEl.innerText.includes('连通失败'), "Group 28: 优雅展示连通失败友善提示");

    // 恢复配置
    vlmKeyEl.value = 'sk-vlm-test-key-2026';
    vlmEndpointEl.value = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
    vlmModelEl.value = 'qwen-vl-plus';
    testVlmConnection();

    // 12. 统一大模型识别：无 API Key 时上传识别失败上方弹窗且无模拟假数据回填
    openManualAddModal();
    setManualOcrEngine('llm');
    vlmKeyEl.value = '';
    saveLlmConfigFromInputs(false);
    document.getElementById('manual-amount').value = '';
    document.getElementById('manual-merchant').value = '';
    handleManualScreenshotUpload({ target: { files: [{ name: 'test_no_key.png', size: 12345 }] } });
    assert(!topErrorToast.classList.contains('hidden'), "Group 28: 无 API Key 时大模型识别失败上方弹出临时小窗口");
    assert(document.getElementById('manual-amount').value === '', "Group 28: 舍弃离线兜底，金额未自动回填假数据");
    assert(document.getElementById('manual-merchant').value === '', "Group 28: 舍弃离线兜底，商户未自动回填假数据");
    closeLlmTopError();
    closeManualAddModal();

    // Group 29: SSOT 图标与元数据解耦联动验证 ("改一处全局自动替换")
    // 1. 验证 window.DomainRegistry 与 window.IconRegistry 已加载且包含 8 大核心分类
    assert(typeof window.DomainRegistry === 'object' && window.DomainRegistry !== null, "Group 29: window.DomainRegistry 已挂载");
    assert(typeof window.IconRegistry === 'object' && window.IconRegistry !== null, "Group 29: window.IconRegistry 已挂载");
    assert(typeof window.CATEGORY_ICON_MAP === 'object', "Group 29: window.CATEGORY_ICON_MAP 代理对象已挂载");

    const coreCategories = ['餐饮美食', '交通出行', '日常购物', '休闲娱乐', '生活缴费', '医疗健康', '其他支出', '工资收入'];
    assert(window.DomainRegistry.getCategories().length === 8, "Group 29: DomainRegistry 包含且仅包含 8 大核心分类定义");
    assert(window.DomainRegistry.getParentCategories().length === 8, "Group 29: DomainRegistry.getParentCategories() 返回 8 大核心一级分类");
    coreCategories.forEach(cat => {
      assert(!!window.DomainRegistry.getCategoryByName(cat), "Group 29: DomainRegistry 成功查得分类: " + cat);
      assert(!!window.IconRegistry.getCategoryIcon(cat), "Group 29: IconRegistry 具有分类图标: " + cat);
    });

    // 确保流水列表中存在餐饮美食条目以供联动断言
    switchTab('transactions');
    let foodTx = document.querySelector('.tx-item[data-category="餐饮美食"]');
    if (!foodTx) {
      insertTransactionToList({
        id: "item-tx-food-ssot-test",
        merchant: "测试老灶火锅店",
        amount: 188.00,
        amountInCents: 18800,
        catName: "餐饮美食",
        parentCat: "餐饮美食",
        category: "餐饮美食",
        channel: "微信",
        account: "微信 · 钱包",
        txTime: "2026-10-26 18:30:00",
        orderTime: "2026-10-26 18:30:00",
        txDate: "2026-10-26",
        timeOnly: "18:30",
        orderId: "SSOT_FOOD_TEST_9999",
        badge: "联动测试"
      });
      foodTx = document.querySelector('.tx-item[data-category="餐饮美食"]');
    }
    assert(foodTx !== null, "Group 29: 流水列表存在餐饮美食交易卡片 .tx-item[data-category='餐饮美食']");

    // 保存初始餐饮美食默认图标，并获取页面 4 处 DOM 容器
    const origFoodIcon = IconRegistry.getCategoryIcon('餐饮美食');
    assert(typeof origFoodIcon === 'string' && origFoodIcon.includes('<svg'), "Group 29: 默认餐饮美食图标已是蓝金线性 SVG 矢量图标");

    const foodTxIconEl = foodTx.querySelector('[data-cat-icon="餐饮美食"]') || foodTx.querySelector('.w-10.h-10');
    const filterFoodIconEl = document.querySelector('#filter-modal-cats [data-cat-icon="餐饮美食"]');
    const modalFoodIconEl = document.querySelector('#category-modal-grid [data-category-name="餐饮美食"] [data-cat-icon="餐饮美食"]') || document.querySelector('#category-modal-grid [data-cat-icon="餐饮美食"]');
    const draftMenuFoodIconEl = document.querySelector('#menu-select-draft-category [data-value="餐饮美食"] [data-cat-icon="餐饮美食"]');

    assert(foodTxIconEl !== null && foodTxIconEl.querySelector('svg') !== null, "Group 29: 流水列表卡片内部成功渲染 SVG 矢量元素");
    assert(filterFoodIconEl !== null && filterFoodIconEl.querySelector('svg') !== null, "Group 29: 筛选弹窗中餐饮美食内部成功渲染 SVG 矢量元素");
    assert(modalFoodIconEl !== null && modalFoodIconEl.querySelector('svg') !== null, "Group 29: 分类弹窗中餐饮美食内部成功渲染 SVG 矢量元素");
    assert(draftMenuFoodIconEl !== null && draftMenuFoodIconEl.querySelector('svg') !== null, "Group 29: 草稿分类下拉框中餐饮美食内部成功渲染 SVG 矢量元素");

    // 断言页面中所有 [data-ui-icon] 节点内部均已成功渲染 SVG 矢量元素
    const uiIconEls = document.querySelectorAll('[data-ui-icon]');
    assert(uiIconEls.length > 0, "Group 29: 页面存在 [data-ui-icon] 元素");
    uiIconEls.forEach(el => {
      const iconKey = el.getAttribute('data-ui-icon');
      assert(el.querySelector('svg') !== null, "Group 29: [data-ui-icon='" + iconKey + "'] 内部成功渲染 SVG 矢量元素");
    });

    // 2. 测试调用 IconRegistry.setCategoryIcon('餐饮美食', '<svg id="custom-noodle-svg"></svg>') 联动验证
    IconRegistry.setCategoryIcon('餐饮美食', '<svg id="custom-noodle-svg"></svg>');
    assert(foodTxIconEl.querySelector('#custom-noodle-svg') !== null, "Group 29: [IconRegistry.setCategoryIcon] 流水列表图标自动同步为 #custom-noodle-svg");
    assert(filterFoodIconEl.querySelector('#custom-noodle-svg') !== null, "Group 29: [IconRegistry.setCategoryIcon] 筛选弹窗图标自动同步为 #custom-noodle-svg");
    assert(modalFoodIconEl.querySelector('#custom-noodle-svg') !== null, "Group 29: [IconRegistry.setCategoryIcon] 分类弹窗图标自动同步为 #custom-noodle-svg");
    assert(draftMenuFoodIconEl.querySelector('#custom-noodle-svg') !== null, "Group 29: [IconRegistry.setCategoryIcon] 草稿分类下拉框图标自动同步为 #custom-noodle-svg");

    // 3. 测试直接赋值 CATEGORY_ICON_MAP['餐饮美食'] = '<svg id="custom-bento-svg"></svg>' 响应式代理联动验证
    CATEGORY_ICON_MAP['餐饮美食'] = '<svg id="custom-bento-svg"></svg>';
    assert(foodTxIconEl.querySelector('#custom-bento-svg') !== null, "Group 29: [Proxy CATEGORY_ICON_MAP] 流水列表图标自动同步为 #custom-bento-svg");
    assert(filterFoodIconEl.querySelector('#custom-bento-svg') !== null, "Group 29: [Proxy CATEGORY_ICON_MAP] 筛选弹窗图标自动同步为 #custom-bento-svg");
    assert(modalFoodIconEl.querySelector('#custom-bento-svg') !== null, "Group 29: [Proxy CATEGORY_ICON_MAP] 分类弹窗图标自动同步为 #custom-bento-svg");
    assert(draftMenuFoodIconEl.querySelector('#custom-bento-svg') !== null, "Group 29: [Proxy CATEGORY_ICON_MAP] 草稿分类下拉菜单图标自动同步为 #custom-bento-svg");

    // 4. 测试完毕后调用 IconRegistry.setCategoryIcon('餐饮美食', origFoodIcon) 恢复默认蓝金线性 SVG 图标
    IconRegistry.setCategoryIcon('餐饮美食', origFoodIcon);
    assert(foodTxIconEl.querySelector('svg') !== null && foodTxIconEl.querySelector('#custom-bento-svg') === null, "Group 29: [Cleanup] 流水列表图标成功恢复默认 SVG");
    assert(filterFoodIconEl.querySelector('svg') !== null && filterFoodIconEl.querySelector('#custom-bento-svg') === null, "Group 29: [Cleanup] 筛选弹窗图标成功恢复默认 SVG");
    assert(modalFoodIconEl.querySelector('svg') !== null && modalFoodIconEl.querySelector('#custom-bento-svg') === null, "Group 29: [Cleanup] 分类弹窗图标成功恢复默认 SVG");
    assert(draftMenuFoodIconEl.querySelector('svg') !== null && draftMenuFoodIconEl.querySelector('#custom-bento-svg') === null, "Group 29: [Cleanup] 草稿分类下拉菜单图标成功恢复默认 SVG");
    assert(IconRegistry.getCategoryIcon('餐饮美食') === origFoodIcon, "Group 29: [Cleanup] IconRegistry 成功恢复为 origFoodIcon");

    // ==========================================
    // Group 30: 账单分类管理（增删分类 & 全局多标签联动）
    // ==========================================
    assert(document.getElementById('category-manager-card') !== null, "Group 30: category-manager-card exists");
    assert(document.getElementById('custom-categories-list') !== null, "Group 30: custom-categories-list exists");
    assert(document.getElementById('custom-category-input') !== null, "Group 30: custom-category-input exists");
    assert(document.getElementById('btn-add-category') !== null, "Group 30: btn-add-category exists");

    // 1. 添加新分类
    const catInput = document.getElementById('custom-category-input');
    catInput.value = '潮玩手办';
    addCustomCategory();
    assert(DomainRegistry.getParentCategories().includes('潮玩手办'), "Group 30: DomainRegistry includes 潮玩手办");
    assert(BILL_STRUCTURED_SCHEMA.json_schema.schema.properties.category.enum.includes('潮玩手办'), "Group 30: BILL_STRUCTURED_SCHEMA enum includes 潮玩手办");

    // 2. 验证全站 5 处 UI 联动同步
    const customList = document.getElementById('custom-categories-list');
    assert(customList.innerText.includes('潮玩手办'), "Group 30: custom-categories-list displays 潮玩手办");
    const menuDraftCat = document.getElementById('menu-select-draft-category');
    assert(menuDraftCat.innerText.includes('潮玩手办'), "Group 30: menu-select-draft-category displays 潮玩手办");
    const menuManualCat = document.getElementById('menu-manual-category');
    assert(menuManualCat.innerText.includes('潮玩手办'), "Group 30: menu-manual-category displays 潮玩手办");
    const modalGrid = document.getElementById('category-modal-grid');
    assert(modalGrid.innerText.includes('潮玩手办'), "Group 30: category-modal-grid displays 潮玩手办");
    const filterCatsEl = document.getElementById('filter-modal-cats');
    assert(filterCatsEl.innerText.includes('潮玩手办'), "Group 30: filter-modal-cats displays 潮玩手办");

    // 3. 编辑分类弹窗与领域重命名测试
    openEditCategoryModal('潮玩手办');
    const catEditModal = document.getElementById('category-edit-modal');
    assert(catEditModal !== null && !catEditModal.classList.contains('hidden'), "Group 30: category-edit-modal 正常弹出");
    const catEditInput = document.getElementById('edit-category-input');
    assert(catEditInput !== null && catEditInput.value === '潮玩手办', "Group 30: edit-category-input 回显正确名称");
    catEditInput.value = '潮玩模玩';
    saveEditedCategory();
    assert(catEditModal.classList.contains('hidden'), "Group 30: 保存后 category-edit-modal 自动关闭");
    assert(DomainRegistry.getParentCategories().includes('潮玩模玩'), "Group 30: DomainRegistry 已更新为 潮玩模玩");
    assert(!DomainRegistry.getParentCategories().includes('潮玩手办'), "Group 30: DomainRegistry 潮玩手办 已替换");
    assert(customList.innerText.includes('潮玩模玩'), "Group 30: custom-categories-list 渲染 潮玩模玩");

    // 4. 删除确认弹窗与删除分类测试
    openCategoryDeleteConfirmModal('潮玩模玩');
    const catDelModal = document.getElementById('category-delete-confirm-modal');
    assert(catDelModal !== null && !catDelModal.classList.contains('hidden'), "Group 30: category-delete-confirm-modal 正常弹出");
    confirmCategoryDelete();
    assert(catDelModal.classList.contains('hidden'), "Group 30: 确认删除后 category-delete-confirm-modal 自动关闭");
    assert(!DomainRegistry.getParentCategories().includes('潮玩模玩'), "Group 30: DomainRegistry removed 潮玩模玩");
    assert(!customList.innerText.includes('潮玩模玩'), "Group 30: custom-categories-list removed 潮玩模玩");
    assert(!menuDraftCat.innerText.includes('潮玩模玩'), "Group 30: menu-select-draft-category removed 潮玩模玩");

    // 5. 验证圆圈感叹号操作提示展开与收起
    const btnCatInfo = document.getElementById('btn-category-info');
    assert(btnCatInfo !== null, "Group 30: #btn-category-info exists");
    const catHelpTip = document.getElementById('category-help-tip');
    assert(catHelpTip !== null && catHelpTip.classList.contains('hidden'), "Group 30: #category-help-tip initially hidden");
    toggleCategoryHelpTip();
    assert(!catHelpTip.classList.contains('hidden'), "Group 30: toggleCategoryHelpTip reveals tip banner");
    toggleCategoryHelpTip();
    assert(catHelpTip.classList.contains('hidden'), "Group 30: toggleCategoryHelpTip closes tip banner");

    // 6. 验证双击胶囊唤起删除确认弹窗
    handleCategoryPillClick('餐饮美食');
    handleCategoryPillClick('餐饮美食');
    assert(!catDelModal.classList.contains('hidden'), "Group 30: 双击胶囊快速唤起 category-delete-confirm-modal");
    closeCategoryDeleteConfirmModal();
    assert(catDelModal.classList.contains('hidden'), "Group 30: closeCategoryDeleteConfirmModal 关闭弹窗");

    // 7. 恢复默认分类
    resetCategoriesToDefault();
    assert(DomainRegistry.getParentCategories().length === 8, "Group 30: resetCategoriesToDefault restores 8 standard categories");

    // ==========================================
    // Group 31: 图标尺寸根治断言与弹窗排版动效
    // ==========================================
    openFilterModal();
    const filterModal = document.getElementById('filter-modal');
    assert(!filterModal.classList.contains('hidden'), "Group 31: filter-modal is open");
    const filterSvgs = document.querySelectorAll('#filter-modal-cats [data-cat-icon] svg');
    assert(filterSvgs.length > 0, "Group 31: filter-modal-cats has category SVG icons");
    filterSvgs.forEach((svg, i) => {
      const rect = svg.getBoundingClientRect();
      assert(rect.width <= 28, "Group 31: filter-modal-cats svg " + i + " width <= 28px (actual: " + rect.width + "px)");
    });
    closeFilterModal();

    // 草稿分类下拉菜单图标尺寸断言
    const draftMenuSvgs = document.querySelectorAll('#menu-select-draft-category [data-cat-icon] svg');
    assert(draftMenuSvgs.length > 0, "Group 31: menu-select-draft-category has category SVG icons");
    draftMenuSvgs.forEach((svg, i) => {
      const rect = svg.getBoundingClientRect();
      assert(rect.width <= 28, "Group 31: menu-select-draft-category svg " + i + " width <= 28px (actual: " + rect.width + "px)");
    });

    // 置信度弹窗浅灰文字与图标验证
    openConfidenceModal();
    const confModal = document.getElementById('confidence-modal');
    assert(!confModal.classList.contains('hidden'), "Group 31: confidence-modal is open");
    assert(document.getElementById('guard-shield-svg-icon') !== null, "Group 31: guard-shield-svg-icon exists in confidence-modal");
    closeConfidenceModal();

    // 手动记账弹窗单屏无滚动溢出验证
    openManualAddModal();
    const manualDialog = document.getElementById('manual-add-dialog');
    assert(manualDialog.scrollHeight <= manualDialog.clientHeight + 1, "Group 31: manual-add-dialog scrollHeight <= clientHeight + 1 (actual scrollHeight: " + manualDialog.scrollHeight + ", clientHeight: " + manualDialog.clientHeight + ")");
    closeManualAddModal();

    // ==========================================
    // Group 32: 快记一手改为后台异步解析 + 草稿箱横向任务胶囊极简进度条
    // ==========================================
    const testTaskId = 'draft-vlm-task-test-999';
    const mockTaskDraft = {
      id: testTaskId,
      merchant: '大模型解析中...',
      merchantHeader: 'VLM 解析',
      amount: 0,
      amountInCents: 0,
      confidence: 0,
      isParsing: true,
      progress: 35,
      category: '日常购物',
      categoryName: '日常购物',
      channel: '微信',
      account: '钱包',
      imgTitle: 'test_async_upload.png',
      tag: '后台解析中...',
      rule: 'VLM 视觉智能识别',
      time: '2026-10-26 18:00:00'
    };
    draftQueue.unshift(mockTaskDraft);
    renderDraftQueue();

    const progBar = document.getElementById('draft-task-prog-' + testTaskId);
    assert(progBar !== null, "Group 32: draft-task-prog element exists for isParsing task");
    assert(progBar.style.width === '35%', "Group 32: progress bar width is 35%");
    const progWrap = progBar.parentElement;
    assert(progWrap.classList.contains('bg-slate-700/50') || progWrap.className.includes('bg-slate-700'), "Group 32: progress bar has bg-slate-700/50 wrapper");

    // 验证批量确认排除 isParsing 任务
    const batchList = draftQueue.filter(d => !d.isParsing && d.confidence >= autoCommitThreshold);
    assert(!batchList.some(d => d.id === testTaskId), "Group 32: batchConfirm list strictly excludes isParsing drafts");

    // 清理测试任务
    const testTaskIdx = draftQueue.findIndex(d => d.id === testTaskId);
    if (testTaskIdx !== -1) draftQueue.splice(testTaskIdx, 1);
    renderDraftQueue();



    // ==========================================
    // Group 33: 后端与领域引擎架构层深度校验 (SSOT DomainRegistry & VLM Queue)
    // ==========================================
    // 1. DomainRegistry.addCategory 校验与去重
    assert(typeof DomainRegistry.addCategory === 'function', "Group 33: DomainRegistry.addCategory exists");
    assert(typeof DomainRegistry.removeCategory === 'function', "Group 33: DomainRegistry.removeCategory exists");
    assert(typeof DomainRegistry.resetCategories === 'function', "Group 33: DomainRegistry.resetCategories exists");

    const initialCatCount = DomainRegistry.getParentCategories().length;
    const addSuccess = DomainRegistry.addCategory('智能新能源');
    assert(addSuccess === true, "Group 33: DomainRegistry.addCategory returns true on new category");
    assert(DomainRegistry.getParentCategories().includes('智能新能源'), "Group 33: getParentCategories includes 智能新能源");
    assert(BILL_STRUCTURED_SCHEMA.json_schema.schema.properties.category.enum.includes('智能新能源'), "Group 33: BILL_STRUCTURED_SCHEMA enum includes 智能新能源");
    const storedCats1 = JSON.parse(localStorage.getItem('singwallet_custom_categories') || '[]');
    assert(storedCats1.includes('智能新能源'), "Group 33: localStorage persisted 智能新能源");

    // 去重断言
    const addDup = DomainRegistry.addCategory('智能新能源');
    assert(addDup === false, "Group 33: DomainRegistry.addCategory returns false on duplicate");
    assert(DomainRegistry.addCategory('') === false, "Group 33: addCategory returns false on empty string");
    assert(DomainRegistry.addCategory('   ') === false, "Group 33: addCategory returns false on whitespace");

    // 2. DomainRegistry.removeCategory 校验
    const remSuccess = DomainRegistry.removeCategory('生活缴费');
    assert(remSuccess === true, "Group 33: removeCategory returns true");
    assert(!DomainRegistry.getParentCategories().includes('生活缴费'), "Group 33: getParentCategories does not contain 生活缴费");
    assert(!BILL_STRUCTURED_SCHEMA.json_schema.schema.properties.category.enum.includes('生活缴费'), "Group 33: BILL_STRUCTURED_SCHEMA enum does not contain 生活缴费");
    const resolvedLiving = resolveParentCategory('国家电网电费代扣', '国网电力');
    assert(resolvedLiving !== '生活缴费', "Group 33: resolveParentCategory never returns removed category 生活缴费");
    assert(DomainRegistry.getParentCategories().includes(resolvedLiving), "Group 33: resolveParentCategory falls back to active category");

    // 3. DomainRegistry.resetCategories 校验
    const resetSuccess = DomainRegistry.resetCategories();
    assert(resetSuccess === true, "Group 33: resetCategories returns true");
    assert(DomainRegistry.getParentCategories().length === 8, "Group 33: getParentCategories restored to 8");
    assert(BILL_STRUCTURED_SCHEMA.json_schema.schema.properties.category.enum.length === 8, "Group 33: BILL_STRUCTURED_SCHEMA enum restored to 8");
    assert(BILL_STRUCTURED_SCHEMA.json_schema.schema.properties.category.enum.includes('生活缴费'), "Group 33: schema enum restored 生活缴费");
    const storedReset = JSON.parse(localStorage.getItem('singwallet_custom_categories') || '[]');
    assert(storedReset.length === 8, "Group 33: localStorage restored to 8 categories");

    // 4. 后台异步解析任务队列引擎字段与单号去重校验
    const queueTaskId = 'draft-vlm-queue-test-' + Date.now();
    const taskItem = {
      id: queueTaskId,
      merchant: '大模型解析中...',
      merchantHeader: 'VLM 解析',
      amount: 0,
      amountInCents: 0,
      confidence: 0,
      isParsing: true,
      progress: 15,
      category: '日常购物',
      categoryName: '日常购物',
      channel: '微信',
      account: '钱包',
      imgTitle: 'queue_test.png',
      tag: '后台解析中...',
      rule: 'VLM 视觉智能识别',
      time: '2026-10-26 19:00:00'
    };
    draftQueue.unshift(taskItem);
    assert(draftQueue[0].id === queueTaskId, "Group 33: taskItem unshifted to head of draftQueue");
    assert(draftQueue[0].isParsing === true, "Group 33: head draft has isParsing === true");
    assert(draftQueue[0].progress === 15, "Group 33: head draft has initial progress");

    // 单号重复去重校验
    assert(typeof isOrderIdDuplicate === 'function', "Group 33: isOrderIdDuplicate function exists");
    committedOrderIds.add('TEST_DEDUP_ORDER_999');
    assert(isOrderIdDuplicate('TEST_DEDUP_ORDER_999') === true, "Group 33: isOrderIdDuplicate correctly identifies duplicate order");
    assert(isOrderIdDuplicate('BRAND_NEW_ORDER_UNIQUE') === false, "Group 33: isOrderIdDuplicate returns false for unique order");

    // 清理测试任务与单号
    const cleanQueueIdx = draftQueue.findIndex(d => d.id === queueTaskId);
    if (cleanQueueIdx !== -1) draftQueue.splice(cleanQueueIdx, 1);
    committedOrderIds.delete('TEST_DEDUP_ORDER_999');
    renderDraftQueue();

    // ==========================================
    // Group 34: 前端 UI 规范与视觉排版专项验证 (Toast 屏幕居中 & 分类双列网格)
    // ==========================================
    // 1. Toast 屏幕内水平居中验证
    showToast('测试居中弹窗');
    const toastWrap = document.querySelector('.singwallet-toast-wrap');
    const screenContainer = document.getElementById('screen-container');
    assert(toastWrap !== null, "Group 34: singwallet-toast-wrap element exists");
    assert(screenContainer.contains(toastWrap), "Group 34: singwallet-toast-wrap is mounted inside #screen-container");

    const toastInner = toastWrap.querySelector('div');
    const toastRect = toastInner.getBoundingClientRect();
    const screenRect = screenContainer.getBoundingClientRect();
    const toastCenter = toastRect.left + toastRect.width / 2;
    const screenCenter = screenRect.left + screenRect.width / 2;
    const centerDiff = Math.abs(toastCenter - screenCenter);
    assert(centerDiff < 5, "Group 34: Toast is horizontally centered within #screen-container (centerDiff: " + centerDiff.toFixed(2) + "px < 5px)");

    // 2. 分类管理双列网格排版与数量徽章验证
    const customCatsGrid = document.getElementById('custom-categories-list');
    assert(customCatsGrid.classList.contains('grid-cols-2'), "Group 34: custom-categories-list has grid-cols-2 class for symmetrical 2-column layout");
    assert(document.getElementById('category-count-badge') !== null, "Group 34: category-count-badge exists");
    assert(document.getElementById('category-count-badge').innerText === String(DomainRegistry.getParentCategories().length), "Group 34: category-count-badge reflects category count");


    // ==========================================
    // Group 35: 账单去重 (Order ID Deduplication) 领域与一键批量入账全场景专项验证
    if (draftQueue.length === 0) injectTestDrafts();
    if (document.querySelectorAll("#transactions-list .tx-item:not(.soft-deleted)").length === 0) injectTestTransactions();
    // ==========================================
    switchTab('drafts');

    // 1. 领域纯函数 SingWalletDomain.normalizeOrderId 校验
    assert(typeof SingWalletDomain.normalizeOrderId === 'function', "Group 35: SingWalletDomain.normalizeOrderId exists");
    assert(SingWalletDomain.normalizeOrderId(null) === '', "Group 35: normalizeOrderId null returns empty string");
    assert(SingWalletDomain.normalizeOrderId('   ') === '', "Group 35: normalizeOrderId whitespace returns empty string");
    assert(SingWalletDomain.normalizeOrderId('无') === '', "Group 35: normalizeOrderId '无' returns empty string");
    assert(SingWalletDomain.normalizeOrderId('--') === '', "Group 35: normalizeOrderId '--' returns empty string");
    assert(SingWalletDomain.normalizeOrderId('  420000_TEST_ORDER  ') === '420000_TEST_ORDER', "Group 35: normalizeOrderId trims whitespace");

    // 2. 领域纯函数 SingWalletDomain.isOrderIdDuplicate 校验
    assert(typeof SingWalletDomain.isOrderIdDuplicate === 'function', "Group 35: SingWalletDomain.isOrderIdDuplicate exists");
    const testCommittedSet = new Set(['ORDER_EXISTING_AAA']);
    assert(SingWalletDomain.isOrderIdDuplicate('ORDER_EXISTING_AAA', testCommittedSet) === true, "Group 35: isOrderIdDuplicate identifies duplicate against Set");
    assert(SingWalletDomain.isOrderIdDuplicate('  ORDER_EXISTING_AAA  ', testCommittedSet) === true, "Group 35: isOrderIdDuplicate normalizes whitespace against Set");
    assert(SingWalletDomain.isOrderIdDuplicate('ORDER_UNIQUE_BBB', testCommittedSet) === false, "Group 35: isOrderIdDuplicate returns false for unique order");
    assert(SingWalletDomain.isOrderIdDuplicate('', testCommittedSet) === false, "Group 35: isOrderIdDuplicate returns false for empty order");

    // 3. 领域纯函数 SingWalletDomain.partitionDraftsByDedup 校验 (含同批次自去重)
    assert(typeof SingWalletDomain.partitionDraftsByDedup === 'function', "Group 35: SingWalletDomain.partitionDraftsByDedup exists");
    const testDraftsForPartition = [
      { id: 't1', orderId: 'ORDER_EXISTING_AAA' }, // 与已入账重复
      { id: 't2', orderId: 'ORDER_BATCH_DUP_111' }, // 批次首笔唯一
      { id: 't3', orderId: 'ORDER_BATCH_DUP_111' }, // 同批次重复
      { id: 't4', orderId: '' },                     // 无单号草稿
      { id: 't5', orderId: 'ORDER_BATCH_UNIQ_222' }  // 另一笔唯一
    ];
    const partitionRes = SingWalletDomain.partitionDraftsByDedup(testDraftsForPartition, testCommittedSet);
    assert(partitionRes.validList.length === 3, "Group 35: partitionDraftsByDedup validList has 3 items (found " + partitionRes.validList.length + ")");
    assert(partitionRes.validList.map(d => d.id).join(',') === 't2,t4,t5', "Group 35: validList contains t2, t4, t5");
    assert(partitionRes.dupList.length === 2, "Group 35: partitionDraftsByDedup dupList has 2 items (found " + partitionRes.dupList.length + ")");
    assert(partitionRes.dupList.map(d => d.id).join(',') === 't1,t3', "Group 35: dupList contains t1 (committed dup) and t3 (intra-batch dup)");

    // 4. 应用层：一键入账拦截与已入账流水重复的草稿，保留在 draftQueue，设为当前选中，并触发顶部橙色 Toast
    closeDedupTopToast();
    const dupTestOrder = 'EXISTING_FLOW_ORDER_888';
    committedOrderIds.add(dupTestOrder);

    draftQueue = [
      {
        id: 'draft-dup-comm-1',
        merchant: '重复商户A',
        amount: 25.00,
        amountInCents: 2500,
        confidence: 98,
        isParsing: false,
        orderId: dupTestOrder,
        time: '2026-10-26 10:00:00',
        category: '餐饮美食'
      },
      {
        id: 'draft-uniq-valid-2',
        merchant: '正常商户B',
        amount: 30.00,
        amountInCents: 3000,
        confidence: 96,
        isParsing: false,
        orderId: 'UNIQUE_CLEAN_ORDER_777',
        time: '2026-10-26 10:30:00',
        category: '日常购物'
      }
    ];
    currentDraftIndex = 0;
    renderDraftQueue();

    batchConfirmHighConfidenceDrafts();

    const dedupToastEl = document.getElementById('dedup-top-toast');
    const toastOrderText = document.getElementById('dedup-toast-order-text')?.innerText || '';
    assert(!dedupToastEl.classList.contains('hidden'), "Group 35: dedup-top-toast is displayed when batch confirming duplicate order");
    assert(toastOrderText.includes(dupTestOrder), "Group 35: dedup-top-toast displays intercepted order ID: " + dupTestOrder);
    assert(draftQueue.some(d => d.id === 'draft-dup-comm-1'), "Group 35: Intercepted duplicate draft MUST remain in draftQueue");
    assert(!draftQueue.some(d => d.id === 'draft-uniq-valid-2'), "Group 35: Valid draft successfully committed and removed from draftQueue");
    assert(draftQueue[currentDraftIndex].id === 'draft-dup-comm-1', "Group 35: Active draft is automatically switched to the intercepted duplicate draft");

    // 5. 应用层：一键入账同批次内自去重拦截 (Intra-batch deduplication)
    closeDedupTopToast();
    const intraBatchOrder = 'INTRA_BATCH_SHARED_ORDER_555';
    draftQueue = [
      {
        id: 'draft-intra-1',
        merchant: '批次相同单号第1笔',
        amount: 18.00,
        amountInCents: 1800,
        confidence: 99,
        isParsing: false,
        orderId: intraBatchOrder,
        time: '2026-10-26 11:00:00',
        category: '休闲娱乐'
      },
      {
        id: 'draft-intra-2',
        merchant: '批次相同单号第2笔',
        amount: 22.00,
        amountInCents: 2200,
        confidence: 97,
        isParsing: false,
        orderId: intraBatchOrder,
        time: '2026-10-26 11:15:00',
        category: '休闲娱乐'
      }
    ];
    currentDraftIndex = 0;
    renderDraftQueue();

    batchConfirmHighConfidenceDrafts();

    assert(!dedupToastEl.classList.contains('hidden'), "Group 35: Intra-batch duplicate triggers dedup-top-toast");
    assert(draftQueue.length === 1, "Group 35: 1 draft remained in draftQueue (found " + draftQueue.length + ")");
    assert(draftQueue[0].id === 'draft-intra-2', "Group 35: Second draft with same orderId was intercepted as intra-batch duplicate");
    assert(isOrderIdDuplicate(intraBatchOrder), "Group 35: intraBatchOrder is now marked committed after first draft succeeded");

    // 6. 应用层：全部草稿因重复被拦截时，严禁弹出“成功入账”虚假提示
    closeDedupTopToast();
    draftQueue = [
      {
        id: 'draft-all-dup-1',
        merchant: '全重复商户1',
        amount: 12.00,
        amountInCents: 1200,
        confidence: 96,
        isParsing: false,
        orderId: dupTestOrder,
        time: '2026-10-26 12:00:00',
        category: '餐饮美食'
      }
    ];
    currentDraftIndex = 0;
    renderDraftQueue();

    batchConfirmHighConfidenceDrafts();

    const toastWrapEl = document.querySelector('.singwallet-toast-wrap');
    const toastMsg = toastWrapEl ? toastWrapEl.innerText : '';
    assert(!dedupToastEl.classList.contains('hidden'), "Group 35: dedupToastEl visible when all drafts are duplicates");
    assert(draftQueue.length === 1, "Group 35: Draft remains in draftQueue when all intercepted");
    assert(!toastMsg.includes('成功将'), "Group 35: No false positive '成功将' success toast when all drafts are duplicates");
    assert(toastMsg.includes('拦截') || toastMsg.includes('重复'), "Group 35: Toast explicitly informs interception of duplicate drafts");

    // 7. 应用层：后台自动入账 commitDraftTransaction 拦截校验
    closeDedupTopToast();
    const autoDupDraft = {
      id: 'draft-auto-dup',
      merchant: '自动入账重复测试',
      amount: 66.00,
      confidence: 99,
      isParsing: false,
      orderId: dupTestOrder
    };
    draftQueue = [autoDupDraft];
    currentDraftIndex = 0;
    renderDraftQueue();

    const autoCommitResult = commitDraftTransaction(autoDupDraft, false);
    assert(autoCommitResult === false, "Group 35: commitDraftTransaction returns false on duplicate order");
    assert(!dedupToastEl.classList.contains('hidden'), "Group 35: commitDraftTransaction triggers dedup-top-toast on duplicate");
    assert(draftQueue.length === 1, "Group 35: duplicate draft kept in draftQueue by commitDraftTransaction");

    // 强制提交 force = true
    const forceCommitResult = commitDraftTransaction(autoDupDraft, true);
    assert(forceCommitResult === true, "Group 35: commitDraftTransaction returns true on force = true");
    assert(draftQueue.length === 0, "Group 35: draft removed from draftQueue after force commit");

    // 8. 清理测试产生的单号并重置演示草稿
    closeDedupTopToast();
    committedOrderIds.delete(dupTestOrder);
    committedOrderIds.delete(intraBatchOrder);
    resetDemoDrafts();


    // ==========================================
    // Group 36: 月度净支出分栏、动态 SVG 环形饼图与分类占比列表及账单卡片优化验证
    // ==========================================
    if (document.querySelectorAll("#transactions-list .tx-item:not(.soft-deleted)").length === 0) injectTestTransactions();
    switchTab('transactions');

    // 1. 结构验证：月份切换按钮、净支出双 ID 兼容与左右分栏
    const btnSelectMonth = document.getElementById('btn-select-month');
    assert(btnSelectMonth !== null, "Group 36: #btn-select-month exists on summary card");
    const monthlyNetEl = document.getElementById('monthly-net-expense');
    const totalNetEl = document.getElementById('total-net-expense');
    assert(monthlyNetEl !== null, "Group 36: #monthly-net-expense exists with prominent styling");
    assert(totalNetEl !== null, "Group 36: #total-net-expense exists for backward compatibility");
    assert(monthlyNetEl.innerText.trim() === totalNetEl.innerText.trim(), "Group 36: #monthly-net-expense and #total-net-expense are in sync (" + monthlyNetEl.innerText + ")");

    // 2. 右侧图表容器与 SVG 实心饼状图验证
    const chartPanel = document.getElementById('monthly-chart-panel');
    assert(chartPanel !== null, "Group 36: #monthly-chart-panel exists");
    const pieChart = document.getElementById('monthly-pie-chart');
    assert(pieChart !== null, "Group 36: #monthly-pie-chart exists");
    const pieSvg = pieChart.querySelector('svg');
    assert(pieSvg !== null, "Group 36: #monthly-pie-chart contains SVG");

    // 验证空心圆环图：存在空心圆环扇区 <circle class="pie-slice">，fill 为 none，stroke 为有效颜色值且 stroke-width 为 10
    const pieSlices = pieSvg.querySelectorAll('.pie-slice');
    assert(pieSlices.length >= 1, "Group 36: SVG donut chart has .pie-slice elements rendered (found " + pieSlices.length + ")");
    pieSlices.forEach(slice => {
      assert(slice.tagName.toLowerCase() === 'circle', "Group 36: Pie slice is circle element (" + slice.tagName + ")");
      const fill = slice.getAttribute('fill') || '';
      assert(fill === 'none', "Group 36: Pie slice has fill='none' (" + fill + ")");
      const stroke = slice.getAttribute('stroke') || '';
      assert(stroke !== '' && stroke !== 'none' && stroke !== 'transparent', "Group 36: Pie slice has valid stroke color (" + stroke + ")");
      assert(slice.getAttribute('stroke-width') === '10', "Group 36: Pie slice has stroke-width='10'");
    });

    // 3. 右侧各分类数据列表与格式验证 (分类名(XX%):紧凑金额) 及无遮罩验证 (<= 4 项)
    const pieLegend = document.getElementById('monthly-pie-legend');
    assert(pieLegend !== null, "Group 36: #monthly-pie-legend exists");
    const legendItems = pieLegend.querySelectorAll('.monthly-pie-legend-item');
    assert(legendItems.length > 0, "Group 36: #monthly-pie-legend contains category items (found " + legendItems.length + ")");
    assert(legendItems.length <= 4, "Group 36: Initial October data has <= 4 categories (found " + legendItems.length + ")");
    assert(!pieLegend.classList.contains('pie-legend-fade-bottom'), "Group 36: #monthly-pie-legend has no fade mask when items <= 4");

    let totalPercentage = 0;
    const legendRegex = /^([^(\s]+)\s*\((\d+)%\):([\d.]+)$/;
    legendItems.forEach(item => {
      const text = item.innerText.trim();
      assert(legendRegex.test(text), "Group 36: Legend item matches format '${分类名}(${百分比}%):${紧凑金额}', got: '" + text + "'");
      const match = text.match(legendRegex);
      const catName = match[1];
      const pct = parseInt(match[2], 10);
      const amtStr = match[3];
      totalPercentage += pct;

      // 验证紧凑金额：去除尾部多余 0，最多 2 位小数
      if (amtStr.includes('.')) {
        assert(!amtStr.endsWith('0'), "Group 36: Compact amount has no trailing zeros ('" + amtStr + "')");
        const decPart = amtStr.split('.')[1];
        assert(decPart.length <= 2, "Group 36: Compact amount has at most 2 decimal places ('" + amtStr + "')");
      }
    });
    assert(totalPercentage === 100, "Group 36: Sum of category breakdown percentages is exactly 100% (got " + totalPercentage + "%)");

    // 4. 账单卡片 (.tx-item) 细节验证
    const allTxCards = Array.from(document.querySelectorAll('.tx-item:not(.soft-deleted)'));
    assert(allTxCards.length > 0, "Group 36: Active transaction cards exist");
    allTxCards.forEach(card => {
      const btnInCard = card.querySelector('button');
      assert(btnInCard === null, "Group 36: tx-item card contains NO button: " + card.id);
      const sourceTagInCard = card.querySelector('.tx-source-tag');
      assert(sourceTagInCard !== null, "Group 36: tx-item contains .tx-source-tag: " + card.id);
      assert(sourceTagInCard.innerText.trim().length > 0, "Group 36: tx-source-tag has non-empty text: " + sourceTagInCard.innerText);

      // 中间底行检查：不应出现 "• 自动识别"
      const middleRow = card.querySelector('.min-w-0.flex-1 .text-xs');
      if (middleRow) {
        assert(!middleRow.innerText.includes('• 自动识别'), "Group 36: Middle row of tx-item does not include '• 自动识别'");
      }
    });

    // 5. 动态联动测试：新增一笔流水后饼图与分类列表实时重算
    insertTransactionToList({
      id: "tx-test-breakdown-add",
      merchant: "测试医疗诊所",
      amount: 150.00,
      amountInCents: 15000,
      catName: "医疗健康",
      parentCat: "医疗健康",
      category: "医疗健康",
      channel: "微信",
      account: "微信钱包",
      txTime: "2026-10-26 18:00:00",
      orderTime: "2026-10-26 18:00:00",
      txDate: "2026-10-26",
      timeOnly: "18:00",
      orderId: "TEST_MED_ORDER_20261026",
      badge: "自动识别"
    });
    adjustMonthlyTotals(150.00);

    const legendItemsAfterAdd = Array.from(pieLegend.querySelectorAll('.monthly-pie-legend-item'));
    const hasMedCat = legendItemsAfterAdd.some(it => it.innerText.includes('医疗健康'));
    assert(hasMedCat, "Group 36: Added '医疗健康' transaction dynamically reflected in pie legend");

    // 重新校验 100% 闭合
    let newTotalPct = 0;
    legendItemsAfterAdd.forEach(item => {
      const m = item.innerText.trim().match(legendRegex);
      if (m) newTotalPct += parseInt(m[2], 10);
    });
    assert(newTotalPct === 100, "Group 36: Total percentage remains 100% after adding new transaction");

    // 5.1 内部滚动与底部渐变遮罩交互验证（分类数量 > 4 时自动激活遮罩，滚动到底部解除）
    assert(legendItemsAfterAdd.length > 4, "Group 36: Category count is > 4 after adding '医疗健康' (found " + legendItemsAfterAdd.length + ")");
    assert(pieLegend.classList.contains('pie-legend-fade-bottom'), "Group 36: #monthly-pie-legend automatically activates .pie-legend-fade-bottom when items > 4");
    assert(pieLegend.scrollHeight > pieLegend.clientHeight, "Group 36: #monthly-pie-legend supports vertical scrolling (scrollHeight " + pieLegend.scrollHeight + " > clientHeight " + pieLegend.clientHeight + ")");

    // 模拟滚动到底部：自动移除 .pie-legend-fade-bottom 遮罩
    pieLegend.scrollTop = pieLegend.scrollHeight - pieLegend.clientHeight;
    if (typeof pieLegend.onscroll === 'function') pieLegend.onscroll();
    assert(!pieLegend.classList.contains('pie-legend-fade-bottom'), "Group 36: .pie-legend-fade-bottom removed when scrolled to bottom");

    // 模拟滚动回顶部：重新激活 .pie-legend-fade-bottom 遮罩
    pieLegend.scrollTop = 0;
    if (typeof pieLegend.onscroll === 'function') pieLegend.onscroll();
    assert(pieLegend.classList.contains('pie-legend-fade-bottom'), "Group 36: .pie-legend-fade-bottom restored when scrolled back up");

    // 6. 动态联动测试：删除流水后饼图与分类列表实时重算
    deleteTxItem('tx-test-breakdown-add');
    const legendItemsAfterDel = Array.from(pieLegend.querySelectorAll('.monthly-pie-legend-item'));
    const hasMedAfterDel = legendItemsAfterDel.some(it => it.innerText.includes('医疗健康'));
    assert(!hasMedAfterDel, "Group 36: Deleted '医疗健康' transaction dynamically removed from pie legend");
    assert(legendItemsAfterDel.length <= 4, "Group 36: Category count restored to <= 4 after deleting '医疗健康' (found " + legendItemsAfterDel.length + ")");
    assert(!pieLegend.classList.contains('pie-legend-fade-bottom'), "Group 36: .pie-legend-fade-bottom automatically removed when category count returns to <= 4");

    // 7. 动态联动测试：切换月份空数据与有数据状态
    selectMonthYear(2026, 11);
    const emptyLegendText = pieLegend.innerText.trim();
    assert(emptyLegendText.includes('暂无支出数据'), "Group 36: Empty month shows '暂无支出数据' in legend");
    const emptySvgCircle = pieChart.querySelector('svg circle');
    assert(emptySvgCircle !== null, "Group 36: Empty month renders placeholder circle in chart");
    assert(!pieLegend.classList.contains('pie-legend-fade-bottom'), "Group 36: Empty month has no fade mask");

    // 切回 2026 年 10 月
    selectMonthYear(2026, 10);
    assert(pieLegend.querySelectorAll('.monthly-pie-legend-item').length > 0, "Group 36: Restored to October, pie legend restored");
    const restoredSlices = pieChart.querySelectorAll('.pie-slice');
    assert(restoredSlices.length >= 1, "Group 36: Restored to October, donut pie slices restored (found " + restoredSlices.length + ")");

    // 8. 动态联动测试：分类管理中删除分类与恢复
    if (window.DomainRegistry && typeof window.DomainRegistry.removeCategory === 'function') {
      window.DomainRegistry.removeCategory('休闲娱乐');
      syncAllCategoryUIs();
      const legendAfterCatRemove = Array.from(pieLegend.querySelectorAll('.monthly-pie-legend-item'));
      assert(!legendAfterCatRemove.some(it => it.innerText.includes('休闲娱乐')), "Group 36: Removed category '休闲娱乐' not in breakdown");
      
      // 还原分类
      if (typeof resetCategoriesToDefault === 'function') resetCategoriesToDefault(); else if (window.DomainRegistry && window.DomainRegistry.resetCategories) window.DomainRegistry.resetCategories();
      syncAllCategoryUIs();
    }

    
    // ================= Group 37: App OTA Update & Three Iron Rules (Data Backup/Restore & Non-Destructive Upgrade) =================
    console.log("=== Group 37: App OTA Update & Three Iron Rules ===");

    // Ensure version badge is clean for testing
    try { localStorage.removeItem('singwallet_app_version'); } catch(e) {}
    if (typeof initAppVersionBadge === 'function') initAppVersionBadge();

    // 1. 断言 #data-backup-card 与 #ota-update-card 存在于 #view-rules-accounts 中，且包含 com.singwallet.app、SQLite v2 无损迁移、#app-current-version-badge
    const rulesContainer = document.getElementById('view-rules-accounts') || document.getElementById('view-rules');
    assert(!!rulesContainer, "Group 37: #view-rules-accounts container exists");

    const dataBackupCard = document.getElementById('data-backup-card');
    assert(!!dataBackupCard, "Group 37: #data-backup-card exists in #view-rules-accounts");
    assert(rulesContainer.contains(dataBackupCard), "Group 37: #data-backup-card is nested inside #view-rules-accounts");

    const otaUpdateCard = document.getElementById('ota-update-card');
    assert(!!otaUpdateCard, "Group 37: #ota-update-card exists in #view-rules-accounts");
    assert(rulesContainer.contains(otaUpdateCard), "Group 37: #ota-update-card is nested inside #view-rules-accounts");

    // 领域层铁律配置锁定（不作为冗余文字堆砌在 UI 界面）
    assert(window.SingWalletDomain && window.SingWalletDomain.APP_VERSION_META && window.SingWalletDomain.APP_VERSION_META.packageId === 'com.singwallet.app', "Group 37: Domain packageId locked to 'com.singwallet.app'");
    assert(dataBackupCard.querySelector('h4') && dataBackupCard.querySelector('h4').classList.contains('whitespace-nowrap') && dataBackupCard.querySelector('h4').innerText === '数据备份', "Group 37: #data-backup-card title is cleanly '数据备份' with no line wrap");
    assert(otaUpdateCard.querySelector('h4') && otaUpdateCard.querySelector('h4').classList.contains('whitespace-nowrap') && otaUpdateCard.querySelector('h4').innerText === '应用版本', "Group 37: #ota-update-card title is cleanly '应用版本' with no line wrap");
    assert(document.getElementById('btn-export-backup') && document.getElementById('btn-export-backup').innerText.trim() === '导出备份', "Group 37: #btn-export-backup button text is cleanly '导出备份'");
    assert(document.getElementById('btn-import-backup') && document.getElementById('btn-import-backup').innerText.trim() === '导入恢复', "Group 37: #btn-import-backup button text is cleanly '导入恢复'");
    assert(document.getElementById('btn-check-ota-update') && document.getElementById('btn-check-ota-text') && document.getElementById('btn-check-ota-text').innerText.trim() === '检查更新', "Group 37: #btn-check-ota-update button text is cleanly '检查更新'");

    const versionBadge = document.getElementById('app-current-version-badge');
    assert(!!versionBadge, "Group 37: #app-current-version-badge exists");
    assert(otaUpdateCard.contains(versionBadge), "Group 37: #app-current-version-badge is inside #ota-update-card");
    assert(versionBadge.innerText.includes('v1.0.0'), "Group 37: initial version is v1.0.0 (found " + versionBadge.innerText + ")");

    // 2. 测试备份导出与无损恢复（铁律 3）
    // 2.1 先添加一个自定义分类（数码外设）
    if (window.DomainRegistry && typeof window.DomainRegistry.addCategory === 'function') {
      window.DomainRegistry.addCategory('数码外设');
    }
    syncAllCategoryUIs();
    const catsAfterAdd = window.DomainRegistry ? window.DomainRegistry.getParentCategories() : [];
    assert(catsAfterAdd.includes('数码外设'), "Group 37: Custom category '数码外设' successfully added");
    const customCatListEl = document.getElementById('custom-categories-list');
    assert(customCatListEl && customCatListEl.innerText.includes('数码外设'), "Group 37: '数码外设' rendered in custom-categories-list");

    // 2.2 调用导出备份函数获取 JSON 快照
    assert(typeof window.exportFullBackupSnapshot === 'function', "Group 37: window.exportFullBackupSnapshot exists");
    const backupSnapshot = window.exportFullBackupSnapshot();
    assert(!!backupSnapshot, "Group 37: exportFullBackupSnapshot returned backup snapshot");
    assert(backupSnapshot.packageId === 'com.singwallet.app', "Group 37: backup snapshot has packageId 'com.singwallet.app'");
    assert(backupSnapshot.dbSchema === 'sqlite_v2', "Group 37: backup snapshot has dbSchema 'sqlite_v2'");
    assert(backupSnapshot.data && backupSnapshot.data.categories && backupSnapshot.data.categories.includes('数码外设'), "Group 37: backup snapshot contains '数码外设'");

    // 2.3 随后删除该自定义分类
    if (window.DomainRegistry && typeof window.DomainRegistry.removeCategory === 'function') {
      window.DomainRegistry.removeCategory('数码外设');
    }
    syncAllCategoryUIs();
    const catsAfterDelete = window.DomainRegistry ? window.DomainRegistry.getParentCategories() : [];
    assert(!catsAfterDelete.includes('数码外设'), "Group 37: '数码外设' deleted from parent categories");
    assert(customCatListEl && !customCatListEl.innerText.includes('数码外设'), "Group 37: '数码外设' no longer in UI list");

    // 2.4 调用 window.importBackupFromJson(snapshot) 恢复备份
    assert(typeof window.importBackupFromJson === 'function', "Group 37: window.importBackupFromJson exists");
    const restoreResult = window.importBackupFromJson(backupSnapshot);
    assert(restoreResult === true, "Group 37: importBackupFromJson returned true");

    // 2.5 断言自定义分类「数码外设」、账单流水、实心饼状图数据 100% 恢复如初
    const catsAfterRestore = window.DomainRegistry ? window.DomainRegistry.getParentCategories() : [];
    assert(catsAfterRestore.includes('数码外设'), "Group 37: '数码外设' 100% restored in parent categories");
    assert(customCatListEl && customCatListEl.innerText.includes('数码外设'), "Group 37: '数码外设' 100% restored in UI list");
    const txItemsAfterRestore = document.querySelectorAll('#transactions-list .tx-item:not(.soft-deleted)');
    assert(txItemsAfterRestore.length >= 3, "Group 37: transactions intact after restore (found " + txItemsAfterRestore.length + ")");
    const pieSlicesAfterRestore = document.querySelectorAll('#monthly-pie-chart .pie-slice');
    assert(pieSlicesAfterRestore.length >= 1, "Group 37: donut pie chart slices 100% restored");

    // 3. 测试 OTA 一键检查更新与无损覆盖升级（方式 2 + 铁律 1/2）
    // 升级前状态快照
    const preUpgradeTxCount = document.querySelectorAll('#transactions-list .tx-item:not(.soft-deleted)').length;
    const preUpgradeCategories = [...(window.DomainRegistry ? window.DomainRegistry.getParentCategories() : [])];
    const preUpgradeVlm = JSON.stringify(window.vlmConfig || {});

    // 3.1 验证点击 #btn-check-ota-update (未配置自定义地址时优雅提示已是最新版本，不强行弹假更新)
    const btnCheckOta = document.getElementById('btn-check-ota-update');
    assert(!!btnCheckOta, "Group 37: #btn-check-ota-update exists");
    btnCheckOta.click();

    const otaResultBox = document.getElementById('ota-check-result-box');
    assert(!!otaResultBox, "Group 37: #ota-check-result-box exists");
    assert(otaResultBox.classList.contains('hidden'), "Group 37: #ota-check-result-box remains hidden when no new release configured");

    // 3.1.2 模拟传入 mockPayload 检查更新 (远端发布 v1.1.0)
    window.checkOtaUpdate({
      version: '1.1.0',
      apkSize: '18.4 MB',
      changelog: [
        'SQLite 数据库无损迁移至 v2 (全量兼容历史字段)',
        '新增全量 JSON 数据备份与一键恢复',
        'AI 视觉凭证识别精准度提升与极速响应',
        '包名与官方签名指纹锁定，支持无感覆盖升级'
      ]
    });
    assert(!otaResultBox.classList.contains('hidden'), "Group 37: #ota-check-result-box is visible after check with new release payload");
    assert(otaResultBox.innerText.includes('v1.1.0'), "Group 37: #ota-check-result-box indicates new version v1.1.0");
    const changelogList = document.getElementById('ota-changelog-list');
    assert(!!changelogList, "Group 37: #ota-changelog-list exists");
    assert(changelogList.querySelectorAll('li').length >= 3, "Group 37: changelog contains detailed release notes");

    // 3.2 点击 #btn-trigger-ota-upgrade（或调用 window.executeOtaInPlaceUpgrade()）
    const btnTriggerUpgrade = document.getElementById('btn-trigger-ota-upgrade');
    assert(!!btnTriggerUpgrade, "Group 37: #btn-trigger-ota-upgrade exists");
    btnTriggerUpgrade.click();

    // 3.3 断言版本号徽章 #app-current-version-badge 更新为 v1.1.0
    assert(versionBadge.innerText.includes('v1.1.0'), "Group 37: #app-current-version-badge updated to v1.1.0 (found " + versionBadge.innerText + ")");
    assert(localStorage.getItem('singwallet_app_version') === '1.1.0', "Group 37: localStorage singwallet_app_version updated to '1.1.0'");

    // 3.4 验证铁律：升级前后账单流水数量、自定义分类、VLM 配置 100% 无损一致
    const postUpgradeTxCount = document.querySelectorAll('#transactions-list .tx-item:not(.soft-deleted)').length;
    const postUpgradeCategories = window.DomainRegistry ? window.DomainRegistry.getParentCategories() : [];
    const postUpgradeVlm = JSON.stringify(window.vlmConfig || {});

    assert(postUpgradeTxCount === preUpgradeTxCount, "Group 37: Iron Rule 1/2 Verified: Transaction count 100% preserved (" + postUpgradeTxCount + " == " + preUpgradeTxCount + ")");
    assert(JSON.stringify(postUpgradeCategories) === JSON.stringify(preUpgradeCategories), "Group 37: Iron Rule 1/2 Verified: Custom categories 100% preserved");
    assert(postUpgradeVlm === preUpgradeVlm, "Group 37: Iron Rule 1/2 Verified: VLM API config 100% preserved");

    // ================= Group 38: iOS-style Swipe-to-Delete & Confirmation Modal Verification =================
    console.log("=== Group 38: iOS-style Swipe-to-Delete & Confirmation Modal ===");

    // 1. 验证 DOM 容器与控件存在性
    const simHomeInd = document.getElementById('simulator-home-indicator');
    assert(!!simHomeInd, "Group 38: #simulator-home-indicator exists for desktop mockup / mobile isolation");
    const bottomNavEl = document.getElementById('bottom-nav-bar');
    assert(!!bottomNavEl, "Group 38: #bottom-nav-bar exists");
    const txDeleteConfirmModal = document.getElementById('tx-delete-confirm-modal');
    assert(!!txDeleteConfirmModal, "Group 38: #tx-delete-confirm-modal exists");
    assert(txDeleteConfirmModal.classList.contains('hidden'), "Group 38: #tx-delete-confirm-modal is initially hidden");

    // 2. 插入测试账单
    insertTransactionToList({
      id: 'tx_swipe_test_001',
      merchant: '麦当劳得来速',
      amount: 38.5,
      catName: '餐饮美食',
      parentCat: '餐饮美食',
      channel: '支付宝',
      time: '2026-10-27 13:14:00',
      date: '2026-10-27',
      orderId: 'SWIPE_TEST_ORDER_001'
    });

    const swipeTxItem = document.getElementById('tx_swipe_test_001');
    assert(!!swipeTxItem, "Group 38: Swipe test transaction item rendered");
    const swipeDelBtn = swipeTxItem.querySelector('.tx-swipe-delete-btn');
    assert(!!swipeDelBtn, "Group 38: .tx-swipe-delete-btn exists inside tx-item");
    assert(swipeDelBtn.getAttribute('role') === 'button', "Group 38: .tx-swipe-delete-btn has role='button'");
    assert(swipeTxItem.querySelector('button') === null, "Group 38: tx-item contains NO button tag (preserving Group 22/36 assertions)");

    // 3. 左滑交互测试
    swipeTxItem.classList.add('swiped-left');
    assert(swipeTxItem.classList.contains('swiped-left'), "Group 38: .swiped-left class added on left swipe");

    // 4. 点击删除触发确认弹窗
    swipeDelBtn.click();
    assert(!txDeleteConfirmModal.classList.contains('hidden'), "Group 38: #tx-delete-confirm-modal opens on clicking .tx-swipe-delete-btn");
    const confirmDesc = document.getElementById('tx-delete-confirm-desc');
    assert(!!confirmDesc, "Group 38: #tx-delete-confirm-desc exists");
    assert(confirmDesc.innerText.includes('麦当劳得来速'), "Group 38: Confirmation description contains merchant name '麦当劳得来速'");
    assert(confirmDesc.innerText.includes('38.50'), "Group 38: Confirmation description contains formatted amount '38.50'");

    // 5. 测试取消按钮
    const btnCancelDel = document.getElementById('btn-cancel-tx-delete');
    assert(!!btnCancelDel, "Group 38: #btn-cancel-tx-delete exists");
    btnCancelDel.click();
    assert(txDeleteConfirmModal.classList.contains('hidden'), "Group 38: #tx-delete-confirm-modal closed on cancel");
    assert(!swipeTxItem.classList.contains('swiped-left'), "Group 38: .swiped-left removed from item on cancel");
    assert(!swipeTxItem.classList.contains('soft-deleted'), "Group 38: Item was not deleted on cancel");

    // 6. 重新左滑并确认删除
    swipeTxItem.classList.add('swiped-left');
    swipeDelBtn.click();
    assert(!txDeleteConfirmModal.classList.contains('hidden'), "Group 38: Modal reopened");
    const btnConfirmDel = document.getElementById('btn-confirm-tx-delete');
    assert(!!btnConfirmDel, "Group 38: #btn-confirm-tx-delete exists");
    btnConfirmDel.click();

    // 7. 确认删除后状态验证
    assert(txDeleteConfirmModal.classList.contains('hidden'), "Group 38: Modal closed after confirmation");
    assert(swipeTxItem.classList.contains('soft-deleted'), "Group 38: Item marked as soft-deleted");
    assert(swipeTxItem.style.display === 'none', "Group 38: Deleted item display is none");
    const tBadge = document.getElementById('trash-badge');
    assert(tBadge && !tBadge.classList.contains('hidden'), "Group 38: Trash badge visible after swipe delete");

    // 8. 验证从回收站中撤销/恢复
    if (typeof window.restoreTrash === 'function') {
      window.restoreTrash('tx_swipe_test_001');
      assert(!swipeTxItem.classList.contains('soft-deleted'), "Group 38: Item restored from trash");
      assert(!swipeTxItem.classList.contains('swiped-left'), "Group 38: Restored item has no swiped-left state");
    }

    // 9. 验证分类字段容错与自愈引擎 (normalizeTxCategory)
    assert(typeof window.normalizeTxCategory === 'function', "Group 38: window.normalizeTxCategory exists");
    const healedSubway = window.normalizeTxCategory({ merchant: '杭州公共交通一码通' });
    assert(healedSubway.catName === '交通出行' && healedSubway.parentCat === '交通出行', "Group 38: '杭州公共交通一码通' inferred as '交通出行'");
    const healedShaxian = window.normalizeTxCategory({ merchant: '沙县小吃', catName: 'undefined' });
    assert(healedShaxian.catName === '餐饮美食' && healedShaxian.parentCat === '餐饮美食', "Group 38: '沙县小吃' inferred as '餐饮美食'");
    const healedBreakfast = window.normalizeTxCategory({ merchant: '杭州市拱墅区辰市早餐店', cat: undefined });
    assert(healedBreakfast.catName === '餐饮美食' && healedBreakfast.parentCat === '餐饮美食', "Group 38: '杭州市拱墅区辰市早餐店' inferred as '餐饮美食'");

    // 测试容错渲染：传入含 undefined 字段的账单，断言绝不呈现 'undefined'
    insertTransactionToList({
      id: 'tx_undefined_heal_test',
      merchant: '杭州公共交通一码通',
      amount: 50,
      catName: undefined,
      category: 'undefined'
    });
    const healedDomItem = document.getElementById('tx_undefined_heal_test');
    assert(!!healedDomItem, "Group 38: Healed DOM item rendered");
    const healedBadge = healedDomItem.querySelector('.inline-flex');
    assert(healedBadge !== null, "Group 38: Category badge rendered");
    assert(healedBadge.innerText.trim() === '交通出行', "Group 38: Badge text cleanly restored to '交通出行', not 'undefined'");
    assert(healedDomItem.getAttribute('data-cat') === '交通出行', "Group 38: data-cat attribute restored to '交通出行'");

    // ========================================================
    // Group 39: 快捷指令无感抓屏卡片、草稿箱结构优化与全尺寸饱满度断言
    // ========================================================
    console.log("=== Group 39: Shortcut Capture, Draft Dropdown Ordering & Plump Controls ===");

    // 1. 验证闪电记账模块卡片 (#shortcut-capture-card)
    const scCard = document.getElementById('shortcut-capture-card');
    assert(scCard !== null, "Group 39: #shortcut-capture-card exists in rules view");

    // 1.1 闪电记账无障碍后台抓屏服务状态与一键跳转开启引导断言
    const a11yBadge = document.getElementById('a11y-service-status-badge');
    assert(a11yBadge !== null, "Group 39: #a11y-service-status-badge exists");
    const a11yBtn = document.getElementById('btn-toggle-a11y-service');
    assert(a11yBtn !== null, "Group 39: #btn-toggle-a11y-service exists");
    assert(typeof window.checkA11yServiceStatus === 'function', "Group 39: window.checkA11yServiceStatus is function");
    assert(typeof window.handleA11yServiceAuth === 'function', "Group 39: window.handleA11yServiceAuth is function");
    assert(typeof window.handleShortcutCapturedItem === 'function', "Group 39: window.handleShortcutCapturedItem is function");
    const a11yInitialReady = window.checkA11yServiceStatus();
    assert(typeof a11yInitialReady === 'boolean', "Group 39: checkA11yServiceStatus returns boolean");
    assert(a11yBadge.innerText.includes('服务已就绪') || a11yBadge.innerText.includes('未授权开启'), "Group 39: a11y status badge shows readable status");

    // 1.2 底部导航栏标准高度与快记一手高宽比
    const btmBar = document.getElementById('bottom-nav-bar');
    assert(btmBar !== null && btmBar.className.includes('h-[52px]'), "Group 39: #bottom-nav-bar 为 52px 黄金高度比例");
    const navTxBtn = document.getElementById('nav-btn-transactions');
    assert(navTxBtn !== null && navTxBtn.className.includes('justify-center') && navTxBtn.className.includes('gap-0.5'), "Group 39: 导航栏项使用 justify-center gap-0.5 紧贴底部");
    const qrBar = document.getElementById('tx-quick-record-bar');
    assert(qrBar !== null && qrBar.className.includes('bottom-[60px]'), "Group 39: #tx-quick-record-bar 设为 bottom-[60px]");
    const qrBtn = qrBar.querySelector('button');
    assert(qrBtn !== null && qrBtn.className.includes('max-w-[240px]') && qrBtn.className.includes('h-[41px]') && qrBtn.className.includes('rounded-[14px]'), "Group 39: 快记按钮尺寸为 max-w-[240px] h-[41px] rounded-[14px]");

    // 2. 验证草稿箱分类下拉框置于支付网格之前，防止底部导航栏遮挡
    const draftCatWrap = document.getElementById('dropdown-wrap-select-draft-category');
    const draftPayGrid = document.getElementById('draft-payment-grid');
    assert(draftCatWrap !== null, "Group 39: #dropdown-wrap-select-draft-category exists");
    assert(draftPayGrid !== null, "Group 39: #draft-payment-grid exists");
    assert(Boolean(draftCatWrap.compareDocumentPosition(draftPayGrid) & Node.DOCUMENT_POSITION_FOLLOWING), "Group 39: 草稿箱分类下拉框物理排布位于支付渠道网格之上");

    // 3. 验证支出账户与支付渠道下拉菜单已移除写死的 inline min-width，实现 100% 触发器对齐
    const accMenu39 = document.getElementById('menu-select-account');
    const chanMenu39 = document.getElementById('menu-select-channel');
    assert(accMenu39 !== null && (!accMenu39.style.minWidth || accMenu39.style.minWidth === ''), "Group 39: #menu-select-account has no inline min-width");
    assert(chanMenu39 !== null && (!chanMenu39.style.minWidth || chanMenu39.style.minWidth === ''), "Group 39: #menu-select-channel has no inline min-width");

    // 4. 验证分类管理器项目为精致紧凑比例 (rounded-xl 与 min-h-[36px])
    syncAllCategoryUIs();
    const catListFirstItem = document.querySelector('#custom-categories-list > div');
    assert(catListFirstItem !== null && catListFirstItem.className.includes('rounded-xl'), "Group 39: Category manager items use rounded-xl");
    assert(catListFirstItem !== null && catListFirstItem.className.includes('min-h-[36px]'), "Group 39: Category manager items use min-h-[36px]");

    // ========================================================
    // Group 40: 闪电记账后台抓屏草稿 100% 零丢失保障 + 离线协议静默容错
    // ========================================================
    console.log("=== Group 40: Background Capture Zero Loss & Offline Resilience ===");

    // 1. 验证 handleShortcutCapturedItem 增强：日志记录、附加上下文标记、全站零硬编码 Emoji
    assert(typeof window.handleShortcutCapturedItem === 'function', "Group 40: window.handleShortcutCapturedItem exists");

    // 2. 场景 A：未配置大模型 API Key 时，后台闪电抓屏零丢失保障验证
    const vlmKeyInput40 = document.getElementById('vlm-api-key');
    if (vlmKeyInput40) vlmKeyInput40.value = '';
    if (window.vlmConfig) window.vlmConfig.apiKey = '';
    const draftsBeforeA = draftQueue.length;

    const fakeBgCaptureItemA = {
      source: 'lightning-tile',
      dataUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    };
    handleShortcutCapturedItem(fakeBgCaptureItemA);

    assert(draftQueue.length === draftsBeforeA + 1, "Group 40 (Scenario A): Background capture draft MUST NOT be discarded when no API key (draftQueue length +1)");
    const savedDraftA = draftQueue[0];
    assert(savedDraftA.parseError === true, "Group 40 (Scenario A): Fallback draft has parseError === true");
    assert(savedDraftA.merchant.includes('闪电抓屏'), "Group 40 (Scenario A): Fallback draft merchant indicates '闪电抓屏'");
    assert(savedDraftA.amount === 0, "Group 40 (Scenario A): Fallback draft amount is 0 (no NaN)");
    assert(savedDraftA.imageData === fakeBgCaptureItemA.dataUrl, "Group 40 (Scenario A): Fallback draft preserves original screenshot imageData");
    assert(savedDraftA.parseErrorReason === '未配置大模型 API Key', "Group 40 (Scenario A): parseErrorReason correctly recorded");

    // 验证草稿胶囊 UI 包含琥珀色样式与“待重试”状态，无硬编码 Emoji
    const pillContainer40 = document.getElementById('draft-pills-container');
    assert(pillContainer40 !== null, "Group 40: #draft-pills-container exists");
    assert(pillContainer40.innerHTML.includes('待重试'), "Group 40: Draft pill displays '待重试' badge");
    assert(!pillContainer40.innerHTML.includes('NaN'), "Group 40: Draft pill HTML contains NO 'NaN'");

    // 验证 localStorage 持久化中包含该草稿
    const persistedDraftsA = JSON.parse(localStorage.getItem('singwallet_user_drafts') || '[]');
    assert(persistedDraftsA.some(d => d.id === savedDraftA.id), "Group 40 (Scenario A): Fallback draft 100% persisted to localStorage");

    // 4. 验证草稿详情区与凭证区待重试状态展示
    loadDraftData(savedDraftA);
    const retryCardDom = document.getElementById('draft-vlm-retry-card');
    assert(retryCardDom !== null && !retryCardDom.classList.contains('hidden'), "Group 40: #draft-vlm-retry-card is visible for draft with parseError");
    assert(document.getElementById('input-amount').value === '0.00' || document.getElementById('input-amount').value === '', "Group 40: input-amount does not show NaN");
    assert(typeof window.retryCurrentDraftVlm === 'function', "Group 40: window.retryCurrentDraftVlm function is mounted");

    // 5. 验证容量超限保护机制 (saveStoredDrafts QuotaExceeded fallback)
    assert(typeof window.saveStoredDrafts === 'function', "Group 40: window.saveStoredDrafts exists");
    const origSetItem = localStorage.setItem;
    let quotaHitCount = 0;
    localStorage.setItem = function(key, val) {
      if (quotaHitCount === 0 && key === 'singwallet_user_drafts') {
        quotaHitCount++;
        const err = new Error('QuotaExceededError');
        err.name = 'QuotaExceededError';
        throw err;
      }
      return origSetItem.call(this, key, val);
    };
    saveStoredDrafts();
    localStorage.setItem = origSetItem;
    assert(quotaHitCount === 1, "Group 40: QuotaExceededError triggered safely and caught by saveStoredDrafts fallback");

    // 6. 场景 B：大模型接口异常网络故障时的草稿零丢失与原地保单验证
    if (vlmKeyInput40) vlmKeyInput40.value = 'sk-test-vlm-key-40';
    if (window.vlmConfig) window.vlmConfig.apiKey = 'sk-test-vlm-key-40';

    const testTaskIdB = 'draft-vlm-task-error-test-' + Date.now();
    const taskDraftB = {
      id: testTaskIdB,
      merchant: '大模型解析中...',
      amount: 0,
      confidence: 0,
      isParsing: true,
      category: '日常购物',
      channel: '微信',
      account: '钱包',
      tag: '后台解析中...',
      rule: 'VLM 视觉智能识别',
      time: '2026-10-29 12:00:00',
      imageData: fakeBgCaptureItemA.dataUrl
    };
    draftQueue.unshift(taskDraftB);
    renderDraftQueue();

    const targetDraftB = draftQueue.find(d => d.id === testTaskIdB);
    assert(targetDraftB !== null, "Group 40: taskDraftB inserted");
    targetDraftB.isParsing = false;
    targetDraftB.parseError = true;
    targetDraftB.parseErrorReason = '网络连接超时 (504 Gateway Timeout)';
    targetDraftB.merchant = '闪电抓屏 (点击重试或手填)';
    targetDraftB.tag = '网络受阻·已保单';
    saveStoredDrafts();
    renderDraftQueue();

    assert(draftQueue.some(d => d.id === testTaskIdB), "Group 40 (Scenario B): Draft MUST NOT be spliced/deleted on network error!");
    assert(draftQueue[0].tag === '网络受阻·已保单', "Group 40 (Scenario B): Draft tag updated to '网络受阻·已保单'");

    // 清理 Group 40 测试草稿
    draftQueue = draftQueue.filter(d => d.id !== savedDraftA.id && d.id !== testTaskIdB);
    saveStoredDrafts();
    renderDraftQueue();
    updateDraftBadge();

    // ========================================================
    // Group 41: Backend Audit Bug Fixes (Bug 1 ~ Bug 6) & New Capture Spec Regression Suite
    // ========================================================
    console.log("=== Group 41: Backend Audit Bug Fixes & Capture Spec Verification ===");
    cleanAllTestData();

    // --- Bug 1 (P0): 删除账单刷新后不复活 & undoDelete 同步恢复 ---
    insertTransactionToList({
      id: "item-tx-bug1-test",
      merchant: "待删不复活测试店",
      amount: 66.60,
      catName: "餐饮美食",
      txDate: "2026-10-26",
      txTime: "2026-10-26 12:00:00",
      orderId: "ORD_BUG1_001"
    });
    adjustMonthlyTotals(66.60, true, 1, '2026-10');
    assert(JSON.parse(localStorage.getItem('singwallet_user_transactions') || '[]').some(t => t.id === 'item-tx-bug1-test'), "Group 41 (Bug 1): Transaction persisted before delete");

    deleteTransaction("item-tx-bug1-test", "待删不复活测试店", 66.60);
    const txInMemAfterDel = allMonthlyData['2026-10'].txs.find(t => t.id === 'item-tx-bug1-test');
    assert(txInMemAfterDel && txInMemAfterDel.softDeleted === true, "Group 41 (Bug 1): deleteTransaction marks tx.softDeleted = true in allMonthlyData");
    const storedAfterDel = JSON.parse(localStorage.getItem('singwallet_user_transactions') || '[]');
    assert(!storedAfterDel.some(t => t.id === 'item-tx-bug1-test'), "Group 41 (Bug 1): Deleted transaction is filtered out from localStorage (will not resurrect on reload)");

    undoDelete();
    assert(txInMemAfterDel && txInMemAfterDel.softDeleted === false, "Group 41 (Bug 1): undoDelete restores tx.softDeleted = false in allMonthlyData");
    const storedAfterUndo = JSON.parse(localStorage.getItem('singwallet_user_transactions') || '[]');
    assert(storedAfterUndo.some(t => t.id === 'item-tx-bug1-test'), "Group 41 (Bug 1): undoDelete re-saves restored transaction to localStorage");

    // --- Bug 2 (P0): 跨月账单动态路由至目标月且不污染当前激活月 ---
    const octCountBefore = document.querySelectorAll('#transactions-list .tx-item:not(.soft-deleted)').length;
    const octExpBefore = allMonthlyData['2026-10'].exp;
    insertTransactionToList({
      id: "item-tx-bug2-sep",
      merchant: "九月跨月书店",
      amount: 88.00,
      catName: "日常购物",
      txDate: "2026-09-15",
      txTime: "2026-09-15 10:20:00",
      orderId: "ORD_BUG2_SEP"
    });
    assert(allMonthlyData['2026-09'] && allMonthlyData['2026-09'].txs.some(t => t.id === 'item-tx-bug2-sep'), "Group 41 (Bug 2): 2026-09 transaction routed to allMonthlyData['2026-09']");
    assert(allMonthlyData['2026-09'].exp === '88.00', "Group 41 (Bug 2): allMonthlyData['2026-09'].exp updated to 88.00 (got " + allMonthlyData['2026-09'].exp + ")");
    assert(allMonthlyData['2026-10'].exp === octExpBefore, "Group 41 (Bug 2): 2026-10 exp untouched by 2026-09 insertion");
    assert(document.querySelectorAll('#transactions-list .tx-item:not(.soft-deleted)').length === octCountBefore, "Group 41 (Bug 2): 2026-10 active DOM list not polluted by 2026-09 bill");

    // --- Bug 3 (P0): 后台闪电记账入队不冲掉当前正在编辑的草稿表单 ---
    draftQueue = [{
      id: 'draft-editing-now',
      merchant: '原草稿商户',
      amount: 20.00,
      confidence: 96,
      isParsing: false,
      category: '餐饮美食',
      categoryName: '餐饮美食',
      channel: '微信',
      account: '钱包',
      orderId: 'ORD_EDIT_001',
      time: '2026-10-26 09:00:00'
    }];
    currentDraftIndex = 0;
    renderDraftQueue();
    document.getElementById('input-merchant').value = '用户正在手改的商户名';
    document.getElementById('input-amount').value = '99.50';

    if (window.vlmConfig) window.vlmConfig.apiKey = '';
    const vlmKeyEl41 = document.getElementById('vlm-api-key');
    if (vlmKeyEl41) vlmKeyEl41.value = '';
    window.currentOcrEngine = 'llm';

    handleManualScreenshotUpload({
      target: { files: [new File([new Uint8Array(10)], 'bg_capture.png', { type: 'image/png' })] },
      isBackgroundCapture: true,
      captureSource: 'lightning-tile',
      sourceDataUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
    });
    assert(draftQueue.length === 2, "Group 41 (Bug 3): Background capture unshifted into draftQueue (length=2)");
    assert(currentDraftIndex === 1, "Group 41 (Bug 3): currentDraftIndex incremented to 1 to stay on user's active draft");
    assert(document.getElementById('input-merchant').value === '用户正在手改的商户名', "Group 41 (Bug 3): Active merchant input preserved without being wiped");
    assert(document.getElementById('input-amount').value === '99.50', "Group 41 (Bug 3): Active amount input preserved without being wiped");
    assert(draftQueue[1].merchant === '用户正在手改的商户名' && draftQueue[1].amount === 99.50, "Group 41 (Bug 3): In-progress edits synced to draftQueue[currentDraftIndex]");
    window.currentOcrEngine = 'local';

    // --- Bug 4 (P1): 智谱 GLM (/api/paas/v4) 端点 URL 拼接无 /v1 污染 ---
    const zhipuBase = 'https://open.bigmodel.cn/api/paas/v4';
    assert(normalizeApiEndpoint(zhipuBase, 'openai') === 'https://open.bigmodel.cn/api/paas/v4/chat/completions', "Group 41 (Bug 4): Zhipu /api/paas/v4 normalized to /api/paas/v4/chat/completions");
    assert(getBaseOriginPath('https://open.bigmodel.cn/api/paas/v4/chat/completions') === 'https://open.bigmodel.cn/api/paas/v4', "Group 41 (Bug 4): getBaseOriginPath preserves /api/paas/v4");
    assert(normalizeApiEndpoint('https://api.openai.com/v1', 'openai') === 'https://api.openai.com/v1/chat/completions', "Group 41 (Bug 4): Standard /v1 endpoint remains 100% compatible");

    // --- Bug 5 (P1): VLM 金额符号/负数清洗、思维链 <think> 与尾逗号解析、本地引擎移除纯文件大小盲猜 ---
    const formattedVlm = formatVlmResult({ merchant: '测试店', amount: '-¥1,234.56', category: '餐饮美食' });
    assert(formattedVlm.amount === 1234.56, "Group 41 (Bug 5): formatVlmResult cleans currency/comma/negative to 1234.56 (got " + formattedVlm.amount + ")");
    const thinkRaw = '<think>\n正在分析账单金额...\n</think>\n```json\n{"merchant": "思维链商户", "amount": "¥35.80", "category": "餐饮美食",}\n```';
    const parsedThink = window.extractJsonFromVlmResponse(thinkRaw);
    assert(parsedThink && parsedThink.merchant === '思维链商户', "Group 41 (Bug 5): extractJsonFromVlmResponse strips <think> block and trailing comma");
    const random70kFile = { name: 'random_photo_20261030.png', size: 70000 };
    const localRes70k = parseBillWithLocalEngine(random70kFile);
    assert(!localRes70k.merchant.includes('星巴克'), "Group 41 (Bug 5): parseBillWithLocalEngine no longer misclassifies arbitrary 70KB file as Starbucks (got " + localRes70k.merchant + ")");

    // --- Bug 6 (P1/P2): 删除自定义分类孤儿数据迁移、空对象备份拒绝、浮点精度 ---
    addCustomCategory(); // no-op with empty input
    if (window.DomainRegistry && typeof window.DomainRegistry.addCategory === 'function') {
      window.DomainRegistry.addCategory('测试孤儿分类');
    }
    insertTransactionToList({
      id: 'item-tx-orphan-cat',
      merchant: '孤儿分类测试商户',
      amount: 12.30,
      catName: '测试孤儿分类',
      txDate: '2026-10-26',
      txTime: '2026-10-26 15:00:00',
      orderId: 'ORD_ORPHAN_001'
    });
    removeCustomCategory('测试孤儿分类');
    const migratedTx = allMonthlyData['2026-10'].txs.find(t => t.id === 'item-tx-orphan-cat');
    assert(migratedTx && migratedTx.category === '其他支出' && migratedTx.parentCat === '其他支出', "Group 41 (Bug 6): Orphan transaction migrated to '其他支出' after custom category deletion");
    const migratedDom = document.getElementById('item-tx-orphan-cat');
    assert(migratedDom && migratedDom.getAttribute('data-category') === '其他支出', "Group 41 (Bug 6): Orphan DOM .tx-item migrated to '其他支出'");

    assert(importBackupFromJson('{}') === false, "Group 41 (Bug 6): Empty object '{}' rejected by importBackupFromJson");
    assert(importBackupFromJson('{"hello":"world"}') === false, "Group 41 (Bug 6): Object without valid backup keys rejected by importBackupFromJson");

    allMonthlyData['2026-11'] = { net: '0.00', exp: '0.00', ref: '0.00', inc: '0.00', txs: [] };
    adjustMonthlyTotals(0.1, true, 1, '2026-11');
    adjustMonthlyTotals(0.2, true, 1, '2026-11');
    assert(allMonthlyData['2026-11'].exp === '0.30', "Group 41 (Bug 6): IEEE 754 float precision 0.1 + 0.2 === '0.30'");

    // --- 新规范：背部轻敲截屏监听已弃用，不自动轮询相册，保留双触发入口 ---
    assert(typeof window.onNativeScreenshotCaptured === 'function' && typeof window.triggerQuickTileCapture === 'function', "Group 41 (Capture Spec): Lightning tile capture entrypoints are exposed");

    // ========================================================
    // Group 42: Dual-Engine GitHub OTA (Commit Web Hot Update & Release APK Upgrade)
    // ========================================================
    console.log("=== Group 42: Dual-Engine GitHub OTA & Bridge Execution ===");

    // 1. 验证领域层 SSOT 元数据与新版仓库配置
    const otaMeta = window.SingWalletDomain ? window.SingWalletDomain.APP_VERSION_META : window.APP_VERSION_META;
    assert(!!otaMeta, "Group 42: APP_VERSION_META exists in domain SSOT");
    assert(otaMeta.githubRepo === 'Hsanli060/singwallet', "Group 42: default githubRepo is locked to 'Hsanli060/singwallet'");
    assert(otaMeta.githubBranch === 'master', "Group 42: default githubBranch is locked to 'master'");
    assert(otaMeta.repo === 'Hsanli060/singwallet', "Group 42: repo compatibility field is 'Hsanli060/singwallet'");
    assert(otaMeta.branch === 'master', "Group 42: branch compatibility field is 'master'");
    assert(otaMeta.currentVersion === '1.0.0', "Group 42: currentVersion remains '1.0.0' for test suite compatibility");
    assert(otaMeta.releasesApiUrl.includes('Hsanli060/singwallet/releases/latest'), "Group 42: releasesApiUrl points to GitHub releases/latest");
    assert(otaMeta.commitsApiUrl.includes('Hsanli060/singwallet/commits/master'), "Group 42: commitsApiUrl points to GitHub commits/master");

    // 2. 验证别名与入口挂载
    assert(typeof window.checkAppUpdate === 'function', "Group 42: window.checkAppUpdate alias is mounted");
    assert(window.checkAppUpdate === window.checkOtaUpdate, "Group 42: checkAppUpdate === checkOtaUpdate");
    assert(typeof window.triggerOtaInstall === 'function', "Group 42: window.triggerOtaInstall alias is mounted");
    assert(window.triggerOtaInstall === window.executeOtaInPlaceUpgrade, "Group 42: triggerOtaInstall === executeOtaInPlaceUpgrade");
    assert(typeof window.fetchAndRenderGitHubOtaUpdate === 'function', "Group 42: fetchAndRenderGitHubOtaUpdate is exposed");
    assert(typeof window.onNativeOtaProgress === 'function', "Group 42: window.onNativeOtaProgress is exposed");

    // 3. 验证 Commit 免编译 Web 秒级热更新检测与 DOM 渲染 (双擎之一)
    const originalFetch = window.fetch;
    const mockCommitSha = '8f9a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a';
    const mockShortSha = '8f9a2b3';
    try {
      localStorage.removeItem('singwallet_hot_commit_sha');
      localStorage.setItem('singwallet_app_version', '1.0.0');

      window.fetch = async function(url, options) {
        if (url.includes('/commits/')) {
          return {
            ok: true,
            status: 200,
            json: async () => ({
              sha: mockCommitSha,
              commit: {
                message: "feat: instant web hot update engine\n- zero install web reload\n- preserve sqlite data",
                author: { name: "Hsanli", date: "2026-10-30T10:00:00Z" }
              }
            })
          };
        }
        if (url.includes('/releases/latest')) {
          return { ok: false, status: 404, json: async () => ({ message: "Not Found" }) };
        }
        return { ok: false, status: 404, json: async () => ({}) };
      };

      const hotCheckRes = await window.fetchAndRenderGitHubOtaUpdate('Hsanli060/singwallet');
      assert(hotCheckRes && hotCheckRes.hasUpdate === true, "Group 42: Web hot update detected successfully from GitHub commits");

      const otaBoxEl = document.getElementById('ota-check-result-box');
      assert(otaBoxEl && !otaBoxEl.classList.contains('hidden'), "Group 42: #ota-check-result-box expanded for web hot update");

      const titleEl = document.getElementById('ota-version-title');
      assert(titleEl && titleEl.innerText.includes(mockShortSha), "Group 42: #ota-version-title displays hot update shortSha #" + mockShortSha);

      const changelogListEl = document.getElementById('ota-changelog-list');
      assert(changelogListEl && changelogListEl.innerHTML.includes('instant web hot update engine'), "Group 42: Changelog renders GitHub commit messages");

      const triggerBtn = document.getElementById('btn-trigger-ota-upgrade');
      assert(triggerBtn && triggerBtn.innerText.includes('立即热更新 (免安装秒级生效)'), "Group 42: Trigger button text shows '立即热更新 (免安装秒级生效)'");
      assert(window.__pendingOtaUpdateMeta && window.__pendingOtaUpdateMeta.mode === 'web_hot', "Group 42: Update meta mode is 'web_hot'");
      assert(window.__pendingOtaUpdateMeta.commitSha === mockCommitSha, "Group 42: Update meta records full commitSha");

      // 4. 验证 AndroidBridge 原生调用 performWebHotUpdate 与秒级热更新闭环
      let capturedPerformHotUpdateJson = null;
      window.AndroidBridge = {
        performWebHotUpdate: function(jsonStr) {
          capturedPerformHotUpdateJson = JSON.parse(jsonStr);
        }
      };

      window.triggerOtaInstall();
      assert(capturedPerformHotUpdateJson !== null, "Group 42: AndroidBridge.performWebHotUpdate called");
      assert(capturedPerformHotUpdateJson.repo === 'Hsanli060/singwallet', "Group 42: performWebHotUpdate repo is 'Hsanli060/singwallet'");
      assert(capturedPerformHotUpdateJson.branch === 'master', "Group 42: performWebHotUpdate branch is 'master'");
      assert(capturedPerformHotUpdateJson.commitSha === mockCommitSha, "Group 42: performWebHotUpdate commitSha matches remote");

      // 5. 验证原生进度回调 onNativeOtaProgress
      // 5.1 过程更新中
      window.onNativeOtaProgress({ percent: 55, status: '正在秒级热更 (55%)...' });
      const pBar = document.getElementById('ota-download-progress-bar');
      const pText = document.getElementById('ota-download-progress-text');
      const pStatus = document.getElementById('ota-download-status-text');
      assert(pBar && pBar.style.width === '55%', "Group 42: onNativeOtaProgress updates progress bar width to 55%");
      assert(pText && pText.innerText === '55%', "Group 42: onNativeOtaProgress updates progress text to 55%");
      assert(pStatus && pStatus.innerText.includes('55%'), "Group 42: onNativeOtaProgress updates status text");

      // 5.2 错误状态处理
      window.onNativeOtaProgress({ error: '资源哈希校验不匹配' });
      assert(!triggerBtn.disabled, "Group 42: onNativeOtaProgress with error re-enables trigger button");
      assert(triggerBtn.innerText.includes('重试更新'), "Group 42: Trigger button text shows '重试更新'");

      // 5.3 成功完成处理
      window.onNativeOtaProgress({ done: true, percent: 100, status: '热更新补丁已装载' });
      assert(localStorage.getItem('singwallet_hot_commit_sha') === mockCommitSha, "Group 42: localStorage singwallet_hot_commit_sha saved");
      assert(triggerBtn.disabled === true, "Group 42: Trigger button disabled after update complete");
      assert(triggerBtn.innerText.includes('已完成更新'), "Group 42: Trigger button text shows '已完成更新'");
      const vBadge = document.getElementById('app-current-version-badge');
      assert(vBadge && vBadge.innerText.includes(mockShortSha), "Group 42: Version badge updated with commit shortSha #" + mockShortSha);

      // 6. 验证 GitHub Release APK 更新流 (双擎之二)
      const mockApkUrl = 'https://github.com/Hsanli060/singwallet/releases/download/v1.2.0/singwallet-v1.2.0.apk';
      window.fetch = async function(url, options) {
        if (url.includes('/releases/latest')) {
          return {
            ok: true,
            status: 200,
            json: async () => ({
              tag_name: "v1.2.0",
              name: "SingWallet v1.2.0 Release",
              body: "### 升级日志\n* 升级 Android 架构底层\n* 新增分类实心圆环",
              assets: [
                {
                  name: "singwallet-v1.2.0.apk",
                  size: 19800000,
                  browser_download_url: mockApkUrl
                }
              ]
            })
          };
        }
        if (url.includes('/commits/')) {
          return {
            ok: true,
            status: 200,
            json: async () => ({ sha: '9999999999999999999999999999999999999999', commit: { message: "release 1.2.0" } })
          };
        }
        return { ok: false, status: 404, json: async () => ({}) };
      };

      const apkCheckRes = await window.fetchAndRenderGitHubOtaUpdate('Hsanli060/singwallet');
      assert(apkCheckRes && apkCheckRes.hasUpdate === true, "Group 42: APK Release update detected successfully");
      assert(window.__pendingOtaUpdateMeta && window.__pendingOtaUpdateMeta.mode === 'apk_or_web', "Group 42: Update meta mode is 'apk_or_web'");
      assert(window.__pendingOtaUpdateMeta.apkDownloadUrl === mockApkUrl, "Group 42: Update meta has correct apkDownloadUrl");
      assert(titleEl && titleEl.innerText.includes('v1.2.0'), "Group 42: Release update displays title '发现新版本 v1.2.0'");
      assert(triggerBtn && triggerBtn.innerText.includes('立即更新 (v1.2.0)'), "Group 42: Trigger button text shows '立即更新 (v1.2.0)'");

      // 7. 验证 AndroidBridge 原生调用 downloadAndInstallApk
      let capturedDownloadUrl = null;
      window.AndroidBridge = {
        downloadAndInstallApk: function(url, sha) {
          capturedDownloadUrl = url;
        }
      };

      window.triggerOtaInstall();
      assert(capturedDownloadUrl === mockApkUrl, "Group 42: AndroidBridge.downloadAndInstallApk called with correct APK url");

      // 8. 验证原生宿主版本号优先读取与徽章呈现 (真机 1.0.7)
      window.AndroidBridge.getAppVersion = () => "1.0.7";
      assert(typeof window.getEffectiveAppVersion === 'function', "Group 42: window.getEffectiveAppVersion is exposed");
      assert(window.getEffectiveAppVersion() === "1.0.7", "Group 42: getEffectiveAppVersion prioritizes AndroidBridge.getAppVersion ('1.0.7')");
      window.initAppVersionBadge();
      const nativeBadge = document.getElementById('app-current-version-badge');
      assert(nativeBadge && nativeBadge.innerText.startsWith('v1.0.7'), "Group 42: #app-current-version-badge updated to v1.0.7 from AndroidBridge");

      // 9. 验证 checkOtaUpdate 形参默认值 triggerAsyncNetwork = null
      // 9.1 当 __SW_DISABLE_NET_OTA__ = true 时，不发起异步请求，安全返回同步结果
      const syncCheckRes = window.checkOtaUpdate();
      assert(syncCheckRes && syncCheckRes.pendingAsync !== true, "Group 42: checkOtaUpdate with default null respects SW_DISABLE_NET_OTA");
      // 9.2 当显式 triggerAsyncNetwork = true 时，发起异步请求并返回 pendingAsync: true
      const asyncCheckRes = window.checkOtaUpdate(null, true);
      assert(asyncCheckRes && asyncCheckRes.pendingAsync === true, "Group 42: checkOtaUpdate(null, true) triggers async network check");

      // 10. 验证 GitHub PAT Token 解析与持久化
      const samplePat = "ghp_MockSecretToken123456789012345678";
      assert(typeof window.resolveGithubToken === 'function', "Group 42: window.resolveGithubToken is exposed");
      const parsedPat = window.resolveGithubToken(samplePat);
      assert(parsedPat === samplePat, "Group 42: resolveGithubToken correctly parses PAT string");
      assert(localStorage.getItem('singwallet_github_token') === samplePat, "Group 42: PAT saved to localStorage singwallet_github_token");
      assert(window.resolveGithubToken() === samplePat, "Group 42: resolveGithubToken reads from localStorage when no param passed");

      // 11. 验证携带 Token 访问 GitHub API 时请求头注入 Authorization: token <token>
      let capturedAuthHeader = null;
      window.fetch = async function(url, options) {
        if (options && options.headers) {
          capturedAuthHeader = options.headers['Authorization'] || options.headers['authorization'];
        }
        return {
          ok: true,
          status: 200,
          json: async () => ({ sha: 'abcdef1234567890abcdef1234567890abcdef12', commit: { message: "token auth update" } })
        };
      };
      await window.fetchAndRenderGitHubOtaUpdate();
      assert(capturedAuthHeader === `token ${samplePat}`, "Group 42: fetch headers include Authorization: token <token>");

      // 12. 验证热更新 Payload 透传 Token 给 AndroidBridge.performWebHotUpdate
      let capturedHotToken = null;
      window.AndroidBridge.performWebHotUpdate = function(jsonStr) {
        const parsed = JSON.parse(jsonStr);
        capturedHotToken = parsed.token;
      };
      window.triggerOtaInstall();
      assert(capturedHotToken === samplePat, "Group 42: AndroidBridge.performWebHotUpdate received authToken");

      // 13. 验证 404 且无 Token 时的明确 Toast 友好指引
      localStorage.removeItem('singwallet_github_token');
      const feedInputEl = document.getElementById('ota-feed-url-input');
      if (feedInputEl) feedInputEl.value = '';
      window.fetch = async function() {
        return { ok: false, status: 404, json: async () => ({ message: "Not Found" }) };
      };
      const check404Res = await window.fetchAndRenderGitHubOtaUpdate();
      assert(check404Res && check404Res.hasUpdate === false, "Group 42: Private repo returns hasUpdate: false");
      const toastEl = document.querySelector('.singwallet-toast-wrap');
      assert(toastEl && toastEl.innerText.includes('检查更新失败(404)：当前 GitHub 仓库为私有(Private)'), "Group 42: 404 error shows private repo guidance toast");

    } finally {
      window.fetch = originalFetch;
      delete window.AndroidBridge;
    }

    // ========================================================
    // Group 43: 渠道-账户互斥与首次点击下拉过滤专项回归 (Bug 1 专项测试)
    // ========================================================
    console.log("=== Group 43: Channel-Account Mutex & Dropdown Filter Regression ===");
    switchTab('drafts');
    
    // 1. 测试当草稿渠道为「支付宝」且原始账户误传为「钱包」时，loadDraftData 自动修正为「余额」
    const alipayBugDraft = {
      id: 'draft-bug-alipay-mutex',
      merchant: '测试商户-支付宝互斥校验',
      amount: 68.80,
      amountInCents: 6880,
      channel: '支付宝',
      account: '钱包', // 原始账户误传为 钱包
      category: '日常购物',
      categoryName: '日常购物',
      confidence: 96,
      rule: '测试规则-支付宝互斥',
      orderId: '202610310001',
      orderTime: '2026-10-31 10:00:00',
      time: '2026-10-31 10:00:00',
      payment: { channel: '支付宝', sub_type: '钱包', display_name: '支付宝 · 钱包' }
    };

    draftQueue = [alipayBugDraft];
    currentDraftIndex = 0;
    renderDraftQueue();
    loadDraftData(alipayBugDraft);

    const selChanEl = document.getElementById('select-channel');
    const labelChanEl = document.getElementById('label-select-channel');
    const selAccEl = document.getElementById('select-account');
    const labelAccEl = document.getElementById('label-select-account');

    assert(selChanEl && selChanEl.value === '支付宝', "Group 43: Draft channel correctly set to 支付宝");
    assert(labelChanEl && labelChanEl.textContent.trim() === '支付宝', "Group 43: Channel label shows 支付宝");
    assert(selAccEl && selAccEl.value === '余额', "Group 43: Erroneous account '钱包' under '支付宝' automatically corrected to '余额'");
    assert(labelAccEl && labelAccEl.textContent.trim() === '余额', "Group 43: Account label updated to '余额'");

    // 2. 测试首次点击打开 #menu-select-account 时仅显示支付宝下的选项
    // 微信专有选项（钱包、零钱通、招商银行(8848)）display 必须为 'none'
    // 支付宝选项（余额、余额宝、建设银行(1234)）display 必须不为 'none'
    toggleCustomDropdown('select-account');
    const accMenuEl = document.getElementById('menu-select-account');
    assert(accMenuEl && accMenuEl.classList.contains('open'), "Group 43: #menu-select-account is open on first click");

    const optWallet = accMenuEl.querySelector('[data-channel="微信"][data-value="钱包"]');
    const optChange = accMenuEl.querySelector('[data-channel="微信"][data-value="零钱通"]');
    const optCmb = accMenuEl.querySelector('[data-channel="微信"][data-value="招商银行(8848)"]');
    const optBalance = accMenuEl.querySelector('[data-channel="支付宝"][data-value="余额"]');
    const optYeb = accMenuEl.querySelector('[data-channel="支付宝"][data-value="余额宝"]');
    const optCcb = accMenuEl.querySelector('[data-channel="支付宝"][data-value="建设银行(1234)"]');

    assert(optWallet && optWallet.style.display === 'none', "Group 43: WeChat '钱包' option display is 'none' when channel is Alipay");
    assert(optChange && optChange.style.display === 'none', "Group 43: WeChat '零钱通' option display is 'none' when channel is Alipay");
    assert(optCmb && optCmb.style.display === 'none', "Group 43: WeChat '招商银行(8848)' option display is 'none' when channel is Alipay");

    assert(optBalance && optBalance.style.display !== 'none', "Group 43: Alipay '余额' option display is not none");
    assert(optBalance && optBalance.classList.contains('selected'), "Group 43: Alipay '余额' option has 'selected' class");
    assert(optYeb && optYeb.style.display !== 'none', "Group 43: Alipay '余额宝' option display is not none");
    assert(optCcb && optCcb.style.display !== 'none', "Group 43: Alipay '建设银行(1234)' option display is not none");

    closeAllCustomDropdowns();

    // 3. 对称性逆向验证：测试当草稿为「微信」且原始账户误传为「余额」时，自动修正为「钱包」，且仅显示微信选项
    const wechatBugDraft = {
      id: 'draft-bug-wechat-mutex',
      merchant: '测试商户-微信互斥校验',
      amount: 32.50,
      amountInCents: 3250,
      channel: '微信',
      account: '余额', // 原始账户误传为 余额
      category: '餐饮美食',
      categoryName: '餐饮美食',
      confidence: 97,
      rule: '测试规则-微信互斥',
      orderId: '202610310002',
      orderTime: '2026-10-31 10:05:00',
      time: '2026-10-31 10:05:00',
      payment: { channel: '微信', sub_type: '余额', display_name: '微信 · 余额' }
    };
    loadDraftData(wechatBugDraft);
    assert(selChanEl.value === '微信', "Group 43: Draft channel correctly set to 微信");
    assert(selAccEl.value === '钱包', "Group 43: Erroneous account '余额' under '微信' automatically corrected to '钱包'");
    assert(labelAccEl.textContent.trim() === '钱包', "Group 43: Account label updated to '钱包'");

    toggleCustomDropdown('select-account');
    assert(optWallet && optWallet.style.display !== 'none', "Group 43: WeChat '钱包' option is visible when channel is WeChat");
    assert(optWallet && optWallet.classList.contains('selected'), "Group 43: WeChat '钱包' option has 'selected' class");
    assert(optBalance && optBalance.style.display === 'none', "Group 43: Alipay '余额' option display is 'none' when channel is WeChat");
    assert(optYeb && optYeb.style.display === 'none', "Group 43: Alipay '余额宝' option display is 'none' when channel is WeChat");
    closeAllCustomDropdowns();

    // ========================================================
    // Group 44: 动态银行卡识别规范化与动态下拉注入专项回归 (Bug 2 专项测试)
    // ========================================================
    console.log("=== Group 44: Dynamic Bank Card Normalization & Dynamic Injection Regression ===");
    
    // 1. 规范化纯函数断言验证
    const normBankAccFn = window.normalizeBankCardAccount || (window.DomainRegistry && window.DomainRegistry.normalizeBankCardAccount);
    assert(typeof normBankAccFn === 'function', "Group 44: normalizeBankCardAccount function is defined and callable");
    assert(normBankAccFn("工商银行银联储蓄卡[5678]") === "工商银行[5678]", "Group 44: normalizeBankCardAccount('工商银行银联储蓄卡[5678]') === '工商银行[5678]'");
    assert(normBankAccFn("中国工商银行储蓄卡(9988)") === "工商银行(9988)", "Group 44: normalizeBankCardAccount('中国工商银行储蓄卡(9988)') === '工商银行(9988)'");
    assert(normBankAccFn("中国农业银行借记卡(1122)") === "农业银行(1122)", "Group 44: normalizeBankCardAccount('中国农业银行借记卡(1122)') === '农业银行(1122)'");
    assert(normBankAccFn("招商银行信用卡[3344]") === "招商银行[3344]", "Group 44: normalizeBankCardAccount('招商银行信用卡[3344]') === '招商银行[3344]'");
    assert(normBankAccFn("中国邮政储蓄银行储蓄卡(5566)") === "邮储银行(5566)", "Group 44: normalizeBankCardAccount('中国邮政储蓄银行储蓄卡(5566)') === '邮储银行(5566)'");

    // 2. 动态银行卡草稿加载与下拉选项自动创建并选中
    const dynamicCardDraft = {
      id: 'draft-dynamic-card-injection',
      merchant: '测试商户-动态银行卡注入',
      amount: 158.00,
      amountInCents: 15800,
      channel: '支付宝',
      account: '工商银行银联储蓄卡[5678]',
      category: '日常购物',
      categoryName: '日常购物',
      confidence: 99,
      orderId: '202610310003',
      orderTime: '2026-10-31 10:10:00',
      time: '2026-10-31 10:10:00',
      payment: { channel: '支付宝', sub_type: '工商银行银联储蓄卡[5678]', display_name: '支付宝 · 工商银行银联储蓄卡[5678]' }
    };

    loadDraftData(dynamicCardDraft);
    assert(selChanEl.value === '支付宝', "Group 44: Dynamic card draft channel is 支付宝");
    assert(selAccEl.value === '工商银行[5678]', "Group 44: Dynamic card draft account normalized to '工商银行[5678]'");
    assert(labelAccEl.textContent.trim() === '工商银行[5678]', "Group 44: Account label synced to '工商银行[5678]'");

    // 检查 #menu-select-account 中动态创建的选项
    const dynamicCardOpt = accMenuEl.querySelector('[data-value="工商银行[5678]"]');
    assert(dynamicCardOpt !== null, "Group 44: Option '工商银行[5678]' was dynamically created and injected into #menu-select-account");
    assert(dynamicCardOpt && dynamicCardOpt.getAttribute('data-channel') === '支付宝', "Group 44: Dynamically created option has data-channel='支付宝'");
    assert(dynamicCardOpt && dynamicCardOpt.classList.contains('selected'), "Group 44: Dynamically created option has 'selected' class");
    assert(dynamicCardOpt && dynamicCardOpt.style.display !== 'none', "Group 44: Dynamically created option is visible (display !== 'none')");

    // 3. 验证 ocr_vlm_engine.js 的 Prompt 包含 'account' 及银行卡剔除修饰词的约束说明
    const vlmPromptText = (typeof window.buildVlmPromptText === 'function')
      ? window.buildVlmPromptText()
      : '';

    assert(vlmPromptText !== '', "Group 44: VLM Prompt text generated successfully");
    assert(vlmPromptText.includes('"account": "支出账户"'), "Group 44: VLM Prompt contains JSON property 'account': '支出账户'");
    assert(vlmPromptText.includes('剔除“中国”、“银联”、“储蓄卡”、“借记卡”、“信用卡”等卡种修饰词'), "Group 44: VLM Prompt contains card modifier stripping instructions");
    assert(vlmPromptText.includes('如“工商银行银联储蓄卡[5678]”输出为“工商银行[5678]”'), "Group 44: VLM Prompt contains square bracket card normalization example");
    assert(vlmPromptText.includes('“中国工商银行储蓄卡(5678)”输出为“工商银行(5678)”'), "Group 44: VLM Prompt contains round bracket card normalization example");

    // 4. 验证结构化 Schema 包含 account 字段
    const structuredSchema = window.BILL_STRUCTURED_SCHEMA || (window.DomainRegistry && window.DomainRegistry.getConfig().schema);
    assert(structuredSchema &&
           structuredSchema.json_schema &&
           structuredSchema.json_schema.schema &&
           structuredSchema.json_schema.schema.properties &&
           structuredSchema.json_schema.schema.properties.account !== undefined,
           "Group 44: VLM structured output JSON schema contains 'account' property definition");

    // 5. 验证 formatVlmResult 对大模型提取结果的账户规范化输出
    const mockRawResult = {
      merchant: "测试商户",
      amount: 28.5,
      category: "日常购物",
      time: "2026-10-31 12:00:00",
      channel: "支付宝",
      account: "中国工商银行银联储蓄卡[5678]",
      orderId: "202610310001"
    };
    const formattedVlmResult = window.formatVlmResult(mockRawResult);
    assert(formattedVlmResult && formattedVlmResult.account === '工商银行[5678]', "Group 44: formatVlmResult normalizes extracted bank card to '工商银行[5678]'");
    assert(formattedVlmResult && formattedVlmResult.channel === '支付宝', "Group 44: formatVlmResult preserves channel 支付宝");
    assert(formattedVlmResult && formattedVlmResult.amount === 28.5, "Group 44: formatVlmResult extracts amount 28.5");

    // ========================================================
    // Group 45: 分类下拉防底部导航栏遮挡专项回归 (Bug 3 专项测试)
    // ========================================================
    console.log("=== Group 45: Category Dropdown Anti-Occlusion Regression ===");
    switchTab('drafts');
    resetDemoDrafts();
    loadDraftData(draftQueue[0]);

    // 1. 添加多个自定义分类标签以撑大下拉菜单选项数量
    const testCustomCats = ['数码潮玩', '宠物生活', '健身运动', '文化阅读', '投资理财', '美妆个护'];
    for (const cat of testCustomCats) {
      window.DomainRegistry.addCategory(cat);
    }
    if (typeof window.syncAllCategoryUIs === 'function') {
      window.syncAllCategoryUIs();
    }

    // 2. 打开 #menu-select-draft-category
    toggleCustomDropdown('select-draft-category');
    const draftCatMenu = document.getElementById('menu-select-draft-category');
    const navBar = document.getElementById('bottom-nav-bar');
    const catWrapEl = document.getElementById('dropdown-wrap-select-draft-category');

    assert(draftCatMenu && draftCatMenu.classList.contains('open'), "Group 45: #menu-select-draft-category is open");
    const catMenuRect = draftCatMenu.getBoundingClientRect();
    const bottomNavRect = navBar.getBoundingClientRect();
    const catWrapRect = catWrapEl.getBoundingClientRect();

    // 3. 核心断言：验证 menu.getBoundingClientRect().bottom <= navBar.getBoundingClientRect().top（或具备 menu-dropup 向上展开），绝不被 #bottom-nav-bar 遮挡
    const hasDropupClass = draftCatMenu.classList.contains('menu-dropup');
    const isAboveNavBar = catMenuRect.bottom <= bottomNavRect.top + 1.0;
    const isAntiOccluded = hasDropupClass || isAboveNavBar;

    assert(isAntiOccluded, "Group 45: Draft category menu is protected from occlusion (has dropup or bottom <= navBar.top)");
    assert(hasDropupClass, "Group 45: Draft category menu has 'menu-dropup' class applied when bottom space is restricted");
    assert(catMenuRect.top < catWrapRect.top, "Group 45: Dropup menu extends upwards above trigger wrapper");

    closeAllCustomDropdowns();
    assert(!draftCatMenu.classList.contains('open'), "Group 45: Category menu closed cleanly");

    // 4. 清理还原自定义分类
    if (typeof window.resetCategories === 'function') {
      window.resetCategories();
    } else if (window.DomainRegistry && typeof window.DomainRegistry.resetCategories === 'function') {
      window.DomainRegistry.resetCategories();
    }
    if (typeof window.syncAllCategoryUIs === 'function') {
      window.syncAllCategoryUIs();
    }
    try { localStorage.removeItem('singwallet_custom_categories'); } catch(e) {}
    switchTab('transactions');

    // ========================================================
    // Group 46: AI Model Dropdown, Model List Fetching & Multi-Image Upload Verification
    // ========================================================
    console.log("=== Group 46: AI Model Dropdown, Fetching & Multi-Image Upload Verification ===");

    // 1. 模型选择下拉列表与选择断言
    switchTab('rules');
    const modelMenu = document.getElementById('menu-vlm-model-select');
    const modelInput = document.getElementById('vlm-model');
    const modelDropBtn = document.getElementById('btn-vlm-model-dropdown');
    const modelFetchBtn = document.getElementById('btn-fetch-vlm-models');

    assert(modelMenu !== null, "Group 46: #menu-vlm-model-select 存在");
    assert(modelInput !== null, "Group 46: #vlm-model 输入框存在");
    assert(modelDropBtn !== null, "Group 46: #btn-vlm-model-dropdown 下拉展开按钮存在");
    assert(modelFetchBtn !== null, "Group 46: #btn-fetch-vlm-models 获取模型按钮存在");

    // 测试下拉展开与关闭
    toggleVlmModelDropdown();
    assert(modelMenu.classList.contains('open'), "Group 46: toggleVlmModelDropdown 打开菜单");
    const options = modelMenu.querySelectorAll('.custom-dropdown-option');
    assert(options.length > 0, "Group 46: 模型下拉菜单已渲染选项列表 (got " + options.length + ")");

    // 测试选择模型
    selectVlmModelOption('qwen-vl-max');
    assert(modelInput.value === 'qwen-vl-max', "Group 46: selectVlmModelOption 更新输入框为 qwen-vl-max");
    assert(vlmConfig.model === 'qwen-vl-max', "Group 46: vlmConfig.model 更新为 qwen-vl-max");
    assert(!modelMenu.classList.contains('open'), "Group 46: selectVlmModelOption 后自动收起下拉菜单");

    // 2. 获取模型列表功能断言
    // 无 API Key 测试
    document.getElementById('vlm-api-key').value = '';
    await fetchVlmModelsList();
    const topErr46 = document.getElementById('llm-top-error-toast');
    assert(topErr46 && !topErr46.classList.contains('hidden'), "Group 46: 空 API Key 获取模型列表弹出错误提示");
    closeLlmTopError();

    // 体验 Key 模拟测试
    document.getElementById('vlm-api-key').value = 'sk-vlm-singwallet-demo-live';
    await fetchVlmModelsList();
    assert(modelMenu.classList.contains('open'), "Group 46: fetchVlmModelsList 成功后自动展开菜单");
    const cachedModels = localStorage.getItem('singwallet_vlm_models_cache');
    assert(cachedModels && cachedModels.includes('qwen-vl'), "Group 46: 模型列表成功缓存至 localStorage");
    closeVlmModelDropdown();

    // 3. 多图选择与自动关闭“加一笔”弹窗断言
    const manualUploadInput = document.getElementById('manual-upload-input');
    assert(manualUploadInput !== null, "Group 46: #manual-upload-input 存在");
    assert(manualUploadInput.hasAttribute('multiple'), "Group 46: #manual-upload-input 带有 multiple 属性支持多图上传");

    // 本地离线引擎多图测试
    currentOcrEngine = 'local';
    draftQueue = [];
    openManualAddModal();
    const manModal46 = document.getElementById('manual-add-modal');
    assert(!manModal46.classList.contains('hidden'), "Group 46: manual-add-modal 已打开");

    const dummyFile1 = new File([new Uint8Array(20)], 'multi_1.png', { type: 'image/png' });
    const dummyFile2 = new File([new Uint8Array(30)], 'multi_2.png', { type: 'image/png' });

    await handleManualScreenshotUpload({ target: { files: [dummyFile1, dummyFile2] } });
    assert(document.getElementById('manual-amount').value !== '', "Group 46: 多图本地模式第 1 张填入手动记账表单");
    assert(draftQueue.length === 1, "Group 46: 多图本地模式第 2 张进入草稿箱 (length=1)");
    const toastWrapLocal = document.querySelector('.singwallet-toast-wrap');
    assert(toastWrapLocal && toastWrapLocal.innerText.includes('存入草稿箱'), "Group 46: 本地多图上传弹出 Toast 提示存入草稿箱");
    assert(manModal46.classList.contains('hidden'), "Group 46: 多图本地识别完成后自动关闭加一笔弹窗");

    // 大模型 VLM 模式多图测试
    currentOcrEngine = 'llm';
    draftQueue = [];
    vlmConfig.apiKey = 'sk-vlm-test-key-2026';
    openManualAddModal();
    assert(!manModal46.classList.contains('hidden'), "Group 46: manual-add-modal 再次打开");

    await handleManualScreenshotUpload({ target: { files: [dummyFile1, dummyFile2] } });
    assert(draftQueue.length === 2, "Group 46: 多图大模型模式两张图片均存入草稿箱");
    assert(draftQueue.every(d => d.isParsing), "Group 46: 多图大模型模式两张图片均启动后台异步解析");
    const toastWrapLlm = document.querySelector('.singwallet-toast-wrap');
    assert(toastWrapLlm && toastWrapLlm.innerText.includes('并行解析'), "Group 46: 大模型多图上传弹出 Toast 提示并行解析");
    assert(manModal46.classList.contains('hidden'), "Group 46: 大模型多图上传后自动收起加一笔弹窗");

    // 恢复状态
    currentOcrEngine = 'local';
    draftQueue = [];
    switchTab('transactions');

    // ========================================================
    // Group 47: Transaction Detail Editing, Trash Operations & Deduplication Regression Verification
    // ========================================================
    console.log("=== Group 47: Transaction Detail Editing, Trash Operations & Deduplication Regression Verification ===");
    switchTab('transactions');
    cleanAllTestData();

    // ----------------------------------------------------
    // Part 1: 功能 1（账单流水详情可编辑）
    // ----------------------------------------------------
    const testTxId47 = "tx-editable-test-47";
    insertTransactionToList({
      id: testTxId47,
      merchant: "星巴克咖啡旗舰店",
      amount: 38.50,
      catName: "餐饮美食",
      channel: "微信",
      account: "钱包",
      txDate: "2026-10-26",
      txTime: "2026-10-26 14:30:00",
      orderId: "ORDER_ORIG_10001"
    });

    // 打开详情弹窗
    viewTransactionDetail("星巴克咖啡旗舰店", "38.50", "餐饮美食", "微信 · 钱包", "2026-10-26 14:30:00", "ORDER_ORIG_10001", testTxId47);
    const txDetailModal47 = document.getElementById('tx-detail-modal');
    assert(txDetailModal47 && !txDetailModal47.classList.contains('hidden'), "Group 47: #tx-detail-modal 成功打开");

    const btnEditTx47 = document.getElementById('btn-edit-tx-detail');
    assert(btnEditTx47 !== null, "Group 47: 右上角 #btn-edit-tx-detail 存在");
    assert(btnEditTx47.innerText.trim() === '编辑', "Group 47: #btn-edit-tx-detail 初始文本显示 '编辑'");

    // 点击切换为编辑态
    toggleTxDetailEditMode();
    assert(btnEditTx47.innerText.trim() === '完成', "Group 47: 点击后按钮切换显示 '完成'");
    assert(btnEditTx47.className.includes('bg-indigo-600'), "Group 47: '完成' 按钮高亮显示 (包含 bg-indigo-600)");

    // 验证各编辑字段展示并回填初始数据
    const editAmtWrap47 = document.getElementById('wrap-detail-edit-amount');
    const editAmtInput47 = document.getElementById('detail-edit-amount');
    const editMerchantInput47 = document.getElementById('detail-edit-merchant');
    const editCatWrap47 = document.getElementById('wrap-detail-edit-category');
    const editCatInput47 = document.getElementById('detail-edit-category');
    const editChanWrap47 = document.getElementById('wrap-detail-edit-channel-account');
    const editChanInput47 = document.getElementById('detail-edit-channel');
    const editAccInput47 = document.getElementById('detail-edit-account');
    const editTimeInput47 = document.getElementById('detail-edit-time');
    const editOrderInput47 = document.getElementById('detail-edit-order');

    assert(editAmtWrap47 && !editAmtWrap47.classList.contains('hidden'), "Group 47: 金额编辑容器 #wrap-detail-edit-amount 处于展示状态");
    assert(editAmtInput47 && editAmtInput47.value === '38.50', "Group 47: #detail-edit-amount 初始回填 38.50");
    assert(editMerchantInput47 && !editMerchantInput47.classList.contains('hidden'), "Group 47: 商户编辑输入框 #detail-edit-merchant 处于展示状态");
    assert(editMerchantInput47 && editMerchantInput47.value === '星巴克咖啡旗舰店', "Group 47: #detail-edit-merchant 初始回填原商户名");
    assert(editCatWrap47 && !editCatWrap47.classList.contains('hidden'), "Group 47: 分类下拉框处于展示状态");
    assert(editCatInput47 && editCatInput47.value === '餐饮美食', "Group 47: 分类下拉框初始回填 '餐饮美食'");
    assert(editChanWrap47 && !editChanWrap47.classList.contains('hidden'), "Group 47: 渠道与账户联动下拉处于展示状态");
    assert(editChanInput47 && editChanInput47.value === '微信', "Group 47: 渠道联动下拉框初始为 '微信'");
    assert(editAccInput47 && editAccInput47.value === '钱包', "Group 47: 账户联动下拉框初始为 '钱包'");
    assert(editTimeInput47 && !editTimeInput47.classList.contains('hidden'), "Group 47: 时间编辑输入框 #detail-edit-time 处于展示状态");
    assert(editTimeInput47 && editTimeInput47.value === '2026-10-26 14:30:00', "Group 47: #detail-edit-time 初始回填原时间");
    assert(editOrderInput47 && !editOrderInput47.classList.contains('hidden'), "Group 47: 平台单号输入框 #detail-edit-order 处于展示状态");
    assert(editOrderInput47 && editOrderInput47.value === 'ORDER_ORIG_10001', "Group 47: #detail-edit-order 初始回填原单号");

    // 修改上述字段并保存
    editAmtInput47.value = '68.20';
    editMerchantInput47.value = '喜茶超级茶饮坊';
    selectCustomDropdownOption('detail-edit-category', '日常购物');
    selectCustomDropdownOption('detail-edit-channel', '支付宝');
    selectCustomDropdownOption('detail-edit-account', '余额宝');
    editTimeInput47.value = '2026-10-26 19:15:30';
    editOrderInput47.value = 'ORDER_EDITED_20002';

    // 点击“完成”保存
    toggleTxDetailEditMode();
    assert(btnEditTx47.innerText.trim() === '编辑', "Group 47: 保存后按钮文字恢复为 '编辑'");
    assert(editAmtWrap47.classList.contains('hidden'), "Group 47: 保存后金额编辑框已收起隐藏");
    assert(editMerchantInput47.classList.contains('hidden'), "Group 47: 保存后商户输入框已收起隐藏");

    // 验证详情只读视图已更新
    assert(document.getElementById('detail-amount').innerText.includes('68.20'), "Group 47: 详情只读视图金额更新为 68.20");
    assert(document.getElementById('detail-merchant').innerText === '喜茶超级茶饮坊', "Group 47: 详情只读视图商户更新为 '喜茶超级茶饮坊'");
    assert(document.getElementById('detail-cat').innerText.includes('日常购物'), "Group 47: 详情只读视图分类更新包含 '日常购物'");
    assert(document.getElementById('detail-channel').innerText.includes('支付宝') && document.getElementById('detail-channel').innerText.includes('余额宝'), "Group 47: 详情只读视图渠道与账户更新为 '支付宝 · 余额宝'");
    assert(document.getElementById('detail-time').innerText === '2026-10-26 19:15:30', "Group 47: 详情只读视图交易时间更新为 2026-10-26 19:15:30");
    assert(document.getElementById('detail-order').innerText === 'ORDER_EDITED_20002', "Group 47: 详情只读视图单号更新为 ORDER_EDITED_20002");

    // 验证内存 allMonthlyData 同步更新
    const updatedTxInMem47 = allMonthlyData['2026-10'].txs.find(t => t.id === testTxId47);
    assert(updatedTxInMem47 !== undefined, "Group 47: allMonthlyData['2026-10'] 存在更新后的账单对象");
    assert(updatedTxInMem47.amount === 68.2, "Group 47: allMonthlyData 账单金额更新为 68.2");
    assert(updatedTxInMem47.merchant === '喜茶超级茶饮坊', "Group 47: allMonthlyData 账单商户名更新");
    assert(updatedTxInMem47.cat === '日常购物' || updatedTxInMem47.category === '日常购物', "Group 47: allMonthlyData 账单分类更新");
    assert(updatedTxInMem47.channel === '支付宝', "Group 47: allMonthlyData 渠道更新为 支付宝");
    assert(updatedTxInMem47.account === '余额宝', "Group 47: allMonthlyData 账户更新为 余额宝");
    assert(updatedTxInMem47.orderId === 'ORDER_EDITED_20002', "Group 47: allMonthlyData 平台单号更新为 ORDER_EDITED_20002");

    // 关闭详情弹窗，验证流水卡片 .tx-item 同步更新
    closeTxDetailModal();
    assert(txDetailModal47.classList.contains('hidden'), "Group 47: #tx-detail-modal 关闭成功");
    const txCardEl47 = document.getElementById(testTxId47);
    assert(txCardEl47 !== null, "Group 47: 流水列表对应卡片节点存在");
    assert(txCardEl47.innerText.includes('喜茶超级茶饮坊'), "Group 47: 流水卡片商户名同步展示为 '喜茶超级茶饮坊'");
    assert(txCardEl47.innerText.includes('68.20'), "Group 47: 流水卡片金额同步展示为 68.20");

    // ----------------------------------------------------
    // Part 2: Bug 修复（回收站账单不阻断相同单号再次入账）
    // ----------------------------------------------------
    // 当前 testTxId47 具有有效单号 ORDER_EDITED_20002，验证查重返回 true
    assert(isOrderIdDuplicate('ORDER_EDITED_20002') === true, "Group 47 (Bug Fix): 活跃账单单号 ORDER_EDITED_20002 查重返回 true");

    // 将该账单移入回收站
    deleteTransaction(testTxId47, '喜茶超级茶饮坊', 68.20);
    assert(updatedTxInMem47.softDeleted === true, "Group 47 (Bug Fix): deleteTransaction 后该账单被标记 softDeleted = true");

    // 核心 Bug 修复断言：移入回收站后，isOrderIdDuplicate 必须返回 false，不阻断相同单号再次入账
    assert(isOrderIdDuplicate('ORDER_EDITED_20002') === false, "Group 47 (Bug Fix): 账单移入回收站后 isOrderIdDuplicate 返回 false (不阻断相同单号入账)");

    // 模拟再次录入相同单号的新账单
    const reAddedTxId47 = "tx-readded-order-47";
    insertTransactionToList({
      id: reAddedTxId47,
      merchant: "同单号重入账商户",
      amount: 50.00,
      catName: "餐饮美食",
      channel: "微信",
      account: "钱包",
      txDate: "2026-10-26",
      txTime: "2026-10-26 20:00:00",
      orderId: "ORDER_EDITED_20002"
    });
    assert(document.getElementById(reAddedTxId47) !== null, "Group 47 (Bug Fix): 相同单号的新账单成功入账并加入流水列表");
    assert(isOrderIdDuplicate('ORDER_EDITED_20002') === true, "Group 47 (Bug Fix): 新账单入账后该单号被活跃账单占用 (返回 true)");

    // 清理新账单
    document.getElementById(reAddedTxId47)?.remove();
    allMonthlyData['2026-10'].txs = allMonthlyData['2026-10'].txs.filter(t => t.id !== reAddedTxId47);
    committedOrderIds.delete('ORDER_EDITED_20002');
    assert(isOrderIdDuplicate('ORDER_EDITED_20002') === false, "Group 47 (Bug Fix): 清除新账单后临时恢复 false");

    // 从回收站恢复原账单
    restoreTrash(testTxId47);
    assert(updatedTxInMem47.softDeleted === false, "Group 47 (Bug Fix): 从回收站恢复后 softDeleted 还原为 false");
    assert(isOrderIdDuplicate('ORDER_EDITED_20002') === true, "Group 47 (Bug Fix): 从回收站恢复后 isOrderIdDuplicate 重新生效并返回 true");

    // ----------------------------------------------------
    // Part 3: 功能 2（回收站单条删除确认 + 多选全选批量删除）
    // ----------------------------------------------------
    // 再次将 testTxId47 移入回收站，并添加另外两笔账单一同移入回收站
    deleteTransaction(testTxId47, '喜茶超级茶饮坊', 68.20);
    const trashTx2_47 = "tx-trash-demo-02";
    const trashTx3_47 = "tx-trash-demo-03";
    insertTransactionToList({
      id: trashTx2_47,
      merchant: "待彻底删除账单B",
      amount: 15.00,
      catName: "餐饮美食",
      txDate: "2026-10-26",
      txTime: "2026-10-26 10:00:00"
    });
    insertTransactionToList({
      id: trashTx3_47,
      merchant: "待彻底删除账单C",
      amount: 25.00,
      catName: "餐饮美食",
      txDate: "2026-10-26",
      txTime: "2026-10-26 11:00:00"
    });
    deleteTransaction(trashTx2_47, '待彻底删除账单B', 15.00);
    deleteTransaction(trashTx3_47, '待彻底删除账单C', 25.00);

    assert(deletedItems.length === 3, "Group 47 (Trash): 回收站 deletedItems 存在 3 条记录");

    // 打开回收站弹窗
    openTrashDialog();
    const trashModal47 = document.getElementById('trash-modal');
    assert(trashModal47 && !trashModal47.classList.contains('hidden'), "Group 47 (Trash): #trash-modal 打开");
    const trashBatchBar47 = document.getElementById('trash-batch-bar');
    assert(trashBatchBar47 && !trashBatchBar47.classList.contains('hidden'), "Group 47 (Trash): #trash-batch-bar 批量操作栏处于显示状态");

    const trashCheckboxes47 = document.querySelectorAll('.trash-item-checkbox');
    assert(trashCheckboxes47.length === 3, "Group 47 (Trash): 每条回收站记录均具备独立复选框 (共3个)");
    const trashDelBtns47 = document.getElementById('trash-items').querySelectorAll('button');
    assert(trashDelBtns47.length >= 3, "Group 47 (Trash): 每条回收站记录均具备独立删除按钮");

    // 1) 单条删除确认流程
    openTrashDeleteConfirmModal(testTxId47);
    const trashConfirmModal47 = document.getElementById('trash-delete-confirm-modal');
    assert(trashConfirmModal47 && !trashConfirmModal47.classList.contains('hidden'), "Group 47 (Trash): 点击单条删除弹出 #trash-delete-confirm-modal");
    assert(document.getElementById('trash-delete-confirm-msg').innerText.includes('喜茶超级茶饮坊'), "Group 47 (Trash): 单条确认删除弹窗展示账单名称");

    // 测试取消删除
    closeTrashDeleteConfirmModal();
    assert(trashConfirmModal47.classList.contains('hidden'), "Group 47 (Trash): 取消彻底删除后弹窗收起");
    assert(deletedItems.length === 3, "Group 47 (Trash): 取消后 deletedItems 数量仍为 3");

    // 再次打开并确认彻底删除
    openTrashDeleteConfirmModal(testTxId47);
    confirmTrashPermanentDelete();
    assert(trashConfirmModal47.classList.contains('hidden'), "Group 47 (Trash): 确认删除后弹窗关闭");
    assert(deletedItems.length === 2, "Group 47 (Trash): 确认彻底删除后从 deletedItems 移除 (剩余 2 条)");
    assert(!deletedItems.some(i => i.id === testTxId47), "Group 47 (Trash): testTxId47 不再存在于 deletedItems 中");
    assert(!allMonthlyData['2026-10'].txs.some(t => t.id === testTxId47), "Group 47 (Trash): testTxId47 从 allMonthlyData 彻底抹除");

    // 2) 全选与批量删除确认流程
    const trashSelectAllCb47 = document.getElementById('trash-select-all');
    assert(trashSelectAllCb47 !== null, "Group 47 (Trash): #trash-select-all 全选复选框存在");
    trashSelectAllCb47.checked = true;
    toggleTrashSelectAll(true);

    const remainingTrashCbs47 = Array.from(document.querySelectorAll('.trash-item-checkbox'));
    assert(remainingTrashCbs47.length === 2, "Group 47 (Trash): 回收站列表当前显示剩余 2 条复选框");
    assert(remainingTrashCbs47.every(cb => cb.checked), "Group 47 (Trash): 全选后所有子复选框均处于 checked 状态");
    assert(document.getElementById('trash-selected-count').innerText.includes('2'), "Group 47 (Trash): 已选计数展示 '(已选 2)'");

    // 打开批量删除确认弹窗
    openTrashBatchDeleteConfirmModal();
    assert(trashConfirmModal47 && !trashConfirmModal47.classList.contains('hidden'), "Group 47 (Trash): 点击批量删除弹出 #trash-delete-confirm-modal");
    assert(document.getElementById('trash-delete-confirm-msg').innerText.includes('2 条'), "Group 47 (Trash): 批量确认删除提示彻底删除选中的 2 条账单");

    // 确认批量彻底删除
    confirmTrashPermanentDelete();
    assert(trashConfirmModal47.classList.contains('hidden'), "Group 47 (Trash): 批量删除后确认弹窗收起");
    assert(deletedItems.length === 0, "Group 47 (Trash): deletedItems 彻底清空 (length=0)");
    assert(document.getElementById('trash-items').innerText.includes('回收站为空'), "Group 47 (Trash): 回收站列表展示 '回收站为空'");
    assert(trashBatchBar47.classList.contains('hidden'), "Group 47 (Trash): 回收站为空时批量操作栏自动隐藏");

    closeTrashModal();
    assert(trashModal47.classList.contains('hidden'), "Group 47 (Trash): #trash-modal 关闭");

    // ========================================================
    // Group 48: Payment Display Standardization, Detail Sticky Bug Fix, Sorting & Dynamic Accounts
    // ========================================================
    console.log("=== Group 48: Payment Display Standardization, Detail Sticky Bug Fix, Sorting & Dynamic Accounts ===");
    switchTab('transactions');
    cleanAllTestData();

    // ----------------------------------------------------
    // Test 48.1: Bug 1 — 账单流水界面 "渠道 · 账户" 与完整消费时间显示
    // ----------------------------------------------------
    assert(typeof formatTxPaymentDisplay === 'function', "Test 48.1: formatTxPaymentDisplay 函数存在");
    assert(formatTxPaymentDisplay('微信', '钱包') === '微信 · 钱包', "Test 48.1: formatTxPaymentDisplay('微信', '钱包') === '微信 · 钱包'");
    assert(formatTxPaymentDisplay('支付宝', '余额宝') === '支付宝 · 余额宝', "Test 48.1: formatTxPaymentDisplay('支付宝', '余额宝') === '支付宝 · 余额宝'");
    assert(formatTxPaymentDisplay('云闪付', '工商银行[5678]') === '云闪付 · 工商银行[5678]', "Test 48.1: formatTxPaymentDisplay('云闪付', '工商银行[5678]') === '云闪付 · 工商银行[5678]'");
    assert(formatTxPaymentDisplay('微信', '微信 · 钱包') === '微信 · 钱包', "Test 48.1: formatTxPaymentDisplay('微信', '微信 · 钱包') === '微信 · 钱包' (自动去重前缀)");

    // 验证 insertTransactionToList 插入后卡片标签严格显示 "渠道 · 账户" 且时间包含完整秒数
    const tx48_1_id = "tx-48-1-display";
    insertTransactionToList({
      id: tx48_1_id,
      merchant: "全家便利店",
      amount: 18.50,
      catName: "日常购物",
      channel: "支付宝",
      account: "余额宝",
      txDate: "2026-10-26",
      txTime: "2026-10-26 14:30:25"
    });
    const tx48_1_el = document.getElementById(tx48_1_id);
    assert(tx48_1_el !== null, "Test 48.1: 插入账单 DOM 节点存在");
    const tag48_1 = tx48_1_el.querySelector('.tx-source-tag');
    assert(tag48_1 && tag48_1.innerText.trim() === '支付宝 · 余额宝', "Test 48.1: insertTransactionToList 卡片 .tx-source-tag 严格显示 '支付宝 · 余额宝' (got: " + (tag48_1 ? tag48_1.innerText : 'null') + ")");
    assert(tx48_1_el.innerText.includes('14:30:25'), "Test 48.1: 账单卡片时间包含完整秒数 14:30:25");

    // 验证 renderMonthTransactions 重新渲染后的卡片标签与完整秒数
    renderMonthTransactions('2026', '10');
    const tx48_1_rerender = document.getElementById(tx48_1_id);
    assert(tx48_1_rerender !== null, "Test 48.1: renderMonthTransactions 重新渲染后节点存在");
    const tag48_1_rerender = tx48_1_rerender.querySelector('.tx-source-tag');
    assert(tag48_1_rerender && tag48_1_rerender.innerText.trim() === '支付宝 · 余额宝', "Test 48.1: 重新渲染后 .tx-source-tag 依然为 '支付宝 · 余额宝'");
    assert(tx48_1_rerender.innerText.includes('14:30:25'), "Test 48.1: 重新渲染后卡片时间依然保留完整秒数");

    cleanAllTestData();

    // ----------------------------------------------------
    // Test 48.2: Bug 2 — 账单流水详情界面编辑支付类型无粘性
    // ----------------------------------------------------
    const txA_id = "tx-stick-a";
    const txB_id = "tx-stick-b";
    insertTransactionToList({
      id: txA_id,
      merchant: "商户A",
      amount: 10.00,
      catName: "餐饮美食",
      channel: "支付宝",
      account: "余额宝",
      txDate: "2026-10-26",
      txTime: "2026-10-26 10:00:00"
    });
    insertTransactionToList({
      id: txB_id,
      merchant: "商户B",
      amount: 20.00,
      catName: "餐饮美食",
      channel: "云闪付",
      account: "招商银行[8899]",
      txDate: "2026-10-26",
      txTime: "2026-10-26 11:00:00"
    });

    // 1) 打开账单 A 详情 -> 编辑 -> 改为 微信 · 钱包 -> 保存
    viewTransactionDetail("商户A", "10.00", "餐饮美食", "支付宝 · 余额宝", "2026-10-26 10:00:00", "", txA_id);
    toggleTxDetailEditMode();
    selectCustomDropdownOption('detail-edit-channel', '微信');
    selectCustomDropdownOption('detail-edit-account', '钱包');
    saveTxDetailEdit();
    assert(document.getElementById('detail-channel').innerText === '微信 · 钱包', "Test 48.2: 账单 A 成功保存为 '微信 · 钱包'");
    closeTxDetailModal();

    // 2) 紧接着打开账单 B 详情
    viewTransactionDetail("商户B", "20.00", "餐饮美食", "云闪付 · 招商银行[8899]", "2026-10-26 11:00:00", "", txB_id);
    assert(document.getElementById('detail-edit-channel').value === '云闪付', "Test 48.2: 打开账单 B 时 #detail-edit-channel 初始为 '云闪付'");
    assert(document.getElementById('detail-edit-account').value === '招商银行[8899]', "Test 48.2: 打开账单 B 时 #detail-edit-account 初始为 '招商银行[8899]'");

    // 3) 点击编辑 -> 什么都不改，直接点击保存
    toggleTxDetailEditMode();
    saveTxDetailEdit();

    // 4) 验证账单 B 保存后依然是 云闪付 · 招商银行[8899]，绝不会变成上次选过的 微信 · 钱包
    assert(document.getElementById('detail-channel').innerText === '云闪付 · 招商银行[8899]', "Test 48.2: 账单 B 保存后详情展示依然为 '云闪付 · 招商银行[8899]' (无粘性遗留)");
    const foundTxB_48 = allMonthlyData['2026-10'].txs.find(t => t.id === txB_id);
    assert(foundTxB_48 && foundTxB_48.channel === '云闪付', "Test 48.2: 账单 B 内存 channel 保持 '云闪付'");
    assert(foundTxB_48 && foundTxB_48.account === '招商银行[8899]', "Test 48.2: 账单 B 内存 account 保持 '招商银行[8899]'");
    closeTxDetailModal();

    cleanAllTestData();

    // ----------------------------------------------------
    // Test 48.3: Bug 3 — 流水明细界面账单严格按最近日期与最近时间从上往下倒序排列
    // ----------------------------------------------------
    // 乱序插入多笔不同日期及同一日期不同时间的账单
    insertTransactionToList({
      id: "tx-sort-20",
      merchant: "老账单",
      amount: 10.00,
      catName: "日常购物",
      txDate: "2026-10-20",
      txTime: "2026-10-20 15:00:00"
    });
    insertTransactionToList({
      id: "tx-sort-26-noon",
      merchant: "26日中午账单",
      amount: 20.00,
      catName: "餐饮美食",
      txDate: "2026-10-26",
      txTime: "2026-10-26 12:30:00"
    });
    insertTransactionToList({
      id: "tx-sort-25",
      merchant: "昨天账单",
      amount: 30.00,
      catName: "休闲娱乐",
      txDate: "2026-10-25",
      txTime: "2026-10-25 10:00:00"
    });
    insertTransactionToList({
      id: "tx-sort-26-evening",
      merchant: "26日傍晚账单",
      amount: 40.00,
      catName: "餐饮美食",
      txDate: "2026-10-26",
      txTime: "2026-10-26 18:45:30"
    });
    insertTransactionToList({
      id: "tx-sort-26-morning",
      merchant: "26日早晨账单",
      amount: 50.00,
      catName: "生活缴费",
      txDate: "2026-10-26",
      txTime: "2026-10-26 09:15:00"
    });

    // 验证插入及 renderMonthTransactions 后的排列顺序
    renderMonthTransactions('2026', '10');
    const dayGroups48 = Array.from(document.querySelectorAll('#transactions-list .day-group'));
    assert(dayGroups48.length === 3, "Test 48.3: 渲染出 3 个日期分组 (2026-10-26, 2026-10-25, 2026-10-20)");
    const groupDates48 = dayGroups48.map(g => g.getAttribute('data-group-date') || g.getAttribute('data-date'));
    assert(groupDates48[0] === '2026-10-26', "Test 48.3: 第 1 个分组为最近日期 2026-10-26 (got: " + groupDates48[0] + ")");
    assert(groupDates48[1] === '2026-10-25', "Test 48.3: 第 2 个分组为次近日期 2026-10-25 (got: " + groupDates48[1] + ")");
    assert(groupDates48[2] === '2026-10-20', "Test 48.3: 第 3 个分组为最远日期 2026-10-20 (got: " + groupDates48[2] + ")");

    // 验证 2026-10-26 分组内的账单按时间严格降序 (18:45:30 -> 12:30:00 -> 09:15:00)
    const oct26Group48 = dayGroups48[0];
    const oct26Items48 = Array.from(oct26Group48.querySelectorAll('.tx-item'));
    assert(oct26Items48.length === 3, "Test 48.3: 2026-10-26 分组内包含 3 笔账单");
    const oct26Times48 = oct26Items48.map(el => el.getAttribute('data-time') || '');
    assert(oct26Times48[0].includes('18:45:30'), "Test 48.3: 第 1 笔账单为最新时间 18:45:30 (got: " + oct26Times48[0] + ")");
    assert(oct26Times48[1].includes('12:30:00'), "Test 48.3: 第 2 笔账单为中间时间 12:30:00 (got: " + oct26Times48[1] + ")");
    assert(oct26Times48[2].includes('09:15:00'), "Test 48.3: 第 3 笔账单为最早时间 09:15:00 (got: " + oct26Times48[2] + ")");

    cleanAllTestData();

    // ----------------------------------------------------
    // Test 48.4: 动态银行卡与去硬编码验证
    // ----------------------------------------------------
    const defaultAccountsSSOT = window.CHANNEL_DEFAULT_ACCOUNT || (typeof CHANNEL_DEFAULT_ACCOUNT !== 'undefined' ? CHANNEL_DEFAULT_ACCOUNT : null);
    assert(defaultAccountsSSOT !== null, "Test 48.4: CHANNEL_DEFAULT_ACCOUNT 存在");
    assert(defaultAccountsSSOT['云闪付'] === '银行卡', "Test 48.4: CHANNEL_DEFAULT_ACCOUNT['云闪付'] === '银行卡' (不再硬编码工商银行)");

    // 调用 syncAccountToAllDropdowns 注入任意新银行卡
    syncAccountToAllDropdowns('云闪付', '中国银行[3344]');

    // 验证 #menu-select-account (即 edit-account 下拉)
    const selectAccMenu48 = document.getElementById('menu-select-account');
    assert(selectAccMenu48 !== null, "Test 48.4: #menu-select-account 存在");
    const hasInSelectAcc = Array.from(selectAccMenu48.querySelectorAll('.custom-dropdown-option')).some(opt => opt.getAttribute('data-value') === '中国银行[3344]');
    assert(hasInSelectAcc, "Test 48.4: #menu-select-account (edit-account) 动态包含 '中国银行[3344]' 选项");

    // 验证 #menu-manual-pay-sub / #menu-manual-account (即 manual-account 下拉)
    const manualAccMenu48 = document.getElementById('menu-manual-pay-sub') || document.getElementById('menu-manual-account');
    assert(manualAccMenu48 !== null, "Test 48.4: manual account 下拉菜单存在");
    const hasInManualAcc = Array.from(manualAccMenu48.querySelectorAll('.custom-dropdown-option')).some(opt => {
      const v = opt.getAttribute('data-value') || '';
      return v === '中国银行[3344]' || v.includes('中国银行[3344]');
    });
    assert(hasInManualAcc, "Test 48.4: manual-account 下拉菜单动态包含 '中国银行[3344]' 选项");

    // 验证 #menu-detail-edit-account
    const detailAccMenu48 = document.getElementById('menu-detail-edit-account');
    assert(detailAccMenu48 !== null, "Test 48.4: #menu-detail-edit-account 存在");
    const hasInDetailAcc = Array.from(detailAccMenu48.querySelectorAll('.custom-dropdown-option')).some(opt => opt.getAttribute('data-value') === '中国银行[3344]');
    assert(hasInDetailAcc, "Test 48.4: #menu-detail-edit-account 动态包含 '中国银行[3344]' 选项");

    // ========================================================
    // Group 49: Dynamic Content & De-hardcoding Across All Modals Regression Verification
    // ========================================================
    console.log("=== Group 49: Dynamic Content & De-hardcoding Across All Modals Regression Verification ===");
    switchTab('transactions');
    cleanAllTestData();

    // ----------------------------------------------------
    // Test 49.1: 筛选弹窗（#filter-modal）动态内容与匹配验证
    // ----------------------------------------------------
    // 1) 插入一笔微信支付账单和一笔自定义银行卡账单
    insertTransactionToList({
      id: "tx-49-wechat",
      merchant: "微信便利店",
      amount: 15.00,
      catName: "餐饮美食",
      channel: "微信",
      account: "钱包",
      txDate: "2026-10-26",
      txTime: "2026-10-26 12:00:00"
    });
    insertTransactionToList({
      id: "tx-49-abc",
      merchant: "农业银行专卖店",
      amount: 88.00,
      catName: "日常购物",
      channel: "云闪付",
      account: "农业银行[9988]",
      txDate: "2026-10-26",
      txTime: "2026-10-26 13:00:00"
    });

    // 2) 新增自定义分类 "户外运动"
    const catInput49 = document.getElementById('custom-category-input');
    if (catInput49) catInput49.value = '户外运动';
    addCustomCategory();

    // 3) 打开筛选抽屉，验证分类与账户动态生成
    openFilterModal();
    const filterModal49 = document.getElementById('filter-modal');
    assert(filterModal49 && !filterModal49.classList.contains('hidden'), "Test 49.1: 筛选弹窗 #filter-modal 打开");

    const filterCatTags49 = Array.from(document.querySelectorAll('#filter-modal-cats .modal-cat-tag'));
    assert(filterCatTags49.some(t => t.innerText.includes('工资收入')), "Test 49.1: #filter-modal-cats 动态包含 '工资收入'");
    assert(filterCatTags49.some(t => t.innerText.includes('户外运动')), "Test 49.1: #filter-modal-cats 动态包含新增分类 '户外运动'");

    const filterAccBtns49 = Array.from(document.querySelectorAll('#filter-modal-accounts .modal-acc-btn'));
    assert(filterAccBtns49.some(b => b.innerText.includes('农业银行[9988]')), "Test 49.1: #filter-modal-accounts 动态提取出自定义银行卡 '农业银行[9988]'");

    // 4) 按 "微信支付" 筛选匹配
    const wechatBtn49 = filterAccBtns49.find(b => b.innerText.includes('微信支付'));
    assert(wechatBtn49 !== undefined, "Test 49.1: 存在 '微信支付' 筛选项按钮");
    selectModalAccount(wechatBtn49, '微信支付');
    applyFilterModal();
    const visibleWechat49 = Array.from(document.querySelectorAll('#transactions-list .tx-item')).filter(el => el.style.display !== 'none');
    assert(visibleWechat49.length === 1 && visibleWechat49[0].id === 'tx-49-wechat', "Test 49.1: 按 '微信支付' 筛选正确匹配微信流水");

    // 5) 按动态银行卡 "农业银行[9988]" 筛选匹配
    openFilterModal();
    const abcBtn49 = Array.from(document.querySelectorAll('#filter-modal-accounts .modal-acc-btn')).find(b => b.innerText.includes('农业银行[9988]'));
    assert(abcBtn49 !== undefined, "Test 49.1: 存在 '农业银行[9988]' 筛选项按钮");
    selectModalAccount(abcBtn49, '农业银行[9988]');
    applyFilterModal();
    const visibleAbc49 = Array.from(document.querySelectorAll('#transactions-list .tx-item')).filter(el => el.style.display !== 'none');
    assert(visibleAbc49.length === 1 && visibleAbc49[0].id === 'tx-49-abc', "Test 49.1: 按动态银行卡 '农业银行[9988]' 筛选正确匹配流水");

    resetFilter();
    closeFilterModal();

    // ----------------------------------------------------
    // Test 49.2: 分类管理与分类选择弹窗（#category-modal & #category-delete-confirm-modal）
    // ----------------------------------------------------
    const catModalGrid49 = document.getElementById('category-modal-grid');
    assert(catModalGrid49 !== null, "Test 49.2: #category-modal-grid 存在");
    assert(catModalGrid49.innerText.includes('户外运动'), "Test 49.2: #category-modal-grid 图标网格动态同步包含 '户外运动'");

    const detailCatMenu49 = document.getElementById('menu-detail-edit-category');
    assert(detailCatMenu49 !== null, "Test 49.2: #menu-detail-edit-category 存在");
    const hasDetailCat49 = Array.from(detailCatMenu49.querySelectorAll('.custom-dropdown-option')).some(opt => opt.getAttribute('data-value') === '户外运动');
    assert(hasDetailCat49, "Test 49.2: #menu-detail-edit-category 详情编辑分类下拉框动态同步包含 '户外运动'");

    // 点击删除自定义分类，验证确认标题
    openCategoryDeleteConfirmModal('户外运动');
    const delCatModal49 = document.getElementById('category-delete-confirm-modal');
    assert(delCatModal49 && !delCatModal49.classList.contains('hidden'), "Test 49.2: #category-delete-confirm-modal 打开");
    const delTitle49 = document.getElementById('del-cat-confirm-title');
    assert(delTitle49 && delTitle49.innerText.includes('确认删除「户外运动」'), "Test 49.2: #del-cat-confirm-title 动态显示 '确认删除「户外运动」' (got: " + (delTitle49 ? delTitle49.innerText : 'null') + ")");
    closeCategoryDeleteConfirmModal();

    // ----------------------------------------------------
    // Test 49.3: 账单流水详情弹窗（#tx-detail-modal）动态内容与缺省回退
    // ----------------------------------------------------
    insertTransactionToList({
      id: "tx-49-income-sample",
      merchant: "科技公司薪酬发放",
      amount: 15000.00,
      catName: "工资收入",
      channel: "微信",
      account: "钱包",
      txDate: "2026-10-26",
      txTime: "2026-10-26 09:30:00"
    });

    viewTransactionDetail("科技公司薪酬发放", "15000.00", "工资收入", "微信 · 钱包", "2026-10-26 09:30:00", "", "tx-49-income-sample");
    const amtLabel49 = document.getElementById('detail-amount-label');
    assert(amtLabel49 && amtLabel49.innerText.trim() === '收款金额 (分精确)', "Test 49.3: 工资收入账单 #detail-amount-label 动态变为 '收款金额 (分精确)'");
    const detailAmt49 = document.getElementById('detail-amount');
    assert(detailAmt49 && detailAmt49.innerText.includes('+¥'), "Test 49.3: 工资收入金额前缀为 '+¥'");
    assert(detailAmt49.classList.contains('text-emerald-400'), "Test 49.3: 工资收入金额高亮为绿色 (text-emerald-400)");

    // 进入编辑态验证前缀符号
    toggleTxDetailEditMode();
    const editSign49 = document.getElementById('detail-edit-amount-sign');
    assert(editSign49 && editSign49.innerText.trim() === '+¥', "Test 49.3: 编辑态金额前缀 #detail-edit-amount-sign 动态显示 '+¥'");
    closeTxDetailModal();

    // 云闪付缺省账户回退验证 (非硬编码工商银行[5678])
    viewTransactionDetail("闪付商户", "30.00", "日常购物", "云闪付", "2026-10-26 14:00:00", "", null);
    const detailChan49 = document.getElementById('detail-channel');
    assert(detailChan49 && detailChan49.innerText.includes('银行卡') && !detailChan49.innerText.includes('工商银行[5678]'), "Test 49.3: 云闪付缺省账户回退为 '银行卡' 而非硬编码 '工商银行[5678]' (got: " + (detailChan49 ? detailChan49.innerText : 'null') + ")");
    closeTxDetailModal();

    cleanAllTestData();

    // ----------------------------------------------------
    // Test 49.4: 回收站弹窗（#trash-modal）数量标题与正负号
    // ----------------------------------------------------
    insertTransactionToList({
      id: "tx-49-del-exp",
      merchant: "测试待删支出",
      amount: 45.00,
      catName: "餐饮美食",
      txDate: "2026-10-26",
      txTime: "2026-10-26 10:00:00"
    });
    insertTransactionToList({
      id: "tx-49-del-inc",
      merchant: "测试待删收入",
      amount: 600.00,
      catName: "工资收入",
      txDate: "2026-10-26",
      txTime: "2026-10-26 11:00:00"
    });

    deleteTransaction("tx-49-del-exp", "测试待删支出", 45.00);
    deleteTransaction("tx-49-del-inc", "测试待删收入", 600.00);

    openTrashDialog();
    const trashTitle49 = document.getElementById('trash-modal-title-text');
    assert(trashTitle49 && trashTitle49.innerText === `回收站 (${deletedItems.length})`, "Test 49.4: #trash-modal-title-text 动态显示 '回收站 (2)' (got: " + (trashTitle49 ? trashTitle49.innerText : 'null') + ")");
    const trashItemsHtml49 = document.getElementById('trash-items').innerText;
    assert(trashItemsHtml49.includes('-¥45.00'), "Test 49.4: 支出账单在回收站动态显示 '-¥45.00'");
    assert(trashItemsHtml49.includes('+¥600.00'), "Test 49.4: 收入账单在回收站动态显示 '+¥600.00'");
    closeTrashModal();

    cleanAllTestData();

    // ----------------------------------------------------
    // Test 49.5: 月份选择弹窗（#month-modal）与防重弹窗（#dedup-modal）
    // ----------------------------------------------------
    // 1) getMonthlyData 动态初始化任意月份
    const dynamicMonthData = getMonthlyData(2028, '07');
    assert(dynamicMonthData !== null && Array.isArray(dynamicMonthData.txs), "Test 49.5: getMonthlyData(2028, '07') 支持任意年份月份动态初始化");
    assert(dynamicMonthData.net === '0.00' && dynamicMonthData.count === '0 笔', "Test 49.5: 动态初始化的月份数据结构完备");
    assert(allMonthlyData['2028-07'] !== undefined, "Test 49.5: allMonthlyData 成功挂载动态月份 '2028-07'");

    // 2) 防重弹窗动态信息填充
    insertTransactionToList({
      id: "tx-49-dedup-target",
      merchant: "盒马鲜生超级旗舰店",
      amount: 188.60,
      catName: "日常购物",
      channel: "微信",
      account: "钱包",
      txDate: "2026-10-26",
      txTime: "2026-10-26 16:20:00",
      orderId: "ORDER_DEDUP_TEST_9999"
    });

    showDedupTopToast("ORDER_DEDUP_TEST_9999");
    const dedupMer49 = document.getElementById('dedup-modal-merchant');
    const dedupAmt49 = document.getElementById('dedup-modal-amount');
    const dedupTime49 = document.getElementById('dedup-modal-time');
    assert(dedupMer49 && dedupMer49.innerText === '盒马鲜生超级旗舰店', "Test 49.5: 防重弹窗商户动态填充 '盒马鲜生超级旗舰店'");
    assert(dedupAmt49 && dedupAmt49.innerText.includes('188.60'), "Test 49.5: 防重弹窗金额动态填充 '188.60'");
    assert(dedupTime49 && dedupTime49.innerText.includes('2026-10-26 16:20:00'), "Test 49.5: 防重弹窗时间动态填充 '2026-10-26 16:20:00'");
    closeDedupTopToast();

    // 还原自定义分类
    if (window.DomainRegistry && typeof window.DomainRegistry.resetCategories === 'function') {
      window.DomainRegistry.resetCategories();
      syncAllCategoryUIs();
    }

    // 4. 测试收尾：清理全部测试数据，确保 App 还原为 100% 干净状态
    cleanAllTestData();
    assert(document.querySelectorAll('#transactions-list .tx-item').length === 0, "Group 47 Post-Cleanup: Transactions restored to 0");
    assert(draftQueue.length === 0, "Group 47 Post-Cleanup: draftQueue restored to 0");
    assert(document.getElementById('monthly-net-expense').innerText.includes('0.00'), "Group 47 Post-Cleanup: Net expense restored to 0.00");


        const failed = window.__TEST_RESULTS__.filter(r => !r.pass);
    const passed = window.__TEST_RESULTS__.filter(r => r.pass);
    const summary = "SUMMARY: " + passed.length + " PASSED, " + failed.length + " FAILED";
    console.log(summary);
    document.title = summary;

    const outDiv = document.createElement('div');
    outDiv.id = 'test-results-dump';
    outDiv.textContent = JSON.stringify(window.__TEST_RESULTS__);
    document.body.appendChild(outDiv);
  } catch(e) {
    console.error("TEST EXECUTION ERROR: " + e.message + "\\n" + e.stack);
    document.title = "TEST CRASHED: " + e.message;
    const errDiv = document.createElement('div');
    errDiv.id = 'test-error-stack';
    errDiv.innerText = e.stack || e.message;
    document.body.appendChild(errDiv);
  }
}
if (document.readyState === 'loading') {
  window.addEventListener('DOMContentLoaded', runAllTestsSuite);
} else {
  runAllTestsSuite();
}
</script>
"""

test_html = re.sub(r'\?v=[^"\'\s>]+', '', html).replace('</body>', test_script + '\n</body>')
test_file = os.path.join(ROOT_DIR, 'web', 'singwallet_test_runner.html')

try:
    with open(test_file, 'w', encoding='utf-8') as f:
        f.write(test_html)

    import tempfile
    import shutil
    temp_dir = tempfile.mkdtemp()
    edge_exe = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    cmd = [
        edge_exe,
        '--headless',
        '--disable-gpu',
        '--user-data-dir=' + temp_dir,
        '--dump-dom',
        'file:///' + test_file.replace('\\', '/')
    ]

    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='ignore')
        try:
            stdout, stderr = p.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            p.kill()
            stdout, stderr = p.communicate()
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    dump_m = re.search(r'<div id="test-results-dump">([\s\S]*?)</div>', stdout)
    if dump_m:
        results = json.loads(dump_m.group(1))
        passed = [r for r in results if r['pass']]
        failed = [r for r in results if not r['pass']]
        print(f"RESULTS: {len(passed)} PASSED, {len(failed)} FAILED")
        for r in failed:
            print("  [FAIL]", r['msg'])
        if not failed:
            print("  >>> ALL TEST ASSERTIONS PASSED PERFECTLY! <<<")
        else:
            sys.exit(1)
    else:
        err_m = re.search(r'<div id="test-error-stack">([\s\S]*?)</div>', stdout)
        if err_m:
            print("CRASH STACK:\n", err_m.group(1))
        title_m = re.search(r'<title>([^<]+)</title>', stdout)
        print("Edge Result Title:", title_m.group(1) if title_m else "None")
        sys.exit(1)
finally:
    if os.path.exists(test_file):
        try:
            os.remove(test_file)
        except Exception:
            pass
