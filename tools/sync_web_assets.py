#!/usr/bin/env python3
"""
SingWallet Web Assets Sync Tool
--------------------------------
Automates single-source asset synchronization between web source files
(singwallet_preview.html & preview/) and the Android native host asset directory
(android/app/src/main/assets/).

Usage:
    python tools/sync_web_assets.py --check       # Verify consistency without writing
    python tools/sync_web_assets.py --dry-run     # Preview sync changes
    python tools/sync_web_assets.py               # Perform sync (root -> assets)
"""

import argparse
import hashlib
import os
import shutil
import sys
from pathlib import Path


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def file_sha256(file_path: Path) -> str:
    """Calculate SHA-256 hash of a file."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def collect_tree_files(base_dir: Path) -> dict:
    """Collect all files under base_dir as a dict mapping normalized relative path to Path."""
    tree = {}
    if not base_dir.exists():
        return tree
    for root, _, files in os.walk(base_dir):
        for f in files:
            full_path = Path(root) / f
            rel_path = full_path.relative_to(base_dir).as_posix()
            tree[rel_path] = full_path
    return tree


def run_check(src_root: Path, dst_root: Path) -> int:
    """Compare web source files with Android assets without making modifications."""
    print("=" * 60)
    print("SingWallet Web Assets Consistency Check")
    print(f"Source Root:   {src_root}")
    print(f"Target Assets: {dst_root}")
    print("=" * 60)

    differences_found = False

    # 1. Check singwallet_preview.html
    src_html = src_root / "singwallet_preview.html"
    dst_html = dst_root / "singwallet_preview.html"

    if not src_html.exists():
        print(f"[ERROR] Source HTML missing: {src_html}")
        differences_found = True
    elif not dst_html.exists():
        print(f"[MISSING] Target HTML missing: {dst_html}")
        differences_found = True
    else:
        src_hash = file_sha256(src_html)
        dst_hash = file_sha256(dst_html)
        if src_hash == dst_hash:
            print(" [MATCH] singwallet_preview.html")
        else:
            print(" [DIFF]  singwallet_preview.html (content differs)")
            differences_found = True

    # 2. Check preview/ directory
    src_preview_dir = src_root / "preview"
    dst_preview_dir = dst_root / "preview"

    src_files = collect_tree_files(src_preview_dir)
    dst_files = collect_tree_files(dst_preview_dir)

    all_keys = sorted(set(src_files.keys()) | set(dst_files.keys()))

    for key in all_keys:
        if key in src_files and key in dst_files:
            if file_sha256(src_files[key]) == file_sha256(dst_files[key]):
                print(f" [MATCH] preview/{key}")
            else:
                print(f" [DIFF]  preview/{key} (content differs)")
                differences_found = True
        elif key in src_files:
            print(f" [MISSING IN ASSETS] preview/{key}")
            differences_found = True
        else:
            print(f" [EXTRA IN ASSETS]   preview/{key}")
            differences_found = True

    print("=" * 60)
    if differences_found:
        print("[FAIL] Inconsistencies detected between web root and Android assets.")
        return 1
    else:
        print("[SUCCESS] All web preview assets are perfectly synchronized.")
        return 0


def run_sync(src_root: Path, dst_root: Path, dry_run: bool = False, clean: bool = True) -> int:
    """Synchronize root web files to android assets."""
    print("=" * 60)
    mode_str = "[DRY-RUN] " if dry_run else ""
    print(f"{mode_str}Synchronizing Single-Source Web Assets -> Android Host Assets")
    print(f"Source Root:   {src_root}")
    print(f"Target Assets: {dst_root}")
    print("=" * 60)

    # 1. Sync singwallet_preview.html
    src_html = src_root / "singwallet_preview.html"
    dst_html = dst_root / "singwallet_preview.html"

    if not src_html.exists():
        print(f"[ERROR] Source file not found: {src_html}")
        return 1

    dst_root.mkdir(parents=True, exist_ok=True)

    if not dst_html.exists() or file_sha256(src_html) != file_sha256(dst_html):
        print(f" -> Copying {src_html.name} -> {dst_html}")
        if not dry_run:
            shutil.copy2(src_html, dst_html)
    else:
        print(f" -> Up to date: {src_html.name}")

    # 2. Sync preview/ directory
    src_preview_dir = src_root / "preview"
    dst_preview_dir = dst_root / "preview"

    if not src_preview_dir.exists():
        print(f"[ERROR] Source directory not found: {src_preview_dir}")
        return 1

    src_files = collect_tree_files(src_preview_dir)
    dst_files = collect_tree_files(dst_preview_dir)

    # Copy / update
    for rel_path, src_path in src_files.items():
        dst_path = dst_preview_dir / rel_path
        if not dst_path.exists() or file_sha256(src_path) != file_sha256(dst_path):
            print(f" -> Updating preview/{rel_path}")
            if not dry_run:
                dst_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src_path, dst_path)
        else:
            print(f" -> Up to date: preview/{rel_path}")

    # Clean extra files in assets if clean=True
    if clean:
        for rel_path, dst_path in dst_files.items():
            if rel_path not in src_files:
                print(f" -> Removing stale asset: preview/{rel_path}")
                if not dry_run:
                    dst_path.unlink()
                    try:
                        dst_path.parent.rmdir()
                    except OSError:
                        pass

    print("=" * 60)
    print(f"[SUCCESS] {mode_str}Sync operation completed successfully.")
    return 0


def main():
    parser = argparse.ArgumentParser(description="SingWallet Web Assets Sync Tool")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check consistency between source web files and Android assets without modifying anything.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate the sync operation without writing any files.",
    )
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Do not delete stale files from target assets directory.",
    )

    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    src_root = repo_root
    dst_root = repo_root / "android" / "app" / "src" / "main" / "assets"

    if args.check:
        sys.exit(run_check(src_root, dst_root))
    else:
        sys.exit(run_sync(src_root, dst_root, dry_run=args.dry_run, clean=not args.no_clean))


if __name__ == "__main__":
    main()
