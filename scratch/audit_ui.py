import re

with open(r'c:\Other\Projects\singwallet\singwallet_preview.html', 'r', encoding='utf-8') as f:
    html = f.read()

print("--- SELECT ELEMENTS ---")
selects = re.findall(r'<select[\s\S]*?</select>', html)
print(f"Total <select>: {len(selects)}")

print("\n--- CUSTOM DROPDOWNS ---")
containers = re.findall(r'<div class="custom-dropdown-container[^"]*" id="([^"]+)" data-id="([^"]+)">', html)
for c in containers:
    print(f"Found custom dropdown: id={c[0]}, data-id={c[1]}")

print("\n--- INPUT CONTROLS ---")
inputs = re.findall(r'<input[^>]+>', html)
for inp in inputs:
    if 'type="hidden"' not in inp:
        # Check border radius
        has_round = 'rounded' in inp
        print(f"Input: {inp[:80]}... rounded={has_round}")

print("\n--- TOTAL DROPDOWNS COUNT ---")
print(f"Total custom dropdown components: {len(containers)}")
