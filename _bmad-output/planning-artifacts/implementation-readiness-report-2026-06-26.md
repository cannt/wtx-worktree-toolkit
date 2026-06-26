---
stepsCompleted: [step-01, step-02, step-03, step-04, step-05, step-06]
project: wtx
feature: wtx interactive installer (wtx install)
date: 2026-06-26
inputDocuments:
  - _bmad-output/specs/spec-wtx-install/SPEC.md
  - _bmad-output/specs/spec-wtx-install/ux-flow.md
  - _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/epics.md
---

# Implementation Readiness Assessment Report

**Date:** 2026-06-26
**Project:** wtx — interactive installer feature (`wtx install`)
**Assessor:** bmad-check-implementation-readiness

---

## Document Inventory

| Type | File | Lines | Status |
|------|------|-------|--------|
| Spec / Requirements | `_bmad-output/specs/spec-wtx-install/SPEC.md` | 80 | ✅ Present |
| UX Flow | `_bmad-output/specs/spec-wtx-install/ux-flow.md` | 398 | ✅ Present |
| Architecture | `_bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md` | 262 | ✅ Present |
| Epics & Stories | `_bmad-output/planning-artifacts/epics.md` | 430 | ✅ Present |

No PRD exists separately; SPEC.md serves as the requirements baseline. No duplicates. All four artifact types present.

---

## PRD / Spec Analysis

### Capabilities (CAP)

7 capabilities defined in SPEC.md: CAP-1 (guided wizard), CAP-2 (reference templating), CAP-3 (hooks setup), CAP-4 (extras menu), CAP-5 (idempotency), CAP-6 (dry-run), CAP-7 (completion summary).

### Functional Requirements (FR)

25 FRs extracted from epics.md Requirements Inventory:

| FR | Subject | Source |
|----|---------|--------|
| FR1 | `wtx install` invocable end-to-end without errors | CAP-1 |
| FR2 | gum/bash-fallback, completes in both modes | CAP-1 |
| FR3 | Step 0 preflight exact sequence | AD-12 |
| FR4 | Step 1 welcome banner | CAP-1, ux-flow Step 1 |
| FR5 | Step 2 binary install: PATH check + delegation | CAP-1, AD-3, ux-flow Step 2 |
| FR6 | Step 3 forge type, org, optional base URL | CAP-2, ux-flow Step 3 |
| FR7 | Step 4 project directories | CAP-2, ux-flow Step 4 |
| FR8 | Step 5 detection markers: presets + Custom | CAP-2, ux-flow Step 5 |
| FR9 | Step 6 branch defaults | CAP-2, ux-flow Step 6 |
| FR10 | Step 7 Jira key iterative loop | CAP-2, ux-flow Step 7 |
| FR11 | Step 8 plugin discovery via AD-8 | CAP-2, AD-8, ux-flow Step 8 |
| FR12 | No placeholder value in written wtx.toml | CAP-2, AD-9 |
| FR13 | Atomic TOML write: mktemp + mv + trap | CAP-2, AD-4 |
| FR14 | Step 9 hooks: describe + confirm + install.sh --hooks | CAP-3, AD-3, ux-flow Step 9 |
| FR15 | Step 10 Gradle + PATH hint extras | CAP-4, AD-3, ux-flow Step 10 |
| FR16 | PATH hint gate: suppress when already on PATH | CAP-4, AD-11 |
| FR17 | Idempotency: skip/overwrite/merge gate | CAP-5, AD-13 |
| FR18 | Merge pre-fill via wtx_config_get | CAP-5, AD-6 |
| FR19 | `--dry-run` prints [dry-run] prefix, no FS changes | CAP-6, AD-5 |
| FR20 | Single `wtx_install_write_or_dryrun` chokepoint | CAP-6, AD-5 |
| FR21 | Step 11 ledger-driven [✓]/[-]/[!] summary + wtx doctor | CAP-7, AD-7 |
| FR22 | Ledger as parallel indexed arrays (bash 3.2 safe) | CAP-7, AD-7 |
| FR23 | `bin/wtx` routes install via `_wtx_exec_script` | AD-1 |
| FR24 | `lib/wtx-install.sh` single home for all primitives | AD-2 |
| FR25 | All wizard prompts via `tui_*` functions | AD-10 |

**Total FRs: 25**

### Non-Functional Requirements (NFR)

