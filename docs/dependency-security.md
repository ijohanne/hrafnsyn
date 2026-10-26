# Dependency Security Review

This note records the August review (`hrafnsyn-r3t`), September follow-up (`hrafnsyn-4dg`), and October update (`hrafnsyn-h5e`). The application-level reachability assessment below supports the narrow, temporary local gate exceptions described at the end.

## October 26, 2026 local update

Accepted dependency work (`hrafnsyn-dbi`) updates the following packages and
includes the authorized source/security migrations:

| Package | Version change |
| --- | --- |
| Bandit | 1.13.1 → 1.14.0 |
| Plug.Crypto | 2.2.0 → 2.2.1 |
| Phoenix | 1.8.15 → 1.8.16 |
| Phoenix LiveView | 1.2.12 → 1.2.13 |
| CAStore | 1.0.21 → 1.0.22 |
| elixir_make | 0.10.0 → 0.10.1 |
| esbuild wrapper | 0.10.0 → 0.10.1 |
| Tailwind wrapper | 0.5.1 → 0.5.2 |
| JOSE | 1.11.12 → 1.11.13 |
| Cowlib | Hex 2.21.0 → exact upstream Git fix `4401b858f2229abb3ea115c60924f6c77e5f8aa3` |
| MapLibre GL JS/CSS | 5.19.0 → 6.4.1 |

