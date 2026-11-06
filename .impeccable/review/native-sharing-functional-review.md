# Native sharing functional review

Scope: `hrafnsyn-o3n`; independent source and regression-test review of `AppModel`, app URL/activity handling, tracking share controls and `SharedTrackTests`. The reviewer implemented the Rust/server contract and therefore does not present that work as independently reviewed here.

Result: no unresolved material findings in the final Swift source reviewed.

Resolved during review:

- A cold launch with distinct web and gRPC origins originally ignored the saved website mapping and prompted an unnecessary server switch. The current-server decision now includes the saved mapping, with a regression test.
- An unavailable metadata response originally skipped website validation before resolving an identity on a separate gRPC endpoint. New cross-origin connections now require advertised metadata or a previously saved matching association. Contradictory current metadata always blocks lookup. Retry fetches metadata again; the regression asserts that lookup cannot happen before verification.
- Opening the already selected track with a different history range originally left the map navigation observer unchanged. Each successful shared-link resolution now emits a separate navigation revision, observed by the tracking view, while avoiding duplicate ID-based navigation.
- A stationary shared contact now uses a camera helper that preserves an existing close zoom and only zooms in to a 2 km width when starting from a wider overview. Its recentering accounts for the phone panel; the regression covers both retained close dimensions and overview focus. This avoids reintroducing the previous stationary-contact zoom-out bug through a warm shared link.

Session storage remains partitioned by normalized gRPC origin. Switching servers reads only the destination's saved session; URLs contain vehicle identity and history, never credentials. Authentication retains the pending target through login. Generation, selection-request and pending-link identifiers prevent a delayed prior connection or lookup from replacing a newer destination. Cancellation preserves the previous visible selection. Metadata and track-request credential persistence failures are surfaced rather than silently discarded.

The selected record can remain visible when absent from the active list. Share URLs use the server-advertised web origin and selected history range. Current-server links open directly; a different server requires an explicit connection choice. Previously saved web-to-gRPC associations are retained as the offline metadata fallback; they are not a new certificate or domain-ownership verification mechanism.

Validation evidence: implementation agent reports 29 passing iOS tests, including the reviewed cold/warm launch, identity/login continuation, destination-session isolation, last-link-wins, metadata failure/retry, missing metadata, same-track range, stationary shared-camera and Foundation custom-scheme wrapper cases. This reviewer inspected source and tests, but did not run Simulator gestures, render checks, signing or device Universal Link verification. Those remain the parent task's checks and must be reported separately.
