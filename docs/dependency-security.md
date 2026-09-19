# Dependency Security Review

This note records the August 2026 review (`hrafnsyn-r3t`) and September 2026 follow-up (`hrafnsyn-4dg`). It is an application-level reachability assessment, not a suppression list: scanners should continue to report applicable advisory records.

## September 2026 follow-up

### Follow-up on remaining findings

Gun was subsequently upgraded from 2.4.1 to the latest Hex release, 2.6.0, together with `grpc`, `grpc_core`, and `grpc_server` from 1.0.2 to 1.0.5. Even gRPC 1.0.5 declares `~> 2.4.0` for its optional Gun transport, so the application explicitly overrides that constraint. The full 142-test suite, including the gRPC authentication tests, passes with this combination. The Nix dependency hash was regenerated again.

The three remaining scanner records persist at these latest versions. A direct runtime check confirmed that Cowlib 2.20.0 still emits CRLF from a structured-field string and accepts `; admin=1` inside a cookie value, while Gun 2.6.0 rejects the resulting CRLF request header with `invalid_request_header` before sending it. These behaviors were checked without making a network request.

- **CVE-2026-43966:** upstream closed [Cowlib PR 163](https://github.com/ninenines/cowlib/pull/163) and [PR 166](https://github.com/ninenines/cowlib/pull/166), explaining that Cowboy and Gun reject invalid header characters downstream. There is no published Cowlib encoder fix to upgrade to.
- **CVE-2026-43969:** the CNA references a [preliminary patch in the EEF fork](https://github.com/erlef/cowlib/commit/177953d). It is not in the current Cowlib release. Adopting it would require carrying a patch or fork, not an ordinary Hex update.
- **GHSA-w4f7-4cxr-rv3c:** the GitHub record lists a Gun fixed version of 2.16.0, inconsistent with the [CNA's Gun 2.4.0 mitigation](https://cna.erlef.org/cves/CVE-2026-43966.html). Upgrading Gun to 2.6.0 therefore does not clear that scanner record, although the runtime rejection is confirmed.

Mint's earlier publisher-change flag is a supply-chain review signal, not a vulnerability or a missing security update. The supporting owner/tag evidence remains below; it has not been silently vetted or suppressed. The current Mode B scan covers the four follow-up package changes, and retains the previous Mint finding as historical review context.

### Initial update

The September 20 review compared the working lockfile with HEAD (Mode B), scanned old and new Hex tarballs with all eight native audit rules, and ran Semgrep, YARA, `mix hex.audit`, `mix deps.audit`, and OSV-Scanner. Seven OSV advisory records disappeared after these updates:

| Package | Previous | Updated | Resolved advisories |
| --- | --- | --- | --- |
| Bandit | 1.12.4 | 1.12.5 | [CVE-2026-74836](https://cna.erlef.org/cves/CVE-2026-74836.html), [CVE-2026-75484](https://cna.erlef.org/cves/CVE-2026-75484.html) |
| Cowlib | 2.19.0 | 2.20.0 | [CVE-2026-43971](https://cna.erlef.org/cves/CVE-2026-43971.html) |
| Mint | 1.9.3 | 1.10.1 | [CVE-2026-82672](https://cna.erlef.org/cves/CVE-2026-82672.html), [CVE-2026-82728](https://cna.erlef.org/cves/CVE-2026-82728.html), [CVE-2026-82729](https://cna.erlef.org/cves/CVE-2026-82729.html) |
| Phoenix LiveView | 1.1.32 | 1.1.33 | [CVE-2026-64941](https://cna.erlef.org/cves/CVE-2026-64941.html) |

Resolution also updated Phoenix to 1.8.14, Cowboy to 2.19.0, Ranch to 2.3.0, Phoenix PubSub to 2.3.0, Castore to 1.0.21, LazyHTML to 0.1.12, and elixir_make to 0.10.0. The Nix fixed-output dependency hash was regenerated and its build verified. `mix precommit` passed compilation with warnings treated as errors, formatting, strict Credo, and all 142 tests.

The native audit retains one **BLOCK, rule 6**: Mint's release publisher changed from `whatyouhide` (1.9.3) to `ericmj` (1.10.1). [Hex lists both accounts as owners](https://hex.pm/packages/mint), and the [upstream 1.10.1 tag](https://github.com/elixir-mint/mint/releases/tag/v1.10.1) was also created by `ericmj`. This is consistent with publication by another project owner, but does not prove historical ownership or eliminate supply-chain risk. The finding remains unsuppressed; no vet ledger entry was added. The audit therefore does not qualify for the zero-BLOCK gate below.

Semgrep reported no findings. YARA matched build-tool HTTP strings and embedded base64 data in both old and new packages; these remain informational under the differential audit rule. This scan covers direct source patterns in changed packages, not arbitrary runtime behavior or every possible compile-time call chain.

OSV still reports Cowlib CVE-2026-43966 and CVE-2026-43969, which list no fixed release, and Gun GHSA-w4f7-4cxr-rv3c. `mix deps.audit` still exits nonzero for the Gun record. The reachability and default-validation assessments below were rechecked against `lib/`, `config/`, and `test/`; none of these records were added to an ignore list. `mix hex.audit` found no retired packages. Detailed findings and the lockfile SHA-256 are in the local `.claude/deps-audit/last-run.json` sidecar.

## Resolved by dependency updates

The lockfile now uses:

- Bandit 1.12.5, beyond the 1.12.1 fix for [CVE-2026-65623](https://cna.erlef.org/cves/CVE-2026-65623.html)
- Cowboy 2.19.0, beyond the 2.18.0 fix for [CVE-2026-65624](https://cna.erlef.org/cves/CVE-2026-65624.html)
- Cowlib 2.20.0, beyond the 2.19.0 fix for [CVE-2026-59248](https://cna.erlef.org/cves/CVE-2026-59248.html)

These are remotely triggerable resource-exhaustion issues, so the version upgrades are the mitigation; the application does not rely on reachability arguments for them.

## Header-validation defaults

Hrafnsyn uses Bandit for the Phoenix endpoint. Cowboy is used by two optional listeners: the gRPC listener and PromEx's standalone metrics listener when `METRICS_PORT` is set. The gRPC child passes only the listen IP in `adapter_opts`; the PromEx configuration passes only `port` and `path` and does not set `cowboy_opts`. Neither path sets Cowboy's `invalid_response_headers` option, so Cowboy 2.19.0 retains its default `error_terminate` behavior, which rejects response header values containing carriage returns or line feeds before they are sent.

Hrafnsyn has no production call sites for Gun or generated gRPC stubs. Gun is present as the transport used by the gRPC client library; the only repository call site creates a loopback client in `test/hrafnsyn/grpc/auth_server_test.exs`. Neither application nor test configuration sets Gun's `invalid_request_headers` request option, so Gun 2.6.0 retains its default `raise` behavior for request header values containing carriage returns or line feeds.

Do not change either default to `ignore`. Any future Cowboy protocol options or Gun request options must preserve these validation modes.

## Conditional Cowlib advisories

### CVE-2026-43966 and GHSA-w4f7-4cxr-rv3c

[CVE-2026-43966](https://cna.erlef.org/cves/CVE-2026-43966.html) concerns attacker-controlled strings passed to Cowlib's structured-header encoder. There are no calls to `cow_http_struct_hd` in `lib/`, `config/`, or `test/`. Hrafnsyn does not build structured HTTP fields from request data, and the Cowboy/Gun transport validation described above remains enabled. Gun 2.6.0 is therefore covered by the upstream default mitigation referenced by the related GHSA record.

### CVE-2026-43969

[CVE-2026-43969](https://cna.erlef.org/cves/CVE-2026-43969.html) concerns attacker-controlled cookie names or values passed to `cow_cookie:cookie/1`. Hrafnsyn has no direct `cow_cookie` calls. Browser cookies are produced through Plug's signed session and response-cookie APIs. The only Gun-backed client is the loopback gRPC test client, which sends an application-generated bearer token as metadata and does not accept or serialize external cookie input.

The current application therefore has no path from attacker-controlled values to the affected encoder. This conclusion must be revisited if Hrafnsyn adds a production Gun/gRPC client, forwards caller-supplied metadata, constructs structured HTTP fields, or imports external cookies into a Gun cookie store.

## Revalidation

After any HTTP-stack lockfile change:

1. Run the full Mode B Hex dependency audit from the Nix development shell.
2. Confirm `.claude/deps-audit/last-run.json` was regenerated for the current `mix.lock` hash.
3. Require `summary.blocks_total` to be zero.
4. Keep mitigated or reachability-dependent advisory records visible with their rationale; do not silently suppress them.
