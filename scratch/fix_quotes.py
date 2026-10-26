with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
    c = f.read()

target1 = 'showToast(当前待确认队列中没有 ≥% 的高置信度草稿);'
repl1 = 'showToast("当前待确认队列中没有 ≥" + autoCommitThreshold + "% 的高置信度草稿");'
if target1 in c:
    c = c.replace(target1, repl1)
    print("Fixed target1")

# Also check for any other unquoted showToast
import re
# Find showToast(something without quotes or backticks)
def fix_toast(m):
    arg = m.group(1).strip()
    if not (arg.startswith('"') or arg.startswith("'") or arg.startswith('`')):
        return f'showToast("{arg}")'
    return m.group(0)

c = re.sub(r'showToast\(([^"\'`\)\n]+)\);', fix_toast, c)

with open('singwallet_preview.html', 'w', encoding='utf-8') as f:
    f.write(c)

# Extract script and check with node
script_start = c.find('<script>')
script_end = c.rfind('</script>')
script = c[script_start+8:script_end]

with open('scratch/test_syntax.js', 'w', encoding='utf-8') as f:
    f.write(script)

print("Saved test_syntax.js")