12 NFRs extracted: NFR1 (bash 3.2), NFR2 (set -u only), NFR3 (no hardcodes), NFR4 (pure-bash fallback), NFR5 (no eval), NFR6 (path relative to WTX_ROOT/WORKSPACE_ROOT), NFR7 (config reads via wtx_config_get), NFR8 (optional tool graceful degradation), NFR9 (quoted paths), NFR10 (errors to stderr), NFR11 (existing libs unchanged), NFR12 (wtx doctor exits 0 post-install).

### UX Design Requirements (UX-DR)

15 UX-DRs extracted, mapping to wizard steps 0–11 plus dry-run visual and step ordering:

| UX-DR | Wizard Step | Subject |
|-------|-------------|---------|
| UX-DR1 | Step 0 | Silent preflight; gum-absent notice |
| UX-DR2 | Step 1 | Welcome banner gum/fallback |
| UX-DR3 | Step 2 | Binary install prompt |
| UX-DR4 | Step 3 | Forge type/org/base URL |
| UX-DR5 | Step 4 | Project dirs input |
| UX-DR6 | Step 5 | Detection markers preset |
| UX-DR7 | Step 6 | Branch defaults |
| UX-DR8 | Step 7 | Jira key loop |
| UX-DR9 | Step 8 | Setup hook selection |
| UX-DR10 | Step 9 | Hooks confirm box |
| UX-DR11 | Step 10a | Gradle extra confirm |
| UX-DR12 | Step 10b | PATH hint gate |
| UX-DR13 | Step 11 | Completion summary |
| UX-DR14 | all write steps | Dry-run visual lines |
| UX-DR15 | full wizard | Step ordering contract |

### Architectural Decisions (AD)

13 ADs defined in ARCHITECTURE-SPINE.md: AD-1 (dispatcher routing), AD-2 (file layout/lib), AD-3 (delegation to install.sh), AD-4 (atomic TOML write), AD-5 (dry-run flag propagation), AD-6 (merge pre-fill), AD-7 (summary ledger), AD-8 (plugin discovery), AD-9 (no schema extension), AD-10 (TUI consistency), AD-11 (PATH hint gate), AD-12 (preflight sequence), AD-13 (idempotency gate placement).

---

## CAP Coverage Analysis

| Capability | Covered by Stories | ACs reference it? |
|------------|-------------------|-------------------|
| CAP-1 | 1.1, 1.2 | ✅ Yes (FR1–FR5, FR25) |
| CAP-2 | 1.1, 1.2 | ✅ Yes (FR6–FR13, FR24) |
| CAP-3 | 1.3 | ✅ Yes (FR14) |
| CAP-4 | 1.4 | ✅ Yes (FR15, FR16) |
| CAP-5 | 1.5 | ✅ Yes (FR17, FR18) |
| CAP-6 | 1.1, 1.6 | ✅ Yes (FR19, FR20) |
| CAP-7 | 1.7 | ✅ Yes (FR21, FR22) |

**Coverage: 7/7 CAPs — COMPLETE ✅**

---

## AD Coverage Analysis

| AD | Description | Covered by | Story ACs |
|----|-------------|------------|-----------|
| AD-1 | Dispatcher routing | FR23 | Story 1.1 ✅ |
| AD-2 | File layout / lib | FR24 | Story 1.1 ✅ |
| AD-3 | Delegation to install.sh | FR5, FR14, FR15 | Stories 1.2, 1.3, 1.4 ✅ |
| AD-4 | Atomic TOML write | FR13 | Story 1.1 primitive + 1.2 consumer ✅ |
| AD-5 | Dry-run flag propagation | FR20 | Story 1.1 primitive; 1.3, 1.4, 1.6 ✅ |
| AD-6 | Merge pre-fill | FR18 | Story 1.5 ✅ |
| AD-7 | Summary ledger | FR21, FR22 | Story 1.7 ✅ |
| AD-8 | Plugin discovery | FR11 | Story 1.2 ✅ |
| AD-9 | No schema extension | FR12 | Story 1.2 ✅ |
| AD-10 | TUI consistency | FR25 | Story 1.2 ✅ |
| AD-11 | PATH hint gate | FR16 | Story 1.4 ✅ |
| AD-12 | Preflight sequence | FR3 | Story 1.1 ✅ |
| AD-13 | Idempotency gate placement | FR17 | Story 1.5 ✅ |

**Coverage: 13/13 ADs — COMPLETE ✅**

---

## FR Coverage Analysis

The FR Coverage Map in epics.md explicitly maps every FR to a story. Verified against story ACs:

