with open('tools/run_browser_tests.py', 'r', encoding='utf-8') as f:
    c = f.read()

target = """    // Group 16: Escape key closes open dropdown
    switchTab('transactions');
    toggleCustomDropdown('quick-date-dropdown');
    assert(qdMenu.classList.contains('open'), "quick-date-dropdown open before Escape");
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    assert(!qdMenu.classList.contains('open'), "quick-date-dropdown closed after Escape");"""

addition = """    // Group 16: Escape key closes open dropdown
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
    closeTxDetailModal();"""

assert target in c, "Could not find target"
c = c.replace(target, addition, 1)

with open('tools/run_browser_tests.py', 'w', encoding='utf-8') as f:
    f.write(c)

print('Successfully added Group 17 test')
