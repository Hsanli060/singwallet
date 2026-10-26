import sqlite3
import re

# Read schema.dart directly
with open(r"c:\Other\Projects\singwallet\lib\data\database\schema.dart", "r", encoding="utf-8") as f:
    schema_code = f.read()

# Extract DDL statements
tables_match = re.search(r"static const List<String> createTablesStatements = \[(.*?)\];", schema_code, re.DOTALL)
indices_match = re.search(r"static const List<String> createIndicesStatements = \[(.*?)\];", schema_code, re.DOTALL)

assert tables_match, "Failed to extract createTablesStatements"
assert indices_match, "Failed to extract createIndicesStatements"

# Extract SQL string literals
table_sqls = re.findall(r"'''(.*?)'''", tables_match.group(1), re.DOTALL)
index_sqls = re.findall(r"'(.*?)'", indices_match.group(1))

print(f"Extracted {len(table_sqls)} table statements and {len(index_sqls)} index statements from schema.dart.")

conn = sqlite3.connect(":memory:")
cursor = conn.cursor()
cursor.execute("PRAGMA foreign_keys = ON;")

for sql in table_sqls:
    cursor.execute(sql)

for sql in index_sqls:
    cursor.execute(sql)

# 1. Verify 12 tables
cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = [row[0] for row in cursor.fetchall()]
expected_tables = [
    "capture_jobs", "drafts", "accounts", "categories", "projects",
    "tags", "transactions", "transaction_metadata", "transaction_tags",
    "refund_links", "classification_rules", "confirmed_identifiers"
]
for t in expected_tables:
    assert t in tables, f"Missing table: {t}"
print(f"PASS: All 12 tables verified in schema.dart: {len(tables)} tables created.")

# 2. Verify 11 indexes
cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';")
indexes = [row[0] for row in cursor.fetchall()]
expected_indexes = [
    'idx_capture_jobs_hash', 'idx_capture_jobs_state', 'idx_drafts_saved_tx',
    'idx_tx_occurred_on', 'idx_tx_category', 'idx_tx_deleted_at',
    'idx_tx_project', 'idx_tx_account', 'idx_transaction_tags_tag',
    'idx_refund_original', 'idx_confirmed_identifiers_tx'
]
for idx in expected_indexes:
    assert idx in indexes, f"Missing index: {idx}"
print(f"PASS: All 11 indexes verified in schema.dart: {len(indexes)} indexes created.")

# 3. Test amount_minor > 0
cursor.execute("INSERT INTO categories (id, name, applicable_type, created_at, updated_at) VALUES ('c1', '餐饮', 'expense', 'now', 'now');")
try:
    cursor.execute("""
        INSERT INTO transactions (id, type, amount_minor, merchant_raw, occurred_on, event_time_source, event_time_precision, payment_channel, category_id, created_at, updated_at)
        VALUES ('tx_bad', 'expense', 0, 'zero', '2026-10-22', 'user_confirmed', 'minute', 'wechat', 'c1', 'now', 'now');
    """)
    assert False, "CHECK (amount_minor > 0) failed to reject 0"
except sqlite3.IntegrityError:
    print("PASS: CHECK (amount_minor > 0) rejected 0.")

try:
    cursor.execute("""
        INSERT INTO transactions (id, type, amount_minor, merchant_raw, occurred_on, event_time_source, event_time_precision, payment_channel, category_id, created_at, updated_at)
        VALUES ('tx_neg', 'expense', -50, 'neg', '2026-10-22', 'user_confirmed', 'minute', 'wechat', 'c1', 'now', 'now');
    """)
    assert False, "CHECK (amount_minor > 0) failed to reject negative amount"
except sqlite3.IntegrityError:
    print("PASS: CHECK (amount_minor > 0) rejected negative amount.")

# 4. Test transactions.category_id ON DELETE RESTRICT
cursor.execute("""
    INSERT INTO transactions (id, type, amount_minor, merchant_raw, occurred_on, event_time_source, event_time_precision, payment_channel, category_id, created_at, updated_at)
    VALUES ('tx1', 'expense', 1000, 'merch', '2026-10-22', 'user_confirmed', 'minute', 'wechat', 'c1', 'now', 'now');
""")
try:
    cursor.execute("DELETE FROM categories WHERE id = 'c1';")
    assert False, "FOREIGN KEY ON DELETE RESTRICT failed to prevent category deletion"
