# Dependency Security Review

This note records the August 2026 review of the HTTP and gRPC dependency advisories tracked by `hrafnsyn-r3t`. It is an application-level reachability assessment, not a suppression list: scanners should continue to report applicable advisory records.

## Resolved by dependency updates

The lockfile now uses:

- Bandit 1.12.4, beyond the 1.12.1 fix for [CVE-2026-65623](https://cna.erlef.org/cves/CVE-2026-65623.html)
- Cowboy 2.18.0, which fixes [CVE-2026-65624](https://cna.erlef.org/cves/CVE-2026-65624.html)
- Cowlib 2.19.0, which fixes [CVE-2026-59248](https://cna.erlef.org/cves/CVE-2026-59248.html)

These are remotely triggerable resource-exhaustion issues, so the version upgrades are the mitigation; the application does not rely on reachability arguments for them.

## Header-validation defaults

Hrafnsyn uses Bandit for the Phoenix endpoint. Cowboy is used by two optional listeners: the gRPC listener and PromEx's standalone metrics listener when `METRICS_PORT` is set. The gRPC child passes only the listen IP in `adapter_opts`; the PromEx configuration passes only `port` and `path` and does not set `cowboy_opts`. Neither path sets Cowboy's `invalid_response_headers` option, so Cowboy 2.18.0 retains its default `error_terminate` behavior, which rejects response header values containing carriage returns or line feeds before they are sent.

Hrafnsyn has no production call sites for Gun or generated gRPC stubs. Gun is present as the transport used by the gRPC client library; the only repository call site creates a loopback client in `test/hrafnsyn/grpc/auth_server_test.exs`. Neither application nor test configuration sets Gun's `invalid_request_headers` request option, so Gun 2.4.1 retains its default `raise` behavior for request header values containing carriage returns or line feeds.

Do not change either default to `ignore`. Any future Cowboy protocol options or Gun request options must preserve these validation modes.

## Conditional Cowlib advisories

### CVE-2026-43966 and GHSA-w4f7-4cxr-rv3c

[CVE-2026-43966](https://cna.erlef.org/cves/CVE-2026-43966.html) concerns attacker-controlled strings passed to Cowlib's structured-header encoder. There are no calls to `cow_http_struct_hd` in `lib/`, `config/`, or `test/`. Hrafnsyn does not build structured HTTP fields from request data, and the Cowboy/Gun transport validation described above remains enabled. Gun 2.4.1 is therefore covered by the upstream default mitigation referenced by the related GHSA record.

### CVE-2026-43969

[CVE-2026-43969](https://cna.erlef.org/cves/CVE-2026-43969.html) concerns attacker-controlled cookie names or values passed to `cow_cookie:cookie/1`. Hrafnsyn has no direct `cow_cookie` calls. Browser cookies are produced through Plug's signed session and response-cookie APIs. The only Gun-backed client is the loopback gRPC test client, which sends an application-generated bearer token as metadata and does not accept or serialize external cookie input.

The current application therefore has no path from attacker-controlled values to the affected encoder. This conclusion must be revisited if Hrafnsyn adds a production Gun/gRPC client, forwards caller-supplied metadata, constructs structured HTTP fields, or imports external cookies into a Gun cookie store.

## Revalidation

After any HTTP-stack lockfile change:

1. Run the full Mode B Hex dependency audit from the Nix development shell.
2. Confirm `.claude/deps-audit/last-run.json` was regenerated for the current `mix.lock` hash.
3. Require `summary.blocks_total` to be zero.
4. Keep mitigated or reachability-dependent advisory records visible with their rationale; do not silently suppress them.
