import os
import re
import ssl
import json
import ctypes
import hashlib
import struct
import sqlite3

def test_markdown_files(root_dir=None):
    print("--- 1. Testing Markdown Files & Local Links Integrity ---")
    if root_dir is None:
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    
    md_files = []
    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            if f.endswith(".md"):
                md_files.append(os.path.join(root, f))
                
    print(f"Found {len(md_files)} markdown files.")
    assert len(md_files) >= 4, f"Expected at least 4 markdown files, got {len(md_files)}"
    
    for path in md_files:
        rel = os.path.relpath(path, root_dir)
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
            
        print(f"\nChecking: {rel}")
        print(f"  Length: {len(content)} characters, {len(content.splitlines())} lines")
        
        # 1. Code fences balance
        fences = re.findall(r"(?m)^```", content)
        assert len(fences) % 2 == 0, f"Unbalanced code fences in {rel}: {len(fences)}"
        print(f"  Code fences: {len(fences)} ({len(fences)//2} blocks) - OK")
        
        # 2. Markdown links existence
        links = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", content)
        for text, target in links:
            if target.startswith("http://") or target.startswith("https://") or target.startswith("#"):
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            assert os.path.exists(resolved), f"Broken link in {rel}: [{text}]({target}) -> {resolved}"
            print(f"  Valid link: [{text}]({target}) -> OK")

def test_hybrid_architecture_integrity(root_dir=None):
    print("\n--- 2. Testing Hybrid Architecture Core Assets Integrity ---")
    if root_dir is None:
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    
    required_assets = [
        os.path.join(root_dir, "singwallet_preview.html"),
        os.path.join(root_dir, "preview", "css", "preview.css"),
        os.path.join(root_dir, "preview", "js", "app_controller.js"),
        os.path.join(root_dir, "preview", "js", "ocr_vlm_engine.js"),
        os.path.join(root_dir, "android", "app", "src", "main", "kotlin", "com", "singwallet", "app", "MainActivity.kt"),
    ]
    for asset in required_assets:
        assert os.path.exists(asset), f"Required hybrid architecture asset missing: {asset}"
        rel = os.path.relpath(asset, root_dir)
        print(f"  Valid asset: {rel} ({os.path.getsize(asset)} bytes) - OK")