except sqlite3.IntegrityError:
    print("PASS: Category deletion blocked by ON DELETE RESTRICT foreign key constraint.")

# 5. Test refund_links ON DELETE CASCADE on original_expense_id
cursor.execute("""
    INSERT INTO transactions (id, type, amount_minor, merchant_raw, occurred_on, event_time_source, event_time_precision, payment_channel, category_id, created_at, updated_at)
    VALUES ('tx_ref', 'refund', 200, 'merch', '2026-10-23', 'user_confirmed', 'minute', 'wechat', 'c1', 'now', 'now');
""")
cursor.execute("INSERT INTO refund_links (refund_transaction_id, original_expense_id, created_at) VALUES ('tx_ref', 'tx1', 'now');")
# Delete tx1 (original expense)
cursor.execute("DELETE FROM transactions WHERE id = 'tx1';")
cursor.execute("SELECT * FROM refund_links WHERE original_expense_id = 'tx1';")
assert cursor.fetchone() is None, "refund_links row was not cascaded"
cursor.execute("SELECT id FROM transactions WHERE id = 'tx_ref';")
assert cursor.fetchone() is not None, "tx_ref was mistakenly deleted"
print("PASS: refund_links ON DELETE CASCADE unlinked refund without deleting refund transaction.")

# 6. Test categories parent_id ON DELETE SET NULL
cursor.execute("INSERT INTO categories (id, name, applicable_type, created_at, updated_at) VALUES ('c_parent', '父分类', 'expense', 'now', 'now');")
cursor.execute("INSERT INTO categories (id, name, parent_id, applicable_type, created_at, updated_at) VALUES ('c_child', '子分类', 'c_parent', 'expense', 'now', 'now');")
cursor.execute("DELETE FROM categories WHERE id = 'c_parent';")
cursor.execute("SELECT parent_id FROM categories WHERE id = 'c_child';")
row = cursor.fetchone()
assert row[0] is None, "parent_id was not set to NULL"
print("PASS: categories parent_id ON DELETE SET NULL verified.")

# 7. Test origin_draft_id UNIQUE constraint
cursor.execute("INSERT INTO capture_jobs (id, content_hash, source_kind, imported_at, private_image_ref, state, created_at, updated_at) VALUES ('j1', 'h1', 'systemShare', 'now', 'p1', 'COMMITTED', 'now', 'now');")
cursor.execute("INSERT INTO drafts (id, capture_id, candidate_fields, field_evidence, validation_issues, duplicate_candidates, created_at, updated_at) VALUES ('d1', 'j1', '{}', '{}', '[]', '[]', 'now', 'now');")
cursor.execute("""
    INSERT INTO transactions (id, origin_draft_id, type, amount_minor, merchant_raw, occurred_on, event_time_source, event_time_precision, payment_channel, category_id, created_at, updated_at)
    VALUES ('tx_a', 'd1', 'expense', 100, 'merch', '2026-10-22', 'user_confirmed', 'minute', 'wechat', 'c_child', 'now', 'now');
""")
try:
    cursor.execute("""
        INSERT INTO transactions (id, origin_draft_id, type, amount_minor, merchant_raw, occurred_on, event_time_source, event_time_precision, payment_channel, category_id, created_at, updated_at)
        VALUES ('tx_b', 'd1', 'expense', 100, 'merch', '2026-10-22', 'user_confirmed', 'minute', 'wechat', 'c_child', 'now', 'now');
    """)
    assert False, "origin_draft_id UNIQUE constraint failed"
except sqlite3.IntegrityError:
    print("PASS: origin_draft_id UNIQUE constraint verified.")

# 8. Test confirmed_identifiers compound PK
cursor.execute("""
    INSERT INTO confirmed_identifiers (namespace, identifier_type, complete_value, stable_event_kind, transaction_id)
    VALUES ('wechat_pay', 'platform_transaction_no', '4200000001', 'payment', 'tx_a');
""")
try:
    cursor.execute("""
        INSERT INTO confirmed_identifiers (namespace, identifier_type, complete_value, stable_event_kind, transaction_id)
        VALUES ('wechat_pay', 'platform_transaction_no', '4200000001', 'payment', 'tx_b');
    """)
    assert False, "confirmed_identifiers compound PK duplicate failed"
except sqlite3.IntegrityError:
    print("PASS: confirmed_identifiers compound PK hard deduplication verified.")

print("\nALL INDEPENDENT SQLITE VERIFICATION CHECKS PASSED 100%!")
