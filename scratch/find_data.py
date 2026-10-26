import re

with open(r'c:\Other\Projects\singwallet\singwallet_preview.html', 'r', encoding='utf-8') as f:
    content = f.read()

# Search for draft or tx lists
for m in re.finditer(r'(let|const|var)\s+([a-zA-Z0-9_]*transactions[a-zA-Z0-9_]*|[a-zA-Z0-9_]*drafts[a-zA-Z0-9_]*)\s*=', content, re.IGNORECASE):
    print(m.group(0))

# Also search for arrays with sample data
matches = re.findall(r'(let|const|var)\s+([a-zA-Z0-9_]+)\s*=\s*\[\s*\{', content)
print("Arrays of objects:", matches)