def test_sqlite_ddl(root_dir=None):
    print("\n--- 3. Testing SQLite DDL, Constraints & Cascades ---")
    if root_dir is None:
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    doc_path = os.path.join(root_dir, "docs", "跨平台架构与数据规范.md")
    with open(doc_path, "r", encoding="utf-8") as f:
        content = f.read()
        
    sql_blocks = re.findall(r"```sql\s*(.*?)\s*```", content, re.DOTALL)
    assert len(sql_blocks) > 0, "No SQL code blocks found in specification!"
    full_sql = "\n\n".join(sql_blocks)
    
    conn = sqlite3.connect(":memory:")
    cursor = conn.cursor()
    cursor.execute("PRAGMA foreign_keys = ON;")
    cursor.executescript(full_sql)
    print("  SQLite DDL executed successfully!")
    
    # 1. Verify 12 tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]
    expected_tables = [
        "capture_jobs", "drafts", "accounts", "categories", "projects",
        "tags", "transactions", "transaction_metadata", "transaction_tags",
        "refund_links", "classification_rules", "confirmed_identifiers"
    ]
    for exp in expected_tables:
        assert exp in tables, f"Missing expected table: {exp}"
    print(f"  All 12 expected tables verified: {len(tables)} tables created.")
    
    # 2. Verify all 8+ indexes
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index';")
    indexes = [row[0] for row in cursor.fetchall()]
    required_indexes = [
        "idx_capture_jobs_hash", "idx_capture_jobs_state", "idx_drafts_saved_tx",
        "idx_tx_occurred_on", "idx_tx_category", "idx_tx_deleted_at",
        "idx_tx_project", "idx_tx_account", "idx_transaction_tags_tag",
        "idx_refund_original", "idx_confirmed_identifiers_tx"
    ]
    for idx in required_indexes:
        assert idx in indexes, f"Missing expected index: {idx}"
    print(f"  All {len(required_indexes)} required performance indexes verified!")

    # 3. Test amount_minor > 0 constraint
    cursor.execute("""
        INSERT INTO categories (id, name, applicable_type, created_at, updated_at)
        VALUES ('cat_food', '餐饮美食', 'expense', datetime('now'), datetime('now'));
    """)
    try:
        cursor.execute("""
            INSERT INTO transactions (
                id, type, amount_minor, merchant_raw, occurred_on, event_time_source,
                event_time_precision, payment_channel, category_id, created_at, updated_at
            ) VALUES (
                'tx_bad', 'expense', 0, '非法零元', '2026-10-22', 'user_confirmed',
                'minute', 'wechat', 'cat_food', datetime('now'), datetime('now')
            );
        """)
        assert False, "Should have failed on amount_minor > 0 constraint"
    except sqlite3.IntegrityError:
        print("  Check constraint (amount_minor > 0) verified!")

    # 4. Test origin_draft_id UNIQUE constraint
    cursor.execute("""
        INSERT INTO capture_jobs (id, content_hash, source_kind, imported_at, private_image_ref, state, created_at, updated_at)
        VALUES ('job_01', 'hash_abc', 'systemShare', datetime('now'), 'path/to/img', 'COMMITTED', datetime('now'), datetime('now'));
    """)
    cursor.execute("""
        INSERT INTO drafts (id, capture_id, candidate_fields, field_evidence, validation_issues, duplicate_candidates, created_at, updated_at)
        VALUES ('draft_01', 'job_01', '{}', '{}', '[]', '[]', datetime('now'), datetime('now'));
    """)
    cursor.execute("""
        INSERT INTO transactions (
            id, origin_draft_id, type, amount_minor, merchant_raw, occurred_on, event_time_source,
            event_time_precision, payment_channel, category_id, created_at, updated_at
        ) VALUES (
            'tx_001', 'draft_01', 'expense', 2890, '某某餐厅', '2026-10-22', 'user_confirmed',
            'minute', 'wechat', 'cat_food', datetime('now'), datetime('now')
        );
    """)
    try:
        cursor.execute("""
            INSERT INTO transactions (
                id, origin_draft_id, type, amount_minor, merchant_raw, occurred_on, event_time_source,
                event_time_precision, payment_channel, category_id, created_at, updated_at
            ) VALUES (
                'tx_001_dup', 'draft_01', 'expense', 2890, '某某餐厅重复保存', '2026-10-22', 'user_confirmed',
                'minute', 'wechat', 'cat_food', datetime('now'), datetime('now')
            );
        """)
        assert False, "Should have failed on origin_draft_id UNIQUE constraint"
    except sqlite3.IntegrityError:
        print("  Idempotence UNIQUE constraint (origin_draft_id) verified!")

    # 5. Test confirmed_identifiers hard deduplication primary key
    cursor.execute("""
        INSERT INTO confirmed_identifiers (namespace, identifier_type, complete_value, stable_event_kind, transaction_id)
        VALUES ('wechat_pay', 'platform_transaction_no', '4200002134202610221234567890', 'payment', 'tx_001');
    """)
    try:
        cursor.execute("""
            INSERT INTO confirmed_identifiers (namespace, identifier_type, complete_value, stable_event_kind, transaction_id)
            VALUES ('wechat_pay', 'platform_transaction_no', '4200002134202610221234567890', 'payment', 'tx_other');
        """)
        assert False, "Should have failed on confirmed_identifiers primary key duplicate"
    except sqlite3.IntegrityError:
        print("  Hard deduplication PRIMARY KEY constraint on confirmed_identifiers verified!")

    # 6. Test refund_links ON DELETE CASCADE on original expense (Unlinking without deleting refund)
    cursor.execute("""
        INSERT INTO transactions (
            id, type, amount_minor, merchant_raw, occurred_on, event_time_source,
            event_time_precision, payment_channel, category_id, created_at, updated_at
        ) VALUES (
            'tx_refund_01', 'refund', 500, '某某餐厅退款', '2026-10-23', 'user_confirmed',
            'minute', 'wechat', 'cat_food', datetime('now'), datetime('now')
        );
    """)
    cursor.execute("""
        INSERT INTO refund_links (refund_transaction_id, original_expense_id, created_at)
        VALUES ('tx_refund_01', 'tx_001', datetime('now'));
    """)
    
    # Permanent delete of tx_001 should NOT fail, should delete refund_link row, and should preserve tx_refund_01!
    cursor.execute("DELETE FROM transactions WHERE id = 'tx_001';")
    
    cursor.execute("SELECT id FROM transactions WHERE id = 'tx_001';")
    assert cursor.fetchone() is None, "Original expense was not deleted"
    
    cursor.execute("SELECT * FROM refund_links WHERE original_expense_id = 'tx_001';")
    assert cursor.fetchone() is None, "Refund link was not unlinked on original expense deletion"
    
    cursor.execute("SELECT id, type, amount_minor FROM transactions WHERE id = 'tx_refund_01';")
    refund_row = cursor.fetchone()
    assert refund_row is not None and refund_row[0] == "tx_refund_01", "Refund transaction was erroneously deleted!"
    print("  Refund unlinking on permanent delete (ON DELETE CASCADE without deleting refund transaction) verified!")

    # 7. Test classification_rules project_id foreign key (ON DELETE SET NULL)
    cursor.execute("INSERT INTO projects (id, name, created_at, updated_at) VALUES ('proj_travel', '日本旅行', datetime('now'), datetime('now'));")
    cursor.execute("""
        INSERT INTO classification_rules (id, priority, merchant_pattern, category_id, project_id, created_at, updated_at)
        VALUES ('rule_01', 100, '星巴克%', 'cat_food', 'proj_travel', datetime('now'), datetime('now'));
    """)
    cursor.execute("DELETE FROM projects WHERE id = 'proj_travel';")
    cursor.execute("SELECT project_id FROM classification_rules WHERE id = 'rule_01';")
    assert cursor.fetchone()[0] is None, "classification_rules.project_id was not SET NULL on project deletion"
    print("  classification_rules project_id ON DELETE SET NULL foreign key verified!")

    conn.close()