| FR | Story | AC references FR? |
|----|-------|------------------|
| FR1 | 1.2 | ✅ |
| FR2 | 1.2 | ✅ |
| FR3 | 1.1 | ✅ |
| FR4 | 1.2 | ✅ |
| FR5 | 1.2 | ✅ |
| FR6 | 1.2 | ✅ |
| FR7 | 1.2 | ✅ |
| FR8 | 1.2 | ✅ |
| FR9 | 1.2 | ✅ |
| FR10 | 1.2 | ✅ |
| FR11 | 1.2 | ✅ |
| FR12 | 1.2 | ✅ |
| FR13 | 1.1 primitive / 1.2 consumer | ✅ |
| FR14 | 1.3 | ✅ |
| FR15 | 1.4 | ✅ |
| FR16 | 1.4 | ✅ |
| FR17 | 1.5 | ✅ |
| FR18 | 1.5 | ✅ |
| FR19 | 1.6 | ✅ |
| FR20 | 1.1 primitive / 1.6 thread | ✅ |
| FR21 | 1.7 | ✅ |
| FR22 | 1.7 | ✅ |
| FR23 | 1.1 | ✅ |
| FR24 | 1.1 | ✅ |
| FR25 | 1.2 | ✅ |

- Total PRD FRs: 25
- FRs covered in epics: 25
- **Coverage: 100% ✅**

No orphaned FRs. No story ACs reference undefined FR IDs.

---

## UX Alignment Assessment

### UX Document Status

Found: `_bmad-output/specs/spec-wtx-install/ux-flow.md` (398 lines, Steps 0–11 + ordering rationale + dry-run visual).

### UX ↔ SPEC Alignment

ux-flow.md is declared as a `companion` in SPEC.md frontmatter and is explicitly sourced in ARCHITECTURE-SPINE.md frontmatter. Each wizard step in ux-flow.md maps directly to a CAP in SPEC.md. No UX screen exists without a corresponding capability.

### UX-DR → Story Coverage

| UX-DR | Story AC referencing it | Status |
|-------|------------------------|--------|
| UX-DR1 | Story 1.1 — gum absent notice AC | ✅ |
| UX-DR2 | Story 1.2 — welcome banner AC | ✅ |
| UX-DR3 | Story 1.2 — Steps 3-7 tui_* calls AC | ✅ |
| UX-DR4 | Story 1.2 — forge type tui_choose AC | ✅ |
| UX-DR5 | Story 1.2 — collective UX-DR3–9 AC | ✅ |
| UX-DR6 | Story 1.2 — collective UX-DR3–9 AC | ✅ |
| UX-DR7 | Story 1.2 — collective UX-DR3–9 AC | ✅ |
| UX-DR8 | Story 1.2 — collective UX-DR3–9 AC | ✅ |
| UX-DR9 | Story 1.2 — Step 8 plugin discovery AC | ✅ |
| UX-DR10 | Story 1.3 — hooks step box AC | ✅ |
| UX-DR11 | Story 1.4 — Gradle tui_confirm AC | ✅ |
| UX-DR12 | Story 1.4 — PATH hint gate AC | ✅ |
| UX-DR13 | Stories 1.7 (summary) + 1.6 (dry-run header) | ✅ |
| UX-DR14 | Story 1.6 — write-action [dry-run] AC | ✅ |
| UX-DR15 | **No story AC names UX-DR15 directly** | ⚠️ MINOR GAP |

**UX-DR15 gap detail:** UX-DR15 states "Wizard step ordering matches the UX rationale table: Step 0 → idempotency gate → Step 1 → ... → Step 11." This ordering is enforced distributively (Story 1.1 Step 0, Story 1.5 gate placement, Story 1.2 Steps 1-8, etc.) and is explicitly described in the Architecture flowchart (AD-12 + AD-13). However, no single story AC contains a `Then the wizard executes steps in the order: ... (UX-DR15)` assertion. Coverage is complete in substance but lacks a single traceable AC.

**Severity: Minor** — the ordering invariant is architecturally enforced via AD-12 and AD-13 (both fully covered by Story 1.1 and 1.5 ACs respectively), and the UX flow's ordering rationale table is the authority.

---

## Epic Quality Review

### Epic 1: Interactive Installer

**User value:** ✅ Clear user-centric goal — "Enable any developer to run `wtx install` ... at a valid PATH symlink, a fully-populated `wtx.toml`, and optionally installed Claude Code hooks, verified by `wtx doctor`."

**Independence:** ✅ Single epic, no external epics required.

**Story S.1 (Standalone: graphify):** ✅ Correctly isolated as a separate backlog item, consistent with SPEC non-goals. No coupling to Epic 1.

### Story Quality Assessment

#### Story 1.1 — Wizard shell, shared write primitives & preflight

