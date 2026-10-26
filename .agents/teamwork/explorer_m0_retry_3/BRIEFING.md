# BRIEFING — 2026-10-22T10:00:35Z

## Mission
Investigate and propose concrete fix strategy for:
1. Safe optional binding of `FlutterViewController` in `ios/Runner/AppDelegate.swift`.
2. Strengthening `CurrencyUtils.parseToMinorUnits` for malformed inputs like "12." or ".50".

## 🔒 My Identity
- Archetype: explorer
- Roles: investigator, analyzer
- Working directory: c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_3
- Original parent: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Milestone: m0_retry_3

## 🔒 Key Constraints
- Read-only investigation — do NOT implement source changes directly
- Document concrete fix strategies and code proposals (snippets / diffs) in report and handoff
- Follow Handoff Protocol (5 components)

## Current Parent
- Conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Updated: 2026-10-22T10:00:35Z

## Investigation State
- **Explored paths**:
  - `ios/Runner/AppDelegate.swift`
  - `ios/Runner/Plugins/NativeCaptureHostApiImpl.swift`
  - `ios/Runner/Plugins/NativeBridge.g.swift`
  - `lib/core/utils/currency_utils.dart`
  - `test/core/native/` test suite
  - `reviewer_m0_2/handoff.md` & `report.md`
  - `reviewer_m0_1/review.md`
- **Key findings**:
  - `AppDelegate.swift:10`: Unchecked force-cast (`as! FlutterViewController`) before `super.application(...)` crashes on background wake or uninitialized window hierarchy. Naive guard drops bridge registration. Solution: Call `super.application` first, resolve controller defensively via `resolveFlutterViewController()`, setup bridge idempotently, and provide fallback in `applicationDidBecomeActive`.
  - `currency_utils.dart:48`: Trailing decimal `"12."` yields `centPart = ""` which triggers `centPart.substring(0, 2)` -> uncaught `RangeError`. Leading decimal `".50"` yields `parts[0] = ""` which fails `int.tryParse` -> `FormatException`. Solution: Implement canonical `parseToMinorUnits` handling empty integer part (as 0), empty decimal part (as 0), currency symbols, thousand separators, and alias `yuanStringToCents`.
- **Unexplored areas**: None within scope. Complete replacement implementations and test specifications provided.

## Key Decisions Made
- Provided complete replacement code for `AppDelegate.swift` and `currency_utils.dart`.
- Designed comprehensive test suite `test/core/utils/currency_utils_test.dart` with 11 test groups and 30+ assertions.

## Artifact Index
- DISPATCH.md — Initial dispatch message
- progress.md — Liveness heartbeat and milestone tracker
- BRIEFING.md — Persistent situational awareness
- report.md — Comprehensive investigation and solution design report
- handoff.md — 5-component self-contained handoff report
