# Dispatch for spec_miner_m2_1
Target: Probe M2 authoritative requirements and UI specifications.
Report: .agents/teamwork/spec_miner_m2_1/report.md

## 2026-10-23T01:18:18Z
Your working directory is c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_m2_1.
You are spec_miner_m2_1, a teamwork_preview_spec_miner.
Read the authoritative request at: c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md (specifically see section ## 2026-10-23T01:15:17Z for Milestone M2).
Also consult design documents in c:\Other\Projects\singwallet\docs\ (e.g. 跨平台架构与数据规范.md, Android实现方案.md, iOS实现方案.md).

Task: Extract and document every UI specification, user flow, component requirement, and interaction rule for Milestone M2:
1. R1: Riverpod state architecture, Providers, Notifiers, ViewModels, dependency injection of existing database & engines.
2. R2: Transactions Screen & Dashboard (monthly summary stats, daily aggregated groups, transaction item components, filter bottom sheet/drawer, soft delete / undo / purge recycling bin).
3. R3: Draft Confirmation Screen & OCR BoundingBox Overlay (normalized coordinates [0.0, 1.0] mapping to image viewport without distortion, tap to backfill merchant/amount, smart form, 4-tier deduplication alerts: Tier 3 blocking, Tier 4 24h heuristic duplicate dialog, one-click commit IDENTIFIED -> CONFIRMED).
4. R4: Rules & Accounts Configuration Center (6-tier classification rules list with drag-and-drop or priority adjustment, enable/disable toggle, re-match triggers; account list & balances; project list; refund link picker dialog respecting refund_links ON DELETE CASCADE).
5. R5: Widget testing & E2E verification requirements.

Write your structured findings to c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_m2_1\report.md and write a complete handoff.md in your working directory. Send a message to parent when done.
