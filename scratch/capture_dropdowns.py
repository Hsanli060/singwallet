import os
import subprocess
import time

brain_dir = r"C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5"
preview_path = os.path.join(brain_dir, "singwallet_preview.html")

with open(preview_path, 'r', encoding='utf-8') as f:
    html = f.read()

# 1. Capture quick-date-dropdown open
script_date = """
<script>
window.addEventListener('load', () => {
  setTimeout(() => {
    toggleCustomDropdown('quick-date-dropdown');
  }, 200);
});
</script>
"""
tmp_date_file = os.path.abspath('scratch/temp_date_snap.html')
with open(tmp_date_file, 'w', encoding='utf-8') as f:
    f.write(html.replace('</body>', script_date + '</body>'))

edge_exe = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
snap1_path = os.path.join(brain_dir, 'snap_quick_date_dropdown.png')

cmd1 = [
    edge_exe,
    '--headless',
    '--disable-gpu',
    '--window-size=430,932',
    f'--screenshot={snap1_path}',
    'file:///' + tmp_date_file.replace('\\', '/')
]
subprocess.run(cmd1, capture_output=True)
print("Saved snap1:", os.path.exists(snap1_path), snap1_path)

# 2. Capture drafts channel dropdown open
script_channel = """
<script>
window.addEventListener('load', () => {
  setTimeout(() => {
    switchTab('drafts');
    setTimeout(() => {
      toggleCustomDropdown('select-channel');
    }, 150);
  }, 200);
});
</script>
"""
tmp_chan_file = os.path.abspath('scratch/temp_channel_snap.html')
with open(tmp_chan_file, 'w', encoding='utf-8') as f:
    f.write(html.replace('</body>', script_channel + '</body>'))

snap2_path = os.path.join(brain_dir, 'snap_draft_channel_dropdown.png')
cmd2 = [
    edge_exe,
    '--headless',
    '--disable-gpu',
    '--window-size=430,932',
    f'--screenshot={snap2_path}',
    'file:///' + tmp_chan_file.replace('\\', '/')
]
subprocess.run(cmd2, capture_output=True)
print("Saved snap2:", os.path.exists(snap2_path), snap2_path)

# 3. Capture manual record modal category dropdown open
script_modal = """
<script>
window.addEventListener('load', () => {
  setTimeout(() => {
    openQuickRecordModal();
    setTimeout(() => {
      toggleCustomDropdown('manual-category');
    }, 150);
  }, 200);
});
</script>
"""
tmp_modal_file = os.path.abspath('scratch/temp_modal_snap.html')
with open(tmp_modal_file, 'w', encoding='utf-8') as f:
    f.write(html.replace('</body>', script_modal + '</body>'))

snap3_path = os.path.join(brain_dir, 'snap_modal_category_dropdown.png')
cmd3 = [
    edge_exe,
    '--headless',
    '--disable-gpu',
    '--window-size=430,932',
    f'--screenshot={snap3_path}',
    'file:///' + tmp_modal_file.replace('\\', '/')
]
subprocess.run(cmd3, capture_output=True)
print("Saved snap3:", os.path.exists(snap3_path), snap3_path)
