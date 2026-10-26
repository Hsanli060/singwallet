# BRIEFING — 2026-10-23T01:17:00Z

## Mission
SingWallet Milestone M2 核心业务 UI 与交互全量落地：构建生产级 Flutter Material 3 界面体系，实现 Riverpod 状态总线、流水明细看板、截图草稿箱 OCR 视觉证据高亮确认页、分类规则中心与账户项目管理，并实现配套 Widget 与 E2E 交互验证套件，保持全量测试 100% 通过与 flutter analyze 0 缺陷。

## 🔒 My Identity
- Archetype: teamwork_preview_orchestrator
- Roles: orchestrator, user_liaison, human_reporter, successor
- Working directory: c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_4
- Original parent: Sentinel
- Original parent conversation ID: d13fb168-f4d1-44dc-a4ae-4a90730a630b

## 🔒 My Workflow
- **Pattern**: Project Pattern (Dual Track: Implementation Track + E2E Testing Track)
- **Scope document**: c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_4\PROJECT.md
1. **Decompose**: Decompose M2 scope by module boundaries (R1: Presentation Providers & ViewModels; R2: Transactions Screen & Dashboard; R3: Draft Confirmation & OCR BoundingBox Overlay; R4: Rules & Accounts Configuration; R5: Widget Tests & E2E Verification).
2. **Dispatch & Execute**:
   - Survey full codebase and existing dependencies (flutter_riverpod, test dependencies, etc.) with parallel Explorers/Spec Miners.
   - Execute milestone cycles (Explorer -> Worker -> Reviewers -> Challengers -> Forensic Auditor -> Gate).
3. **On failure** (in this order):
   - Retry: nudge stuck agent or re-send task
   - Replace: spawn fresh agent with partial progress
   - Skip: proceed without (only if non-critical)
   - Redistribute: split stuck agent's remaining work
   - Redesign: re-partition decomposition
   - Escalate: report to parent (sub-orchestrators only, last resort)
4. **Succession**: At spawn count >= 16 and all current subagents complete, write handoff.md, cancel crons, spawn successor.
- **Work items**:
  1. Survey and Codebase Exploration [done]
  2. M2-1: Core Repositories, Database Seeder & Riverpod State Bus [in-progress]
  3. M2-2: Transactions Screen & Dashboard [pending]
  4. M2-3: Draft Confirmation Screen & OCR BoundingBox Overlay [pending]
  5. M2-4: Classification Rules & Accounts/Projects Config Center [pending]
  6. M2-5: Comprehensive Widget & E2E Test Suite [pending]
  7. Final Integration, Quality Gate & Victory Audit [pending]
- **Current phase**: 2 (Milestone M2-1 Execution)
- **Current focus**: Milestone M2-1: Core Repositories, Database Seeder & Riverpod State Bus

## 🔒 Key Constraints
- NEVER write, modify, or create source code files directly (DISPATCH-ONLY orchestrator).
- NEVER run build/test commands yourself — require workers to do so.
- NEVER investigate or explore the problem at the code level — dispatch Explorers for technical investigation.
- You MAY use file-editing tools ONLY for metadata/state files (.md) in your .agents/teamwork/ folder.
- If a Forensic Auditor reports INTEGRITY VIOLATION, the milestone FAILS UNCONDITIONALLY.
- Never reuse a subagent after it has delivered its handoff — always spawn fresh.
- Mandatory integrity warning in all Worker prompts.
- All implementations must be genuine, 0 issues on flutter analyze, 100% test pass on flutter test (297 existing + new UI widget tests).

## Current Parent
- Conversation ID: d13fb168-f4d1-44dc-a4ae-4a90730a630b
- Updated: 2026-10-23T01:27:00Z

## Key Decisions Made
- Adopt Project Pattern with Phase 0 Survey completed by spec_miner_m2_1, explorer_m2_1, explorer_m2_2.
- Decomposed M2 into 5 modular milestones: M2-1 (Repositories, Seeder, Riverpod State Bus), M2-2 (Transactions Dashboard), M2-3 (Draft Confirmation & OCR Overlay), M2-4 (Rules & Config Center), M2-5 (Widget Tests & E2E Validation).
- Strictly adhere to zero-cheating policy and require comprehensive Forensic Audits.
- Remediate Victory Audit failure: fix test/presentation/challenger_m2_stress_test.dart:687 where db.query was awaited in fakeAsync without tester.runAsync, verify all 368 tests pass with exit code 0.

