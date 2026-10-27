import re

def clean_emojis():
    with open('singwallet_preview.html', 'r', encoding='utf-8') as f:
        text = f.read()

    # Replace toasts
    text = text.replace("showToast('📱 灵动岛：", "showToast('灵动岛：")
    text = text.replace("showToast('✨ 已填入", "showToast('已填入")

    # Line 63
    text = text.replace('data-ui-icon="aiRobot">🤖</div>', 'data-ui-icon="aiRobot"></div>')

    # Line 424
    text = text.replace('id="suggested-icon" data-cat-icon="餐饮美食" class="text-sm shrink-0">🍔</span>', 'id="suggested-icon" data-cat-icon="餐饮美食" class="text-sm shrink-0"></span>')

    # Dropdown options and category select
    emojis = {
        '餐饮美食': '🍔',
        '交通出行': '🚗',
        '日常购物': '🛒',
        '休闲娱乐': '🎮',
        '生活缴费': '⚡',
        '医疗健康': '💊',
        '其他支出': '📦',
        '工资收入': '💰'
    }

    for cat, em in emojis.items():
        text = text.replace(f"onDraftCategorySelect('{em}', '{cat}'", f"onDraftCategorySelect('', '{cat}'")
        text = text.replace(f'<span class="shrink-0 text-sm" data-cat-icon="{cat}">{em}</span>', f'<span class="shrink-0 text-sm" data-cat-icon="{cat}"></span>')
        text = text.replace(f'<span data-cat-icon="{cat}">{em}</span>', f'<span data-cat-icon="{cat}"></span>')
        text = text.replace(f"selectCategory('{em}', '{cat}'", f"selectCategory('', '{cat}'")
        text = text.replace(f'<span class="text-2xl block mb-1" data-cat-icon="{cat}">{em}</span>', f'<span class="text-2xl block mb-1" data-cat-icon="{cat}"></span>')

    # Remaining UI icons
    text = text.replace('<span data-ui-icon="aiRobot">🤖</span>', '<span data-ui-icon="aiRobot"></span>')
    text = text.replace('<span data-ui-icon="sparkles">✨</span>', '<span data-ui-icon="sparkles"></span>')
    text = text.replace('<span data-ui-icon="bulb">💡</span>', '<span data-ui-icon="bulb"></span>')

    with open('singwallet_preview.html', 'w', encoding='utf-8') as f:
        f.write(text)

    print('Successfully processed singwallet_preview.html')

if __name__ == '__main__':
    clean_emojis()
