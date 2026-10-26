with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    if 'showToast(' in line and '笔高置信度账单入账' in line:
        new_lines.append('      showToast(`🎉 成功将 ${highList.length} 笔高置信度账单入账 (共 ¥${totalAmt.toFixed(2)})！`);\n')
    else:
        new_lines.append(line)

content = ''.join(new_lines)
with open('singwallet_preview.html', 'w', encoding='utf-8') as f:
    f.write(content)

script_start = content.find('<script>')
script_end = content.rfind('</script>')
script = content[script_start+8:script_end]

with open('scratch/test_syntax.js', 'w', encoding='utf-8') as f:
    f.write(script)

print("Saved cleanly!")
