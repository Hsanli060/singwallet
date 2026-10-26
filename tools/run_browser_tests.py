import os
import subprocess
import re
import json
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')



preview_path = os.path.abspath('singwallet_preview.html')
with open(preview_path, 'r', encoding='utf-8') as f:
    html = f.read()

test_script = r"""
<script>
window.__TEST_RESULTS__ = [];
function assert(cond, msg) {
  if (cond) {
    window.__TEST_RESULTS__.push({ pass: true, msg: msg });
  } else {
    window.__TEST_RESULTS__.push({ pass: false, msg: msg });
    console.error("FAIL: " + msg);
  }
}

window.addEventListener('DOMContentLoaded', () => {
  try {
    console.log("=== COMPREHENSIVE BROWSER DROPDOWN TEST SUITE ===");

    // Group 1: Verify all 8 custom dropdown containers and hidden inputs
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

    // Group 11: Rule match type dropdown and alias test
    const ruleTypeInput = document.getElementById('rule-match-type');
    selectCustomDropdownOption('rule-match-type', 'exact');
    assert(ruleTypeInput.value === 'exact', "rule-match-type value is exact");
    assert(document.getElementById('label-rule-match-type').textContent.includes('全词精确匹配'), "rule-match-type label has 全词精确匹配");

    ruleTypeInput.value = '通配符';
    assert(ruleTypeInput.value === '通配符', "ruleTypeInput is 通配符");
    assert(document.getElementById('label-rule-match-type').textContent.includes('通配符'), "rule-match-type label matched 通配符 via alias");

    // Group 12: Rule target cat dropdown test
    selectCustomDropdownOption('rule-target-cat', '日常购物');
    assert(document.getElementById('rule-target-cat').value === '日常购物', "rule-target-cat value is 日常购物");
    assert(document.getElementById('label-rule-target-cat').textContent.trim() === '日常购物', "rule-target-cat label is 日常购物");

    // Group 13: Manual transaction modal dropdowns
    selectCustomDropdownOption('manual-category', '交通出行');
    assert(document.getElementById('manual-category').value === '交通出行', "manual-category value is 交通出行");
    assert(document.getElementById('label-manual-category').textContent.trim() === '交通出行', "manual-category label is 交通出行");

    selectCustomDropdownOption('manual-account', '微信 · 招商银行(8848)');
    assert(document.getElementById('manual-account').value === '微信 · 招商银行(8848)', "manual-account value is 微信 · 招商银行(8848)");
    assert(document.getElementById('label-manual-account').textContent.trim() === '微信 · 招商银行(8848)', "manual-account label is 微信 · 招商银行(8848)");

    // Group 14: Acc add type dropdown & alias
    const accTypeInput = document.getElementById('acc-add-type');
    selectCustomDropdownOption('acc-add-type', 'credit_card');
    assert(accTypeInput.value === 'credit_card', "acc-add-type value is credit_card");
    assert(document.getElementById('label-acc-add-type').textContent.includes('信用卡'), "acc-add-type label has 信用卡");

    accTypeInput.value = '微信钱包';
    assert(document.getElementById('label-acc-add-type').textContent.includes('微信钱包'), "acc-add-type matched '微信钱包' via alias");

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

    // Group 22: 删除账单后净支出与总支出扣减联动及撤回/还原恢复 (Bug 修复验证)
    const netBeforeDel = parseFloat(document.getElementById('total-net-expense').innerText.replace(/[¥\s,]/g, ''));
    const expBeforeDel = parseFloat(document.getElementById('total-expense').innerText.replace(/[¥\s,]/g, ''));
    
    // Find subwayTx delete button and click it (amount = 5.00)
    const delBtn = subwayTx.querySelector('button');
    assert(delBtn !== null, "Delete button found on subwayTx");
    delBtn.click(); // deleteTransaction('...', '杭州市地铁集团有限责任公司', 5.00)
    
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
    delBtn.click();
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
    switchTab('drafts');
    resetDemoDrafts();
    const orderBeforeBatch = draftQueue[0].orderId;
    batchConfirmHighConfidenceDrafts();
    assert(isOrderIdDuplicate(orderBeforeBatch), "Batch confirmed draft order is now marked duplicate in isOrderIdDuplicate");
    assert(dedupToast.classList.contains('hidden'), "Dedup toast is closed after batch confirmation");

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
    provSelect.value = 'qwen';
    onVlmProviderChange('qwen');
    assert(document.getElementById('vlm-endpoint').value.includes('dashscope.aliyuncs.com'), "Qwen default endpoint configured");
    document.getElementById('vlm-api-key').value = 'sk-vlm-test-key-2026';
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

    // Test Gemini provider change configuration
    onVlmProviderChange('gemini');
    assert(document.getElementById('vlm-endpoint').value.includes('googleapis.com'), "Gemini endpoint contains googleapis.com");
    assert(document.getElementById('vlm-model').value === 'gemini-1.5-flash', "Gemini model is gemini-1.5-flash");

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

    // 通过自定义下拉选择切换服务商
    selectCustomDropdownOption('vlm-provider-select', 'gemini');
    assert(vlmProviderEl.value === 'gemini', "Group 28: 自定义下拉切换为 gemini");
    assert(vlmLabel.innerText.includes('Gemini'), "Group 28: 自定义下拉标签更新为 Gemini: " + vlmLabel.innerText);
    assert(vlmEndpointEl.value.includes('generativelanguage.googleapis.com'), "Group 28: Gemini 端点联动成功");
    assert(vlmModelEl.value === 'gemini-1.5-flash', "Group 28: Gemini 模型联动为 gemini-1.5-flash");

    selectCustomDropdownOption('vlm-provider-select', 'openai');
    assert(vlmProviderEl.value === 'openai', "Group 28: 自定义下拉切换为 openai");
    assert(vlmLabel.innerText.includes('OpenAI'), "Group 28: 自定义下拉标签更新为 OpenAI: " + vlmLabel.innerText);
    assert(vlmEndpointEl.value.includes('api.openai.com'), "Group 28: OpenAI 端点联动成功");
    assert(vlmModelEl.value === 'gpt-4o-mini', "Group 28: OpenAI 模型联动为 gpt-4o-mini");

    // 一键体验配置
    fillVlmDemoKey();
    assert(vlmProviderEl.value === 'qwen', "Group 28: 一键体验配置恢复为 qwen");
    assert(vlmLabel.innerText.includes('通义千问'), "Group 28: 一键体验标签恢复为通义千问");
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
    saveLlmConfigFromInputs(false);
    testVlmConnection();
    assert(vlmStatusEl.innerText.includes('未配置 API Key'), "Group 28: 空 API Key 连通失败提示: " + vlmStatusEl.innerText);
    const topErrorToast = document.getElementById('llm-top-error-toast');
    assert(topErrorToast !== null && !topErrorToast.classList.contains('hidden'), "Group 28: 连通失败在上方弹出临时小窗口");
    assert(document.getElementById('llm-error-msg').innerText.includes('未配置 API Key'), "Group 28: 上方小窗口显示未配置 API Key 错误");
    closeLlmTopError();

    // 8. 测试连通性：401 Unauthorized 错误提示
    vlmKeyEl.value = 'invalid-key';
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


    const failed = window.__TEST_RESULTS__.filter(r => !r.pass);
    const passed = window.__TEST_RESULTS__.filter(r => r.pass);
    const summary = "SUMMARY: " + passed.length + " PASSED, " + failed.length + " FAILED";
    console.log(summary);
    document.title = summary;

    const outDiv = document.createElement('div');
    outDiv.id = 'test-results-dump';
    outDiv.innerHTML = JSON.stringify(window.__TEST_RESULTS__);
    document.body.appendChild(outDiv);
  } catch(e) {
    console.error("TEST EXECUTION ERROR: " + e.message + "\\n" + e.stack);
    document.title = "TEST CRASHED: " + e.message;
  }
});
</script>
"""

test_html = html.replace('</body>', test_script + '\n</body>')
test_file = os.path.abspath('tools/test_runner.html')
with open(test_file, 'w', encoding='utf-8') as f:
    f.write(test_html)

edge_exe = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
cmd = [
    edge_exe,
    '--headless',
    '--disable-gpu',
    '--dump-dom',
    'file:///' + test_file.replace('\\', '/')
]

res = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='ignore')

dump_m = re.search(r'<div id="test-results-dump">([^<]+)</div>', res.stdout)
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
    title_m = re.search(r'<title>([^<]+)</title>', res.stdout)
    print("Edge Result Title:", title_m.group(1) if title_m else "None")

# Cleanup test_runner.html
if os.path.exists(test_file):
    try:
        os.remove(test_file)
    except Exception:
        pass
