import json

with open(r'c:\Other\Projects\singwallet\scratch\ocr_raw_extracted.json', 'r', encoding='utf-8-sig') as f:
    data = json.load(f)

for idx, img in enumerate(data):
    print(f"\n================ IMAGE {idx+1}: {img['ImagePath'].split('\\')[-1]} ================")
    print(f"Dimensions: {img['ImageWidth']}x{img['ImageHeight']}, Total Lines: {img['LineCount']}")
    for l_idx, line in enumerate(img['Lines']):
        box = line['Box']
        print(f"[{l_idx:02d}] ({box['Left']:.3f}, {box['Top']:.3f}, {box['Width']:.3f}, {box['Height']:.3f}): {line['Text']}")
