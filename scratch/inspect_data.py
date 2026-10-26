import sys
sys.stdout.reconfigure(encoding='utf-8')

with open(r'c:\Other\Projects\singwallet\singwallet_preview.html', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'function loadDraftData' in line or 'function renderDraftQueue' in line:
        print(f"Line {i+1}:")
        for j in range(i, min(i+50, len(lines))):
            print(f"  {lines[j]}", end='')
        print("\n" + "="*50)
