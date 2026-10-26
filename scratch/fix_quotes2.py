with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace('curExpEl.innerText = ¥ ;', "curExpEl.innerText = '¥ ' + curExpense.toFixed(2);")
c = c.replace('curNetEl.innerText = ¥ ;', "curNetEl.innerText = '¥ ' + curNet.toFixed(2);")

with open('singwallet_preview.html', 'w', encoding='utf-8') as f:
    f.write(c)

script_start = c.find('<script>')
script_end = c.rfind('</script>')
script = c[script_start+8:script_end]

with open('scratch/test_syntax.js', 'w', encoding='utf-8') as f:
    f.write(script)

print("Saved")
