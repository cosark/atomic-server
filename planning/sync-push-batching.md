# Batched SYNC_PUSH persistence

Status: implementation and local acceptance testing.

- Task: local SyncD / atomic-lib experiment, 132 API rows (10,091 Atomic drive resources).
- Worktree: `/Users/michieldejong/gh/ontola/worktrees/atomic-server/sync-push-batching`.
- Branch: `codex/sync-push-batching`.
- Base: fetched `origin/develop`, `b8a9fd2ed0169751246bdb8062bef766005d793c`.
- Dependency: base includes the SyncD peer's core pin `66880fc53f392771761bb4d967e1e443344a7e34`; relevant importer/persistence code is unchanged since that pin.
- Ownership: Terra implements Db/engine/peer persistence and regression tests; coordinator owns benchmark example, docs, coverage and integration. Astra reviews architecture and the final change.

## Acceptance

- [x] Inspect original checkout and record baseline outside the repository; create isolated worktree.
- [x] Astra architecture review and Terra implementation assignment.
- [x] Reproduce per-localId flush behavior with a regression at the lowest practical layer.
- [x] Batch admitted resource projections, snapshots and indexes into one transaction per chunk, including localId resources.
- [x] Preserve resource/identity locking, staged-parent drive checks, duplicate delta merging, intentional replica identity duplicates, watched/search indexes, lens work and signed-envelope retention.
- [x] Propagate one explicit final import flush on the final SYNC_PUSH chunk, including an empty final chunk; propagate flush failure instead of acknowledging success.
- [ ] Targeted tests, crash/reopen durability, formatting and relevant lint checks pass.
- [x] Benchmark the complete local dataset over a real loopback WebSocket from a prepared sender into an already-open empty receiver. Include transport/import/index work and durable flush; exclude database startup and sender preparation. Report connection/auth separately and with transport timing. Preserve all rows/resources; verify properties, CRDT state, signed envelopes and indexes after reopen.
- [x] Report actual times against the 100 ms target without dropping data, indexes, validation or durability.
- [x] Update public persistence/sync documentation and TESTING_COVERAGE.md.
- [ ] Review complete diff, commit only owned paths, push a PR and follow exact-commit CI.

## Design

Use the existing projection transaction builder, not the bulk helper unchanged. Acquire sorted normalized resource locks before reading snapshots, then sorted identity locks for accepted final resources. Process repeated subjects into accepted staged state in wire order. New parent inference can use accepted staged parents. Apply the transaction before releasing resource/identity guards; release guards before lens backfill, which may acquire resource locks. Preserve full indexing and explicit merged snapshots. Signed envelopes remain on the existing verified import path initially. Final-chunk flush follows envelopes and post-commit work.

The durability promise is one explicit final sync barrier; a store's periodic durability thread may also flush. Intermediate chunks are not an independently acknowledged durable completed transfer. Existing authority/quota checks remain unchanged.

## Evidence and open risks

- Previous 95-resource control: 2.58 s import, 167 ms socket wait, 11 ms final flush; localId imports force their own flushes today.
- Previous full 132-row WebSocket receiver reached a 240 s process cutoff. This is a failure, not a completed timing.
- The prepared checkpoint is an isolated copy of an existing SyncD export, owned by generated test agents. No personal owner key is read and no provider API call is needed.
- Watch staged-parent event attribution, duplicate delta handling, lens lock re-entry, signature-retention ordering, and callers that swallow final import errors.
- 100 ms remains a target, not an established result. Keep source preparation, startup, transport, import, flush and verification timings distinct.

## Local benchmark result

Three optimized release runs with sender prepared and receiver startup excluded:
28,793.848 ms; 28,560.276 ms; 28,671.734 ms. Median 28.67 s: the 100 ms target
is not met. Each run imported and verified all 132 API rows, 10,091 Atomic
resources and 10,091 retained signed envelopes, over 102 chunks / 61,372,321
wire bytes. Verify current properties, full decoded CRDT state and causal hash,
row membership, envelope signatures, SearchDocs and SearchPostings live and
after reopen. Raw Loro snapshot encodings differ for equivalent state and are
excluded from projected-value hashing, with deep-state comparison instead.

Reader nonce AUTH is exercised; receiving import uses a pre-established owner
principal, not source peer authentication. Envelope validation/storage remain
individual, so this is resource batching plus one final import flush, not all
writes in one transaction. Database startup and sender preparation are outside
the measured interval. The 11870 Atomic Server remains stopped.

Baseline regression: test-only copy on b8a9fd2ed fails at non-final localId
flush count (observed 2, expected 0). Feature counting tests pass. Hard abort
without destructor after an empty LAST preserves rows, identity/parent indexes,
CRDT snapshot and signed envelope. Final broader checks and exact-commit CI
remain to be completed before removing this plan.

## Broader validation

- `cargo test -p atomic_lib --features db-redb,ws --lib`: 878 passed,
  1 failed, 11 ignored (890 total). The sole failure is the macOS/redb
  compaction disabled-policy 90% disk-retention assertion at compaction.rs:599.
- Unchanged detached base b8a9fd2ed reproduced that exact assertion: one pass,
  then one failure with 3,981,312 disk bytes vs 4,952,064 before reopen. No
  compaction code is changed here; the failure is pre-existing/nondeterministic.
- Crash integration: 2 passed, 2 subprocess entry points ignored as intended.
- Workspace rustfmt check passes. Pre-commit Clippy and exact-commit CI pending.
