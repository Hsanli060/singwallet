## 2026-10-22T09:09:06Z
You are spec_miner_survey_3.
Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_3
Your parent is orchestrator_1 (conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c).

Mission:
Map and extract all specifications, algorithms, pipelines, and acceptance test requirements for:
R3. 交易识别解析与分类规则引擎（M1）
R4. 自动化测试套件与持续验证（M1）

Inputs to inspect thoroughly:
- c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md (MANDATORY: read this first!)
- c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md
- c:\Other\Projects\singwallet\docs\Android实现方案.md
- c:\Other\Projects\singwallet\docs\iOS实现方案.md
- c:\Other\Projects\singwallet\test_docs_integrity.py

Key Investigation Points:
1. OCR transaction parsing pipeline: stages, text normalization, amount extraction & regex patterns, order number extraction & deduplication, merchant name extraction & cleaning.
2. Classification rule engine: rule structure, matching algorithms, priority scoring, fallback category, regex / keyword matching logic.
3. Automated test requirements: DDL & cascade verification, Pigeon codec verification, amount precision tests, 4-tier anti-duplicate tests, state machine transition tests, OCR parsing & classification engine tests.
4. What test runner / environment is appropriate in Flutter/Dart (e.g. `flutter test`, `sqflite_common_ffi` for desktop SQLite testing)?
5. How `test_docs_integrity.py` works and what acceptance criteria are checked.

Output:
Write your full analysis report to:
c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_3\report.md
Also write handoff.md in your working directory.
When completed, send a message to orchestrator_1 (0be8f589-cb64-4c3b-aed0-2d1a129de39c) notifying completion with your report path.