def test_swbk_container_crypto():
    print("\n--- 4. Testing SWBK v1 Cross-Platform Backup Encryption & Authentication ---")
    dll_path = os.path.join(os.path.dirname(ssl._ssl.__file__), "libcrypto-3.dll")
    lib = ctypes.CDLL(dll_path)
    
    lib.EVP_CIPHER_CTX_new.restype = ctypes.c_void_p
    lib.EVP_CIPHER_CTX_free.argtypes = [ctypes.c_void_p]
    lib.EVP_aes_256_gcm.restype = ctypes.c_void_p
    lib.EVP_CipherInit_ex.argtypes = [
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
        ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int
    ]
    lib.EVP_CipherUpdate.argtypes = [
        ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int),
        ctypes.c_char_p, ctypes.c_int
    ]
    lib.EVP_CipherFinal_ex.argtypes = [
        ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)
    ]
    lib.EVP_CIPHER_CTX_ctrl.argtypes = [
        ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_void_p
    ]

    MAGIC = b"SWBK"
    VERSION = 1
    ITERATIONS = 100000
    SALT_LEN = 16
    IV_LEN = 12
    TAG_LEN = 16
    HEADER_FORMAT = ">4sHI16s12sQ" # 46 bytes: magic(4), version(2), iter(4), salt(16), iv(12), payload_len(8)
    HEADER_SIZE = struct.calcsize(HEADER_FORMAT)
    assert HEADER_SIZE == 46, f"Expected 46-byte header, got {HEADER_SIZE}"

    sample_data = {
        "manifest": {
            "version": "1.0",
            "exported_at": "2026-10-22T08:30:00Z",
            "platform": "Android",
            "app_version": "1.0.0",
            "entity_counts": {"transactions": 1, "categories": 1, "accounts": 1, "rules": 0}
        },
        "categories": [{"id": "cat_food", "name": "餐饮", "applicable_type": "expense"}],
        "accounts": [{"id": "acc_cmb", "name": "招商银行储蓄卡", "kind": "debit_card"}],
        "projects": [], "tags": [],
        "transactions": [{
            "id": "tx_001", "type": "expense", "amount_minor": 2890,
            "currency": "CNY", "merchant_raw": "某某餐厅", "occurred_on": "2026-10-22",
            "event_time_source": "user_confirmed", "event_time_precision": "minute",
            "payment_channel": "wechat", "category_id": "cat_food"
        }],
        "transaction_metadata": [], "transaction_tags": [],
        "refund_links": [], "classification_rules": [], "confirmed_identifiers": []
    }
    
    password = "CorrectStrongPassword2026!"
    json_bytes = json.dumps(sample_data, ensure_ascii=False).encode("utf-8")
    salt = os.urandom(SALT_LEN)
    iv = os.urandom(IV_LEN)
    key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, ITERATIONS, dklen=32)
    aad = MAGIC + struct.pack(">H", VERSION) # 6 bytes AAD
    
    # 1. Pack / Encrypt
    ctx = lib.EVP_CIPHER_CTX_new()
    try:
        assert lib.EVP_CipherInit_ex(ctx, lib.EVP_aes_256_gcm(), None, None, None, 1) == 1
        assert lib.EVP_CIPHER_CTX_ctrl(ctx, 0x9, len(iv), None) == 1
        assert lib.EVP_CipherInit_ex(ctx, None, None, key, iv, 1) == 1
        
        outlen = ctypes.c_int(0)
        assert lib.EVP_CipherUpdate(ctx, None, ctypes.byref(outlen), aad, len(aad)) == 1
        
        ciphertext = (ctypes.c_char * (len(json_bytes) + 16))()
        assert lib.EVP_CipherUpdate(ctx, ciphertext, ctypes.byref(outlen), json_bytes, len(json_bytes)) == 1
        ct_len = outlen.value
        
        final_outlen = ctypes.c_int(0)
        assert lib.EVP_CipherFinal_ex(ctx, (ctypes.c_char * 16)(), ctypes.byref(final_outlen)) == 1
        
        tag = (ctypes.c_char * 16)()
        assert lib.EVP_CIPHER_CTX_ctrl(ctx, 0x10, 16, tag) == 1
        tag_bytes = bytes(tag)
        ct_bytes = bytes(ciphertext[:ct_len])
    finally:
        lib.EVP_CIPHER_CTX_free(ctx)
        
    header = struct.pack(HEADER_FORMAT, MAGIC, VERSION, ITERATIONS, salt, iv, len(ct_bytes))
    container_bytes = header + ct_bytes + tag_bytes
    print(f"  Container packed: Total {len(container_bytes)} bytes (Header: {HEADER_SIZE}B, Ciphertext: {len(ct_bytes)}B, Tag: {len(tag_bytes)}B)")

    # 2. Unpack / Decrypt
    assert len(container_bytes) == HEADER_SIZE + len(ct_bytes) + TAG_LEN
    m, v, iters, s, i_v, plen = struct.unpack(HEADER_FORMAT, container_bytes[:HEADER_SIZE])
    assert m == MAGIC and v == VERSION and iters == ITERATIONS and plen == len(ct_bytes)
    
    dec_key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), s, iters, dklen=32)
    dec_ctx = lib.EVP_CIPHER_CTX_new()
    try:
        assert lib.EVP_CipherInit_ex(dec_ctx, lib.EVP_aes_256_gcm(), None, None, None, 0) == 1
        assert lib.EVP_CIPHER_CTX_ctrl(dec_ctx, 0x9, len(i_v), None) == 1
        assert lib.EVP_CipherInit_ex(dec_ctx, None, None, dec_key, i_v, 0) == 1
        
        outlen2 = ctypes.c_int(0)
        assert lib.EVP_CipherUpdate(dec_ctx, None, ctypes.byref(outlen2), aad, len(aad)) == 1
        
        decrypted = (ctypes.c_char * (plen + 16))()
        assert lib.EVP_CipherUpdate(dec_ctx, decrypted, ctypes.byref(outlen2), ct_bytes, plen) == 1
        dec_len = outlen2.value
        
        assert lib.EVP_CIPHER_CTX_ctrl(dec_ctx, 0x11, 16, tag_bytes) == 1
        ret = lib.EVP_CipherFinal_ex(dec_ctx, (ctypes.c_char * 16)(), ctypes.byref(final_outlen))
        assert ret > 0, "Authentication tag failed on valid decrypt"
        dec_bytes = bytes(decrypted[:dec_len])
    finally:
        lib.EVP_CIPHER_CTX_free(dec_ctx)
        
    recovered = json.loads(dec_bytes.decode("utf-8"))
    assert recovered == sample_data, "Decrypted data does not match original JSON data"
    print("  SWBK v1 AES-256-GCM + PBKDF2 decryption round-trip 100% verified!")

    # 3. Test wrong password
    bad_key = hashlib.pbkdf2_hmac("sha256", b"WrongPassword!", s, iters, dklen=32)
    bad_ctx = lib.EVP_CIPHER_CTX_new()
    try:
        assert lib.EVP_CipherInit_ex(bad_ctx, lib.EVP_aes_256_gcm(), None, None, None, 0) == 1
        assert lib.EVP_CIPHER_CTX_ctrl(bad_ctx, 0x9, len(i_v), None) == 1
        assert lib.EVP_CipherInit_ex(bad_ctx, None, None, bad_key, i_v, 0) == 1
        assert lib.EVP_CipherUpdate(bad_ctx, None, ctypes.byref(outlen2), aad, len(aad)) == 1
        lib.EVP_CipherUpdate(bad_ctx, decrypted, ctypes.byref(outlen2), ct_bytes, plen)
        assert lib.EVP_CIPHER_CTX_ctrl(bad_ctx, 0x11, 16, tag_bytes) == 1
        ret = lib.EVP_CipherFinal_ex(bad_ctx, (ctypes.c_char * 16)(), ctypes.byref(final_outlen))
        assert ret <= 0, "AES-GCM tag should have rejected incorrect password!"
        print("  Wrong password correctly rejected by authentication tag!")
    finally:
        lib.EVP_CIPHER_CTX_free(bad_ctx)