- **Type concern:** This is largely a foundation story (dispatcher wiring, lib creation, preflight). For brownfield feature work this is acceptable and the user value ("all subsequent installer stories depend on a stable, tested foundation") is stated. **Not a blocking violation.**
- **ACs:** Well-formed Given/When/Then, each verifiable. Covers AD-1, AD-2, AD-4 (trap), AD-5 (write_or_dryrun), AD-7 (ledger init), AD-12. Syntax-check AC present.
- **Status:** ✅ PASS

#### Story 1.2 — Reference-templating engine (Steps 1-8 + TOML write)

- **Sizing concern:** This story covers 8 wizard steps (banner, binary install, forge, projects, detection markers, branch defaults, Jira, setup hook) plus plugin discovery and TOML write. It is large by conventional story standards.
- **Prerequisite declared:** ✅ Explicitly states "Prerequisite: Story 1.1."
- **ACs:** Well-formed. References FR1–FR13, FR25, NFR3, NFR4, AD-3, AD-8–10, UX-DR2–UX-DR9. 
- **Status:** ✅ PASS (sizing is wide but all steps are tightly coupled — they feed into a single TOML write call and cannot be meaningfully split without requiring a half-written `wtx.toml` between stories)

#### Story 1.3 — Claude Code hooks setup (Step 9)

- **ACs:** Well-formed. References CAP-3, AD-3, AD-5, AD-7, UX-DR10. Each AC is independently testable.
- **Dependency concern:** Uses `wtx_install_write_or_dryrun` (AD-5), ledger arrays (AD-7), and `install.sh` subprocess pattern (AD-3) — all from Story 1.1. **No explicit "Prerequisite: Story 1.1" line.** Developer picking this up must infer the dependency from the AD references.
- **Status:** ✅ PASS with documentation note (see Gap 2 below)

#### Story 1.4 — Extras menu (Step 10)

- **ACs:** Well-formed. References CAP-4, AD-3, AD-5, AD-7, AD-11, UX-DR11, UX-DR12.
- **Dependency concern:** Same as Story 1.3 — uses Story 1.1 primitives with no explicit prerequisite declared.
- **Status:** ✅ PASS with documentation note

#### Story 1.5 — Idempotency (skip/overwrite/merge)

- **ACs:** Well-formed. References CAP-5, AD-4 (atomic write via `_WTX_INSTALL_TMP`), AD-6, AD-13. Each scenario (skip/overwrite/merge) has its own Given/When/Then. Byte-for-byte diff AC on the skip path is excellently specific.
- **Dependency concern:** Uses `_WTX_INSTALL_TMP` / trap (Story 1.1, AD-4), `wtx_install_write_or_dryrun` (Story 1.1, AD-5), ledger (Story 1.1, AD-7). No explicit prerequisite.
- **Status:** ✅ PASS with documentation note

#### Story 1.6 — Dry-run mode end-to-end threading

- **Prerequisite declared:** ✅ Explicit "Prerequisite: Story 1.1 (`wtx_install_write_or_dryrun` defined; `WTX_INSTALL_DRY_RUN` exported; AD-5 guard in place)."
- **ACs:** Excellent end-to-end dry-run ACs. References CAP-6, AD-3, AD-5, AD-12, UX-DR13, UX-DR14.
- **Status:** ✅ PASS

#### Story 1.7 — Completion summary & doctor handoff (Step 11)

- **ACs:** Well-formed. References CAP-7, AD-7, NFR1, NFR12, FR22, UX-DR13. Explicit bash 3.2 array syntax AC.
- **Dependency concern:** Story 1.7 iterates `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS` populated by stories 1.2–1.6. The ledger arrays are initialized in Story 1.1 (tested in isolation with an empty ledger), but the end-to-end summary test requires 1.2–1.6 to have appended entries. No prerequisite chain stated.
- **Status:** ✅ PASS with documentation note (end-to-end validation of Step 11 requires prior stories, even though the implementation can be written independently)

---

## Dependency Order Analysis

The user specifically asked to confirm the dependency chain for the AD-2/AD-4/AD-5 write primitives:

```
Story 1.1 creates lib/wtx-install.sh with:
  - _wtx_toml_escape           (AD-2)
  - _wtx_csv_to_toml_array     (AD-2)
  - wtx_install_write_or_dryrun (AD-5)
  - _WTX_INSTALL_TMP / trap   (AD-4)
  - _WTX_LEDGER_KEYS / _WTX_LEDGER_VALS  (AD-7)

Consumers:
  Story 1.2 — EXPLICIT prerequisite declared ✅
  Story 1.3 — IMPLICIT (AD-3 + AD-5 + AD-7 referenced in ACs, but no Prerequisite line) ⚠️
  Story 1.4 — IMPLICIT (same) ⚠️
  Story 1.5 — IMPLICIT (AD-4 + AD-5 + AD-7 referenced) ⚠️
  Story 1.6 — EXPLICIT prerequisite declared ✅
  Story 1.7 — IMPLICIT (AD-7 ledger; no Prerequisite line) ⚠️
```

