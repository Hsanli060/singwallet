import json
import re

with open(r'c:\Other\Projects\singwallet\scratch\ocr_raw_extracted.json', 'r', encoding='utf-8-sig') as f:
    data = json.load(f)

for idx, img in enumerate(data):
    print(f"\n================ IMAGE {idx+1}: {img['ImagePath'].split('\\')[-1]} ================")
    lines = img['Lines']
    
    # 1. Normalize text in each line
    norm_lines = []
    for l in lines:
        t = l['Text'].strip()
        # Remove spaces between CJK characters
        t = re.sub(r'([\u4e00-\u9fa5])\s+([\u4e00-\u9fa5])', r'\1\2', t)
        t = re.sub(r'([\u4e00-\u9fa5])\s+([\u4e00-\u9fa5])', r'\1\2', t)
        # Remove spaces in numbers/decimals: "15 . 77" -> "15.77", "一 70 ， 00" -> "-70.00"
        t = re.sub(r'^[一—–－-]\s*(\d)', r'-\1', t)
        t = re.sub(r'(\d)\s*([.,，．·])\s*(\d)', r'\1.\3', t)
        t = re.sub(r'(\d)\s*([.,，．·])\s*(\d)', r'\1.\3', t)
        norm_lines.append({
            'text': t,
            'box': l['Box']
        })
    
    # 2. Pair key-values: left column (left < 0.22) and right column (left >= 0.22) with similar top
    paired = []
    used_right = set()
    left_lines = [l for l in norm_lines if l['box']['Left'] < 0.22 and l['box']['Top'] > 0.3]
    right_lines = [l for l in norm_lines if l['box']['Left'] >= 0.22 and l['box']['Top'] > 0.3]
    
    for l in left_lines:
        match_r = None
        min_dy = 0.02
        for r_idx, r in enumerate(right_lines):
            if r_idx in used_right: continue
            dy = abs(l['box']['Top'] - r['box']['Top'])
            if dy < min_dy:
                min_dy = dy
                match_r = (r_idx, r)
        if match_r:
            used_right.add(match_r[0])
            paired.append(f"{l['text']}：{match_r[1]['text']}")
        else:
            paired.append(l['text'])
            
    # Also find prominent amount line (around top 0.2 - 0.3)
    amounts = [l['text'] for l in norm_lines if 0.2 <= l['box']['Top'] <= 0.32 and re.search(r'\d+\.\d{2}', l['text'])]
    # Also find prominent merchant header (around top 0.17 - 0.24)
    merchants = [l['text'] for l in norm_lines if 0.17 <= l['box']['Top'] <= 0.24 and not re.search(r'\d+\.\d{2}', l['text'])]
    
    print("Prominent Merchant Header:", merchants)
    print("Prominent Amount:", amounts)
    print("Paired Key-Values:")
    for p in paired:
        print("  *", p)
