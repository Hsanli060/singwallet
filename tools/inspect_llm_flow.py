import os
import glob
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')

# tools/inspect_llm_flow.py
# Supports both legacy monolithic singwallet_preview.html and modular preview/js/*.js files
all_texts = []
if os.path.exists('singwallet_preview.html'):
    with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
        all_texts.append(f.read())

for js_file in sorted(glob.glob('preview/js/*.js')):
    with open(js_file, 'r', encoding='utf-8') as f:
        all_texts.append(f.read())

text = "\n\n".join(all_texts)

def show_section(title, start_str, length=1500):
    idx = text.find(start_str)
    if idx != -1:
        print(f"=== {title} ===")
        print(text[idx:idx+length])
    else:
        print(f"=== {title} NOT FOUND ===")

show_section('parseBillWithVlm', 'async function parseBillWithVlm')
show_section('parseBillWithLocalEngine', 'function parseBillWithLocalEngine')
show_section('handleManualScreenshotUpload', 'async function handleManualScreenshotUpload')
show_section('LLM Config State & Storage', 'vlmConfig =')