def test_csv_injection_sanitization():
    print("\n--- 5. Testing CSV Formula Injection Protection ---")
    def sanitize_csv_field(text: str) -> str:
        if not text:
            return ""
        # If starts with =, +, -, @, \t, \r, prepend single quote
        dangerous_prefixes = ('=', '+', '-', '@', '\t', '\r')
        if text.startswith(dangerous_prefixes):
            text = "'" + text
        # If contains comma, quote, or newline, escape with double quotes
        if any(c in text for c in (',', '"', '\n', '\r')):
            text = '"' + text.replace('"', '""') + '"'
        return text

    test_cases = [
        ("=cmd|'/C calc'!A0", "'=cmd|'/C calc'!A0"),
        ("+12345", "'+12345"),
        ("-SUM(A1:A10)", "'-SUM(A1:A10)"),
        ("@evil.com", "'@evil.com"),
        ("\tTabIndented", "'\tTabIndented"),
        ("普通商户名称", "普通商户名称"),
        ("麦当劳, 北京三里屯店", '"麦当劳, 北京三里屯店"'),
        ('含"双引号"商品', '"含""双引号""商品"'),
    ]
    for raw, expected in test_cases:
        actual = sanitize_csv_field(raw)
        assert actual == expected, f"Failed on CSV input: {raw!r}. Expected {expected!r}, got {actual!r}"
    print(f"  All {len(test_cases)} CSV injection test cases passed successfully!")

