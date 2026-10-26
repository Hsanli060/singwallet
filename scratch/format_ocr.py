import json

with open(r'c:\Other\Projects\singwallet\scratch\ocr_raw_extracted.json', 'r', encoding='utf-8-sig') as f:
    data = json.load(f)

output_lines = []
for idx, img in enumerate(data):
    img_name = img['ImagePath'].split('\\')[-1]
    output_lines.append(f"\n================ IMAGE {idx+1}: {img_name} ================")
    output_lines.append(f"Dimensions: {img['ImageWidth']}x{img['ImageHeight']}, Total Lines: {img['LineCount']}")
    for l_idx, line in enumerate(img['Lines']):
        box = line['Box']
        text = line['Text']
        output_lines.append(f"[{l_idx:02d}] ({box['Left']:.3f}, {box['Top']:.3f}, {box['Width']:.3f}, {box['Height']:.3f}): {text}")

with open(r'c:\Other\Projects\singwallet\scratch\ocr_readable.txt', 'w', encoding='utf-8') as f:
    f.write('\n'.join(output_lines))

print("Wrote ocr_readable.txt successfully!")