[Bandit 1.14.0](https://github.com/mtrudel/bandit/releases/tag/1.14.0)
fixes CVE-2026-108525, CVE-2026-108529, CVE-2026-109584,
CVE-2026-110314, CVE-2026-110499, CVE-2026-111101,
CVE-2026-111103, CVE-2026-113436, CVE-2026-114213,
CVE-2026-114216, and CVE-2026-115269. The fixes bound HTTP/2
resource use, enforce HTTP/1 chunk grammar, and harden WebSocket closing
and fragmentation. [Plug.Crypto 2.2.1 fixes CVE-2026-105963](https://cna.erlef.org/cves/CVE-2026-105963.html),
which could expose secrets in exception arguments after wrong-typed input.
Fresh unfiltered OSV queries against the actual resolved lock clear these
twelve records. Regression tests exercise malformed crypto input and a bare
newline in an HTTP chunk extension through a loopback Bandit server.

All eight native supply-chain rules ran on both versions of the nine changed
Hex packages. There are zero BLOCK or WARN findings. Cowlib's six-commit
upstream delta is reviewed separately because it now uses an immutable Git
source rather than a Hex release. CAStore's new Hex release
uses trusted publishing: its registry OIDC repository is `elixir-mint/castore`
and its actor `ericmj` matches the previous publisher. This provenance change
remains an INFO signal; no new vet entry or exception was added.

Cowlib now resolves to [the exact CNA-identified upstream fix](https://github.com/ninenines/cowlib/commit/4401b858f2229abb3ea115c60924f6c77e5f8aa3)
for CVE-2026-43966. This source still advertises version 2.21.0, so the
immutable Git revision is essential. It is six commits after the Hex release:
the reviewed changes update erlang.mk, HTTP/Host parsing and structured fields
to RFC 9651, then restrict serialized strings to printable ASCII. Regression
tests reject every byte outside `0x20..0x7e` directly at the encoder, and
round-trip every allowed byte including escaped quotes/backslashes. This is
the underlying encoder fix, independent of Cowboy/Gun transport validation.

The old OSV vulnerability ignore and MixAudit ignore flag have been removed.
Raw reports remain intact. Gun 2.7.0's catalog alias may still report
`GHSA-w4f7-4cxr-rv3c` because its registry range assumes an affected Cowlib
dependency and names an unavailable Gun 2.16.0 fix. Before classifying only
this existing alias as source-fixed, `mix security` requires the exact
Cowlib repository/ref, SHA-256 of `cow_http_struct_hd.erl`, and exhaustive
runtime rejection of non-VCHAR bytes. Any other advisory fails the gate.
Cowboy/Gun validation defaults remain enabled as defense in depth.
The separate Sobelow HTTPS fingerprint and **2026-11-16** expiration remain.

### MapLibre attribution fix and browser migration

The original bundled version 5.19.0 was affected by
[CVE-2026-85061 / GHSA-jrc7-96c5-q579](https://github.com/maplibre/maplibre-gl-js/security/advisories/GHSA-jrc7-96c5-q579):
its attribution sanitizer could skip adjacent unsafe attributes. Upstream lists
versions through 6.4.0 as affected and **6.4.1** as fixed. Hrafnsyn enables
the attribution control and loads a third-party OpenFreeMap style, so
malicious upstream attribution is a relevant input boundary. The browser
CSP's `script-src 'self'` restricts inline event handlers, but is defense in
depth and does not remove the vulnerable vendor code.

The official 6.4.1 main/shared/worker ES modules and CSS are now vendored
together, with registry integrity, SHA-256 checksums and license recorded in
`priv/static/vendor/maplibre-manifest.json`. The app uses an ESM namespace
import and serves workers from the same origin; no CSP relaxation or new
external CDN is introduced. WebGL2/ES2022 are required by this major release;
unavailable map contexts show an explanatory status instead of throwing from
the LiveView hook.

`scripts/check_maplibre.py` serves a local browser regression fixture with
**no CSP**. Its positive control proves inline event handlers can execute,
then the real attribution control must remove adjacent dangerous attributes
and prevent payload execution. The same fixture exercises ESM/worker loading,
WebGL2, controls, GeoJSON feature selection, route/visibility updates and a
marker popup. `--baseline-ref c17d935` can demonstrate the original failure.
No vendor advisory ignore was added.

### JOSE security release

[JOSE 1.11.13](https://github.com/potatosalad/erlang-jose/releases/tag/1.11.13)
was published after the initial proposal. Its eight confirmed primary
advisories are CVE-2026-65625, CVE-2026-65626, CVE-2026-65627,
CVE-2026-65628, CVE-2026-65629, CVE-2026-65630,
CVE-2026-65631 and CVE-2026-65632. The patch bounds JWE decompression and
RSA work, hardens signature/tag/key validation and export parameters, and
corrects the shipped variable-time crypto fallback default to false.
Hrafnsyn's first-party signer uses HS256; regression tests verify signed-token
round-trips, tamper rejection and native crypto with fallback disabled.
Upstream records remain authoritative while advisory databases catch up.

The asset wrapper updates preserve the Nix-selected esbuild and Tailwind
binaries. Runtime/OS packages, deeper vendor dependencies and dump1090
data/native inputs remain separate coverage layers. No database migration is
added by this change. These are local
changes; publication, downstream pins, and production activation remain pending.

## October 16, 2026 review

Updated 18 Hex packages, including Geo 4 and Peep 5, after saving the old
changelogs and inspecting the release diffs. LiveView 1.2 required declaring
the shared button component's existing `type` attribute. No database migration
is required. Frontend Phoenix modules are imported directly from `deps/`;
there is no npm manifest to synchronize.

| Package | Version change | Native audit risk |
| --- | --- | --- |
| bandit | 1.12.5 → 1.13.1 | clean |
| cowboy | 2.19.0 → 2.20.0 | clean |
| cowlib | 2.20.0 → 2.21.0 | clean |
| decimal | 3.1.1 → 3.2.0 | clean |
| dns_cluster | 0.2.0 → 0.3.1 | low (vetted) |
| finch | 0.23.0 → 0.24.0 | clean |
| geo | 3.6.0 → 4.1.0 | low (vetted) |
| googleapis | 0.1.0 → 0.2.0 | clean |
| gun | 2.6.0 → 2.7.0 | clean |
| peep | 4.4.0 → 5.0.1 | clean |
| phoenix_live_dashboard | 0.8.7 → 0.9.1 | clean |
| phoenix_live_view | 1.1.33 → 1.2.12 | clean |
| phoenix_pubsub | 2.3.0 → 2.4.1 | low (vetted) |
| protobuf | 0.17.0 → 0.17.1 | clean |
| req | 0.7.4 → 0.7.5 | clean |
| sobelow | 0.15.0 → 0.16.0 | clean |
| swoosh | 1.28.1 → 1.29.0 | clean |
| thousand_island | 1.5.0 → 1.6.0 | clean |

The raw OSV comparison clears five advisory records: Bandit's
`EEF-CVE-2026-105659` and `EEF-CVE-2026-105660`, Decimal's
`EEF-CVE-2026-97853`, Protobuf's `EEF-CVE-2026-104635`, and Cowlib's
`EEF-CVE-2026-43969`. No advisory was introduced. The cookie exception is
removed because [Cowlib 2.21.0 fixes that advisory](https://cna.erlef.org/cves/CVE-2026-43969.html).

Two raw scanner records remain: Cowlib `EEF-CVE-2026-43966` and Gun
`GHSA-w4f7-4cxr-rv3c`. Cowlib 2.21.0 still permits CRLF in its
structured-field encoder. The [CNA documents the Cowboy/Gun validation
mitigation](https://cna.erlef.org/cves/CVE-2026-43966.html); the new source
retains `error_terminate` and `raise` respectively. Repository searches still
find no structured-field encoder call or production Gun client. The sole
remaining OSV exception and exact-version guard were reviewed for Cowboy
2.20.0, Cowlib 2.21.0, and Gun 2.7.0, with a new deadline of **2026-11-16**.
The same review retains the exact Sobelow HTTPS fingerprint: ProxySSL still
performs trusted-proxy rewriting before the production HTTPS redirect.
No new advisory or scanner-rule suppression was added.

All eight native supply-chain rules ran on old/new package tarballs. Rules
1–5, 7, and 8 produced no findings. Rule 6 retains three publisher changes:

| Package | Publisher change | Corroborating evidence |
| --- | --- | --- |
| DNSCluster 0.3.1 | chrismccord → josevalim | Both are current Hex owners; the upstream v0.3.1 tag points to a release commit by josevalim. |
| Geo 4.1.0 | tylerayoung → axelson | Hex lists the Felt organization as owner; the upstream v4.1.0 release is authored by axelson. |
| Phoenix PubSub 2.4.1 | josevalim → steffend | Both are current Hex owners; the upstream v2.4.1 tag points to a commit by SteffenDE. |

These are review signals, not proof of compromise or proof of historical
ownership. Ian explicitly accepted all three exact versions as safe to deploy
on October 16. Their entries in `hex_vet.exs` downgrade these findings from
BLOCK to INFO, retaining the original findings and review evidence. The
final native audit has zero BLOCKs and three INFOs. The detailed local report
is `.claude/deps-audit/last-run.json`.

The Google APIs override is required by grpc_core 1.0.5's old `~> 0.1.0`
constraint; its status-details interface is checked by a round-trip test.
PromEx 1.12 still requires Peep 3/4; its `child_spec`, metric collection,
and Prometheus export interface remains compatible with Peep 5 and is
covered by a real telemetry-event/export test. The existing Gun override
remains necessary because gRPC 1.0.5 still declares `~> 2.4.0`.

The Nix dependency fixed-output hash has been regenerated. Both its derivation
and the full Nix release built successfully on aarch64-darwin. Review evidence
and changelog snapshots remain local.
`mix precommit` passed compilation with warnings as errors, formatting,
strict Credo, the four security checks with the reviewed exceptions, and
all 149 tests. LiveView's new test diagnostics warn about the existing
search form lacking an ID; the tests pass, but that form has no automatic
recovery after reconnect. The final Hex inventory reports every dependency
at its latest release.

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
4. Review the exact advisory records, their owner and tracking issue, and the expiration of any local gate exception.

## Local security gate

`mix security` runs `mix hex.audit`, `mix deps.audit --format json`,
`osv-scanner scan source --lockfile=mix.lock --format=json`, and Sobelow with
`--private --format json --threshold low --exit medium --skip`. It saves their output
under ignored `tmp/security/`; `mix precommit` runs this gate before tests.
Semgrep and YARA remain optional investigation tools in the Nix shell.

The current lockfile uses the exact upstream Cowlib encoder fix. There are no
OSV vulnerability ignores or MixAudit ignore flags. Raw Gun/Cowlib catalog
aliases remain visible when the scanner cannot model that fixed source.
The gate classifies only those exact records after validating the source/ref,
encoder file hash and actual runtime byte rejection; unrelated findings fail.
The earlier reachability-only exception is retired. Reassess any future
HTTP dependency, source pin or transport-option change.

Owner of the separate HTTPS review: Ian Johannesen. Tracking: vardrun
`hrafnsyn-fhv`. Expiration: **2026-11-16**, unchanged by this security update.

Sobelow's `Config.HTTPS` check reads only `config/prod.exs`. Hrafnsyn instead
uses `HrafnsynWeb.Plugs.ProxySSL` before routing: it accepts forwarded scheme
headers only from configured trusted proxies, and applies `Plug.SSL` to direct
requests when `HRAFNSYN_FORCE_SSL` is enabled (the production default). The
Nix nginx helper handles HTTPS itself and disables the app redirect. Adding
Phoenix's compile-time `force_ssl` would run before this trusted-proxy logic.
The only Sobelow fingerprint skip is `Config.HTTPS` in `config/prod.exs`, in
`.sobelow-skips`; the task checks its exact fingerprint and the same owner,
tracking issue, and expiration above. Any additional skip fails the gate.
ProxySSL's redirect, proxy trust, and HSTS behavior have dedicated tests.

The former Sobelow hardcoded JWT secret and missing CSP findings were fixed.
Development/test JWT signing keys are generated per runtime start when no
environment key is configured; production requires a configured key. Browser
pages now send a CSP, and the theme script is a local static file. The policy
allows Google Fonts and HTTPS map tile/style requests; `unsafe-inline` styles
remain necessary for MapLibre's generated element styles. Sobelow's remaining
low-confidence findings concern an operator-configured aircraft database path
and literal, parameterized SQL queries; they remain visible in the report and
are not suppressed.
