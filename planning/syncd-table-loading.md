# SyncD table loading

Status: implementation in progress; user authorized the current coding model.

Worktree: `/Users/michieldejong/gh/ontola/worktrees/atomic-server/syncd-table-loading`
Branch: `codex/syncd-table-loading`
Base: `b8a9fd2ed` (`origin/develop`, fetched 2026-10-26).
Owner: current SyncD investigation chat. Browser library read transport and its regression tests are the proposed implementation scope.

- [x] Inspect the running host and current develop; Astra-low architecture review.
- [x] Measure authenticated local HTTP and WebSocket independently of rendering.
- [x] Reproduce a stalled OPEN WebSocket at the library test layer.
- [x] Implement bounded authenticated GET recovery; never duplicate mutations.
- [ ] Verify loading feedback and first-page rendering in a matching isolated browser build.
- [ ] Document behavior and coverage, review diff, publish PR and follow exact-commit CI.

## Evidence and acceptance

The running binary is the older `first-drive-sync-probe-local` build. Its Store waits exclusively for a WS GET whenever the socket reports OPEN, with a 10,000 ms GET timeout. Its table caller does not pass the existing grid's busy state; current develop already does. “Use proxy” immediately recovered the drive in the browser. A fresh signed local client measured metadata 62 ms, a 30-member HTTP page 40 ms, WS authentication 8 ms and WS metadata GET 6 ms. These are diagnostic samples, not browser paint measurements or an established cause of every slow open.

Show a visible loading status while membership is pending and render an available first page without waiting for all 111 rows. Never settle a failed transport as authoritative empty membership. Preserve OPFS-first collection reads and local-only routing. A healthy WS should avoid redundant HTTP; a stalled one should permit a bounded signed HTTP GET without waiting ten seconds. Unauthorized errors must remain errors; late WS failures must not poison successful HTTP content; preserve existing stale-state/commit checks.

## Dependencies

The atomic-server-feature skill explicitly requires Terra coding and prohibits silent model substitution. Terra is absent from available collaboration models; the user explicitly authorized the current model for coding in this chat. Parent work may continue on SyncD projection labels/schema metadata in the separately owned atomic-plugins worktree.

Runtime data and benchmarks use private files outside Git. All committed tests and screenshots must use invented data. Existing benchmark workers remain active; serialize heavy builds and measurements with their shared lock. The user’s pilot must not be repointed to a mismatched isolated test server.

## Validation

All library unit tests: 1742 passed, one explicitly skipped; TypeScript checks passed. Targeted frame tests verify late cancelled responses are ignored while pushes still hydrate. The table already queries 30 rows per page. Browser paint acceptance remains pending: a matching native+WASM build is needed; laptop free disk was about 2.2 GiB at inspection.
