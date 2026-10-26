with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Add HTML input-time
target_html = '''            <!-- Merchant -->
            <div>
              <label class="block text-xs font-medium text-slate-400 mb-1">商户名称</label>
              <input id="input-merchant" type="text" value="麦当劳（王府井店）" class="w-full px-3 py-2 text-sm rounded-xl bg-slate-900 border border-slate-700 text-white focus:ring-2 focus:ring-indigo-500 outline-none transition-all">
            </div>'''

addition_html = '''            <!-- Merchant -->
            <div>
              <label class="block text-xs font-medium text-slate-400 mb-1">商户名称</label>
              <input id="input-merchant" type="text" value="麦当劳（王府井店）" class="w-full px-3 py-2 text-sm rounded-xl bg-slate-900 border border-slate-700 text-white focus:ring-2 focus:ring-indigo-500 outline-none transition-all">
            </div>

            <!-- Transaction Time (OCR Extracted & Editable) -->
            <div>
              <div class="flex items-center justify-between mb-1">
                <label class="block text-xs font-medium text-slate-400">交易时间</label>
                <span class="text-[10px] text-indigo-400 font-mono">OCR 自动解析识别</span>
              </div>
              <input id="input-time" type="text" value="2026-10-25 14:19:38" class="w-full px-3 py-2 text-sm rounded-xl bg-slate-900 border border-slate-700 text-white focus:ring-2 focus:ring-indigo-500 outline-none transition-all font-mono">
            </div>'''

assert target_html in c, "target_html not found"
c = c.replace(target_html, addition_html, 1)

# 2. Add loadDraftData handling
target_load = '''      const inAmt = document.getElementById('input-amount');
      const inMer = document.getElementById('input-merchant');
      const selChan = document.getElementById('select-channel');
      const selAcc = document.getElementById('select-account');
      if (inAmt) inAmt.value = draft.amount.toFixed(2);
      if (inMer) inMer.value = draft.merchant;
      if (selChan) selChan.value = draft.channel;
      if (selAcc) selAcc.value = draft.account;'''

addition_load = '''      const inAmt = document.getElementById('input-amount');
      const inMer = document.getElementById('input-merchant');
      const inTime = document.getElementById('input-time');
      const selChan = document.getElementById('select-channel');
      const selAcc = document.getElementById('select-account');
      if (inAmt) inAmt.value = draft.amount.toFixed(2);
      if (inMer) inMer.value = draft.merchant;
      if (inTime) inTime.value = draft.time || '';
      if (selChan) selChan.value = draft.channel;
      if (selAcc) selAcc.value = draft.account;'''

assert target_load in c, "target_load not found"
c = c.replace(target_load, addition_load, 1)

# 3. Add fillTime helper
target_fill = '''    function fillMerchant(merchant) {
      document.getElementById('input-merchant').value = merchant;
      highlightInput('input-merchant');
      showToast(`✨ OCR商户名已自动提取回填: ${merchant}`);
    }'''

addition_fill = '''    function fillMerchant(merchant) {
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

assert target_fill in c, "target_fill not found"
c = c.replace(target_fill, addition_fill, 1)

# 4. Make ocrTime clickable
target_ocr_time = '''      if (ocrTime) ocrTime.innerText = `支付时间: ${draft.time}`;'''
addition_ocr_time = '''      if (ocrTime) {
        ocrTime.innerText = `支付时间: ${draft.time}`;
        ocrTime.style.cursor = 'pointer';
        ocrTime.title = '点击回填此交易时间';
        ocrTime.onclick = () => fillTime(draft.time);
      }'''

assert target_ocr_time in c, "target_ocr_time not found"
c = c.replace(target_ocr_time, addition_ocr_time, 1)

with open('singwallet_preview.html', 'w', encoding='utf-8') as f:
    f.write(c)

# Check script with node
script_start = c.find('<script>')
script_end = c.rfind('</script>')
script = c[script_start+8:script_end]

with open('scratch/test_syntax.js', 'w', encoding='utf-8') as f:
    f.write(script)

print("Saved and extracted JS successfully!")
