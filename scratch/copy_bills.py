import shutil
import os

brain_dir = r"C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5"
workspace_dir = r"c:\Other\Projects\singwallet"
assets_dir = os.path.join(workspace_dir, "assets", "user_bills")
os.makedirs(assets_dir, exist_ok=True)

src_images = [
    r"C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852462_4f8ed2f2.jpg",
    r"C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852463_ce555f09.jpg",
    r"C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852465_c5e54fb3.jpg",
    r"C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852466_7ec82ee1.jpg"
]

for idx, src in enumerate(src_images):
    name = f"bill_{idx+1}.jpg"
    dest_brain = os.path.join(brain_dir, name)
    dest_ws = os.path.join(assets_dir, name)
    shutil.copyfile(src, dest_brain)
    shutil.copyfile(src, dest_ws)
    print(f"Copied {name} -> brain & workspace")

print("All bill images copied successfully!")
