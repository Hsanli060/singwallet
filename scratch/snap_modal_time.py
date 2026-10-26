import os
import subprocess

preview_path = os.path.abspath('singwallet_preview.html')
with open(preview_path, 'r', encoding='utf-8') as f:
    html = f.read()

inject = """
<script>
window.addEventListener('DOMContentLoaded', () => {
  switchTab('drafts');
  switchDraft(3); // 拼多多
  const viewDrafts = document.getElementById('view-drafts');
  if (viewDrafts) {
    viewDrafts.scrollTop = 380;
  }
});
</script>
"""

test_html = html.replace('</body>', inject + '\n</body>')
snap_file = os.path.abspath('scratch/snap_page.html')
with open(snap_file, 'w', encoding='utf-8') as f:
    f.write(test_html)

artifact_dir = r'C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5'
snap_png = os.path.join(artifact_dir, 'snap_draft_time_input_scroll.png')

edge_exe = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
cmd = [edge_exe, '--headless', '--disable-gpu', '--window-size=430,932', '--screenshot=' + snap_png, 'file:///' + snap_file.replace('\\', '/')]
subprocess.run(cmd, capture_output=True)
print('SCROLLED SNAPSHOT DONE!')
