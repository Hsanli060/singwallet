with open('tools/run_browser_tests.py', 'r', encoding='utf-8') as f:
    content = f.read()

target = """    loadDraftData(draftQueue[2]); // draft-003: channel='支付宝', account='招商银行储蓄卡(1234)'
    assert(chanInput.value === '支付宝', "Draft 3: chanInput value is 支付宝");
    assert(document.getElementById('label-select-channel').textContent.trim() === '支付宝', "Draft 3: chanLabel is 支付宝");
    assert(accInput.value === '招商银行储蓄卡(1234)', "Draft 3: accInput value is 招商银行储蓄卡(1234)");
    assert(accLabel.textContent.trim() === '招商银行储蓄卡(1234)', "Draft 3: accLabel is 招商银行储蓄卡(1234)");"""

replacement = """    loadDraftData(draftQueue[2]); // draft-bill-3: channel='微信支付', account='微信钱包'
    assert(chanInput.value === '微信支付', "Draft 3: chanInput value is 微信支付");
    assert(document.getElementById('label-select-channel').textContent.trim() === '微信支付', "Draft 3: chanLabel is 微信支付");
    assert(accInput.value === '微信钱包', "Draft 3: accInput value is 微信钱包");
    assert(accLabel.textContent.trim() === '微信钱包', "Draft 3: accLabel is 微信钱包");"""

if target in content:
    content = content.replace(target, replacement)
    with open('tools/run_browser_tests.py', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Replaced successfully!")
else:
    print("Target not found!")