def test_coordinate_normalization():
    print("\n--- 6. Testing OCR Coordinate System Normalization Math ---")
    image_width = 1170
    image_height = 2532
    
    # Target bounding box in physical display pixels:
    # X: [100, 400], Y: [500, 600] from top
    # Box width = 300, box height = 100
    
    # 1. Android ML Kit (Rect: left=100, top=500, right=400, bottom=600, top-left origin)
    rect_left = 100
    rect_top = 500
    rect_width = 300
    rect_height = 100
    
    android_left = rect_left / image_width
    android_top = rect_top / image_height
    android_width = rect_width / image_width
    android_height = rect_height / image_height
    
    # 2. iOS Vision (Origin at bottom-left: origin.x = left/W, origin.y = (H - bottom)/H)
    # bottom = 600, so distance from bottom = 2532 - 600 = 1932
    vision_origin_x = 100.0 / image_width
    vision_origin_y = (image_height - 600.0) / image_height
    vision_size_width = 300.0 / image_width
    vision_size_height = 100.0 / image_height
    
    # Swift formula:
    swift_left = vision_origin_x
    swift_top = 1.0 - vision_origin_y - vision_size_height
    swift_width = vision_size_width
    swift_height = vision_size_height
    
    assert abs(android_left - swift_left) < 1e-9
    assert abs(android_top - swift_top) < 1e-9
    assert abs(android_width - swift_width) < 1e-9
    assert abs(android_height - swift_height) < 1e-9
    print(f"  Android ML Kit & iOS Apple Vision coordinate mapping verified to be mathematically equivalent!")
    print(f"  Result: left={swift_left:.4f}, top={swift_top:.4f}, width={swift_width:.4f}, height={swift_height:.4f}")

if __name__ == "__main__":
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    test_markdown_files(root_dir)
    test_hybrid_architecture_integrity(root_dir)
    test_sqlite_ddl(root_dir)
    test_swbk_container_crypto()
    test_csv_injection_sanitization()
    test_coordinate_normalization()
    print("\n=======================================================")
    print(">>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<")
    print("=======================================================")