## Team Roster
| Agent | Type | Work Item | Status | Conv ID |
|---|---|---|---|---|
| spec_miner_m2_1 | teamwork_preview_spec_miner | Phase 0 Requirements & UI Spec Mining | completed | f3a2fc07-ce52-4b56-a840-f6ff24ae8df8 |
| explorer_m2_1 | teamwork_preview_explorer | Phase 0 Data Layer & Engines Exploration | completed | 53d4d333-5562-45e1-835e-95fb74f9e3ba |
| explorer_m2_2 | teamwork_preview_explorer | Phase 0 UI Architecture & Test Exploration | completed | ea744fc3-0963-43a8-b3b7-eb4dbf7dd7e7 |
| worker_m2_1 | teamwork_preview_worker | M2-1 Repositories, Seeder & Riverpod State Bus | completed | 25d7181a-1553-4538-a5cf-95a3d48d2647 |
| worker_m2_2 | teamwork_preview_worker | M2-2 Transactions Screen & Dashboard | completed | b28c9473-32e5-4665-98fb-e89a2fbb995e |
| worker_m2_3 | teamwork_preview_worker | M2-3 Draft Confirmation & OCR Overlay | completed | 92e08a87-ed08-44b9-a624-db65f134f085 |
| worker_m2_4 | teamwork_preview_worker | M2-4 Rules & Accounts Config Center | completed | f11d93ff-db50-4f0a-a358-b16cc94ff1e7 |
| worker_m2_5 | teamwork_preview_worker | M2-5 Full Integration, Zero Lints & Global Tests | completed | cfcee868-8a85-4abe-ae68-5238d027895a |
| reviewer_m2_1 | teamwork_preview_reviewer | Gate Review: Code and Architecture | completed (APPROVE) | e8e7c908-cbe1-4035-8b86-c84d4806b5ca |
| reviewer_m2_2 | teamwork_preview_reviewer | Gate Review: UI and Interaction | completed (APPROVE) | 26fde8d3-2a7c-4425-964c-467d1b26f7d5 |
| challenger_m2_1 | teamwork_preview_challenger | Gate Challenge: UI & Dedup Stress | replaced | 34e5e930-2426-4e41-a17e-dcb1600a3850 |
| challenger_m2_2 | teamwork_preview_challenger | Gate Challenge: Rules & Cascade Stress | completed (APPROVE) | 08fe5783-e90d-418f-a249-cd898d43d84a |
| auditor_m2_1 | teamwork_preview_auditor | Forensic Integrity Audit | completed (CLEAN) | 2c7970ca-63b5-41f9-90ea-2966ebbce01f |
| challenger_m2_1_rep | teamwork_preview_challenger | Boundary & UI Stress Challenge | completed (APPROVE) | 91334bad-e9ea-4c44-b65d-417cc1da5614 |
| worker_m2_remediate | teamwork_preview_worker | Victory Audit Remediation (SQLite isolate deadlock fix) | completed (DONE) | a578bc10-b3f3-4ade-a418-3bf084b2ba1c |

## Succession Status
- Succession required: no
- Spawn count: 15 / 16
- Pending subagents: none
- Predecessor: none
- Successor: not yet spawned

## Active Timers
- Heartbeat cron: none
- Safety timer: none
- On succession: kill all timers before spawning successor
- On context truncation: run `manage_task(Action="list")` — re-create if missing

## Artifact Index
- .agents/teamwork/ORIGINAL_REQUEST.md — Authoritative User Request
- .agents/teamwork/orchestrator_4/DISPATCH.md — Parent Dispatch Instruction
- .agents/teamwork/orchestrator_4/BRIEFING.md — Persistent Working Memory
- .agents/teamwork/orchestrator_4/progress.md — Liveness Heartbeat & Step Checkpoint
- .agents/teamwork/orchestrator_4/PROJECT.md — M2 Scope & Milestone Architecture
