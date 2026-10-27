# SyncD fixes on the Atomic plugins pin

Status: implementation and validation in progress.

Task: codex://threads/01a16c93-853b-7362-94e6-c7287ee8a15e
Worktree: /Users/michieldejong/gh/ontola/worktrees/atomic-server/plugins-pin-syncd-fixes
Branch: codex/plugins-pin-syncd-fixes
Base: candidate22, 7dab1ce49a9159fdeff97e107fcb5962b615fad4.

- [x] Inspect current develop, open PRs, both pins and local host.
- [x] Astra-low architecture review; preserve candidate ancestry, do not merge develop.
- [x] Backport individual WebSocket GET recovery (PR #2368, e18ce3f1d).
- [x] Adapt batched SYNC_PUSH projection and LAST flush (PR #2361, a5e4d371a).
- [x] Render schema-backed nested JSON as readable table cell content.
- [x] Verify JSON null preservation, loading feedback and matching browser build.
- [x] Targeted Rust/browser tests, synthetic browser screenshots and live readback.
- [ ] Publish candidate and follow exact-head CI, then atomic-plugins pin PR.
- [x] Back up local store, roll out matching build on localhost, verify existing data.

Root owns browser/lib WS changes, planning, shared docs, candidate integration and deployment. pin_batch_backport owns Rust db/sync changes and their tests. schema_json_preview owns JSONCell and adjacent helper/tests. No agents switch branches, commit or push independently. Exact Terra model from skill is unavailable; user explicitly authorized current coding model earlier. New instructions do not require repeating that approval.

The pin lacks develop's projection batch API and drive-events API. Extract candidate projection transaction creation while preserving change-log operations, index eviction, snapshots and event semantics. Do not import the broad sparse-sync prerequisite. Retain signature/admission paths, staged parents and wire-order delta merging. Release resource locks before post-write events. Final LAST flush errors must fail sync, including empty LAST. Renderer uses declared OAD JSON schema, preserves meaning and ordering, keeps raw editing and unsupported-schema fallback; no provider-specific browser logic.

Existing localhost service uses an older 0f9b5f429 native build plus local first-upload changes, so do not replace it before matching-build tests and a recoverable store backup. Runtime data and private notes stay outside Git. User explicitly authorized this local deployment. No develop merges are authorized.

Validation so far: all 1,189 candidate library tests passed (one intentional skip); 11 schema preview tests and full UI typecheck passed. Rust targeted suites passed: sync_push 12, public replica batch 1, change_log 21, engine 17, import_identity 5, crash durability 2. Astra architecture review found no actionable issues. Matching frontend/WASM and native server builds remain in progress. Also narrowly backported upstream JSON null preservation from bc493c230 because candidate22 otherwise drops null array fields on edits.

Runtime validation (2026-10-27): matching WASM/frontend/native wasm-plugins+plugin-routes build passed. The synthetic native Playwright schema-preview test passed with no retries, including full JSON editor round trip. Offline copy-on-write backup preceded local rollout. Both isolated clone and live pilot readback checked all 194 resources and 2,491 fields, with 21 issues and 111 notes and no mismatches. The same live readback passed using the candidate23 JavaScript library. All 111 real note bodies use the declared full OAD schema preview; 17 long values have bounded previews, with complete data retained. Candidate23 PR #2372 is open; shared pin advancement still waits for exact-head CI. The SyncD companion pin alignment is under compatibility testing.

Candidate follow-up: single-line previews preserve the table's fixed row height, with ellipsis and bounded readable tooltips. Two new failing-first helper regressions prevent long-value labels turning into ellipses or single-field wrappers reappearing. All 13 helper tests and full UI/E2E typechecks passed. The initial matching native desktop/mobile Playwright run passed; the helper follow-up will be rechecked in the final build. Native companion compatibility testing exposed the remaining Rust nested-null writers from #2206; their focused regression failed first, then all 42 Loro tests passed with the three-arm backport. Astra reviewed the core change and peer binding compatibility fix without findings.