**The dependency order is sound** — the primitives are centralized in `lib/wtx-install.sh` (created by Story 1.1), so there is no risk of divergent implementations. The gap is purely documentation: sprint planning should treat Story 1.1 as a prerequisite for all stories in Epic 1, not just 1.2 and 1.6.

---

## Missing Requirements (Orphan Check)

- **Orphaned FRs:** None. All 25 FRs map to stories.
- **Orphaned ADs:** None. All 13 ADs are referenced in story ACs.
- **Orphaned CAPs:** None. All 7 CAPs map through FRs to stories.
- **Orphaned UX-DRs:** None. All 15 UX-DRs are covered (14 explicitly, UX-DR15 implicitly).
- **Story ACs referencing undefined IDs:** None found. Every CAP-*, AD-*, FR*, NFR*, UX-DR* citation in story ACs resolves to a defined requirement.

---

## Summary and Recommendations

### Overall Readiness Status

**READY for Sprint Planning** ✅

All requirements are covered. Traceability chain is intact. No blocking gaps. Two minor documentation improvements would sharpen sprint execution:

---

### Findings by Severity

#### 🟡 Minor — Gap 1: UX-DR15 has no dedicated story AC

**Finding:** UX-DR15 ("Wizard step ordering matches the UX rationale table") is not explicitly cited in any story acceptance criterion. The ordering is enforced architecturally through AD-12 (Story 1.1) and AD-13 (Story 1.5), but no AC reads "Then the wizard steps execute in this sequence."

**Impact:** Low. An integration test that validates the full step ordering would catch regressions here, but there is no such test framework. The architecture flowchart in ARCHITECTURE-SPINE.md + the individual step-placement ACs are the practical enforcement.

**Recommendation:** Add a note to Story 1.2's ACs: "Given the full wizard runs from Step 0 through Step 11, When completed, Then steps execute in the order defined by UX-DR15 and AD-12/AD-13: preflight → idempotency gate → banner → binary install → forge → projects → markers → branch defaults → Jira → hook selection → TOML write → hooks → Gradle → PATH hint → summary."

---

#### 🟡 Minor — Gap 2: Stories 1.3, 1.4, 1.5, 1.7 missing explicit "Prerequisite: Story 1.1"

**Finding:** Only Stories 1.2 and 1.6 declare an explicit `Prerequisite: Story 1.1` line. Stories 1.3, 1.4, 1.5, and 1.7 all use Story 1.1's primitives (ledger arrays, `wtx_install_write_or_dryrun`, `_WTX_INSTALL_TMP` / trap), but a developer reading them in isolation would need to infer this dependency from the AD reference tags in the ACs.

**Impact:** Low for experienced developers who read the AD references. Medium risk during sprint planning if a developer tries to start Story 1.3 or 1.4 before Story 1.1 is complete and merged.

**Recommendation:** Add a single line to Stories 1.3, 1.4, 1.5, and 1.7:
> **Prerequisite:** Story 1.1 (lib/wtx-install.sh and wizard skeleton in place).

Story 1.7 should additionally note: "Complete validation requires Stories 1.2–1.6 to have populated the ledger." (The implementation can be written against an empty ledger; only integration testing requires prior stories.)

---

### Recommended Next Steps

1. **Proceed to Sprint Planning** — add the two minor prerequisite clarifications to epics.md before the sprint kickoff meeting (15-minute fix).
2. **Sprint ordering:** Implement and merge Story 1.1 before any other story in Epic 1. Stories 1.2–1.6 can be parallelized (they add different wizard steps to the same script). Story 1.7 can be coded in parallel but must be integration-tested after 1.2–1.6.
3. **UX-DR15:** Treat the architecture flowchart in ARCHITECTURE-SPINE.md as the authoritative ordering reference during code review of `scripts/worktree-install.sh`.

---

### Final Note

This assessment found **2 minor documentation gaps** across 1 category (missing prerequisite declarations). No critical violations. No orphaned requirements. No story ACs reference undefined IDs. FR/AD/CAP/UX-DR traceability is complete.

**Status: READY for [SP] Sprint Planning.**
