# Collect iPhone and iPad UDIDs

Hrafnsyn provides collection links on its own domain so friends can send a
device identifier without connecting their device to a computer. A signed-in
Hrafnsyn user creates each invitation and is the only account that can view its
collected UDID. Friends do not need a Hrafnsyn account.

## Send a collection link

1. Sign in and open **iOS devices** from the account menu, or visit
   `/users/devices`.
2. Give the invitation a useful name, such as “Alex's iPhone,” and create it.
3. Tap **Copy** beside the invitation link and send it to the device owner. Create a
   separate invitation for each iPhone or iPad.
4. After your friend completes the steps below, refresh **iOS devices** and use
   **Copy** beside the collected UDID.
5. Register the device in your Apple developer account, update the Ad Hoc
   provisioning profile to include it, and export a new IPA. The [mobile
   distribution guide](mobile.md#export-a-distributable-ipa) contains the build
   and export commands.

Each invitation accepts one device. Retrying the same device response is safe;
a different UDID cannot replace an already-collected one. The collection page
does not register devices with Apple or issue signing certificates. Apple documents the subsequent [registered-device distribution
workflow](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

## Publish and download the current IPA

The signed-in device page also has an **iPhone & iPad app** section. Administrators
can expand **Upload IPA** (or **Replace IPA**), choose an exported `.ipa` of at
most 250 MiB, and select **Publish IPA**. The upload replaces the current file
atomically; there is no release history. A failed upload leaves the previous
download intact. The server checks the archive structure, not Apple signatures
or whether individual devices are provisioned.

Every signed-in user can select **Download IPA**. Public invitation links do not
grant access to the download. This is a file download, not an over-the-air
installer: use Xcode or Apple Configurator on a Mac to install the signed IPA on
a device included in its provisioning profile. See the [distribution
guide](mobile.md#export-a-distributable-ipa) for the local device list and export.

Files live outside `priv/static`, under `HRAFNSYN_MOBILE_BUILD_DIRECTORY`
(`tmp/mobile-builds` in development). The NixOS module sets this to
`/var/lib/<service-user>/mobile-builds`, so the current IPA survives service
restarts and upgrades. Only the application serves downloads after login. The
upload route has its own 251 MiB multipart limit; other request limits stay the
same. If you manage a reverse proxy yourself, mirror this limit only for
`/admin/mobile-build` and allow enough time for the upload.

## Complete an invitation on the device

1. Open the invitation in **Safari on the iPhone or iPad being registered**.
2. Check who invited you, then download the device profile.
3. Open **Settings → General → VPN & Device Management**, or tap **Profile
   Downloaded** if it appears near the top of Settings.
4. Review and approve the profile. It is unsigned, and iOS displays **Not
   Signed**. The profile requests only the device's UDID; it does not install
   Hrafnsyn, configure a VPN, install a root certificate or enroll the device in
   mobile device management.
5. Return to the invitation in Safari to check whether collection succeeded.
   The invitation creator can now copy the identifier from their account page.

The identifier is sent to this Hrafnsyn server, without a third-party UDID
collection service. The public confirmation page does not display the UDID.
Someone holding a valid link can use its invitation, so an invitation is not
proof of a person's identity. Delete a link and create a replacement if it was
sent to the wrong person.

An expired or deleted invitation is unavailable. Ask its creator for a new
link. A failed response does not overwrite an existing collected identifier.

## Limits and retention

- Invitations expire seven days after creation. An expired link cannot collect
  another response, even if its profile was downloaded earlier.
- Each account can retain 25 invitation records, including completed and
  expired invitations. Delete old records to make room.
- **Delete** immediately invalidates the link and removes its collected UDID
  from the application database.
- Records become eligible for deletion 30 days after invitation creation,
  rather than 30 days after collection. A global cleanup runs one minute after
  application startup and then hourly; account listing and creation also remove
  that account's old records. Database backups have their own retention policy.

The database stores the invitation label, owning account, timestamps and
collected UDID. Invitation tokens and profile challenges are stored as hashes;
the raw callback body and its embedded certificates are not retained. Keep a
needed device identifier in your Apple developer account before the collection
record is deleted.

## Server and proxy configuration

Share and callback URLs come from the configured `HrafnsynWeb.Endpoint.url()`.
The request's `Host` header does not choose where a profile sends a UDID.
Configure the endpoint's external host, scheme and port to its canonical HTTPS
address. On the production deployment this is `https://hrafnsyn.unixpimps.net`.
The profile generator allows HTTP only for `localhost`, `127.0.0.1` or `::1`
development endpoints. A remote HTTP deployment cannot generate a profile.

The NixOS module's nginx helper protects the entire `/devices/invite/` prefix:
it disables access logging and error logging for these URLs and limits request
bodies to 64 KiB. This prefix takes priority over the normal web/gRPC location.

If you use another proxy, apply equivalent rules to both access logs and error
logs, including upstream failures and malformed-request errors. Error logs can
contain the full request URI even when access logging is disabled. Do not let
an outer proxy, CDN, request tracing system or cache record these invitation
URLs or callback bodies. Preserve the 64 KiB body limit. The application also
limits callback reads, omits invitation-route request logs and identifier SQL
logs, and returns `no-store`, `no-referrer` and no-index response headers.

The account page and invitation creation/deletion use normal login and CSRF
protection. These public endpoints allow the friend and iOS profile service to
complete the invitation:

| Route | Purpose |
| --- | --- |
| `GET /devices/invite/:token` | Instructions and collection status; never the UDID |
| `GET /devices/invite/:token/profile` | Download a profile while the invitation is pending |
| `POST /devices/invite/:token/callback` | Receive the device's bounded CMS response |

Only the callback bypasses browser-session CSRF validation, because iOS posts
outside the user's browser session. It must present the valid invitation token
and the independent challenge embedded in the profile. Completion is atomic;
expired, deleted, revoked or mismatched submissions are rejected. A successful
callback returns a 301 redirect to the invitation page, with no UDID in the URL.

## Protocol and verification

The profile follows Apple's [Profile Service
payload](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/iPhoneOTAConfiguration/profile-service/profile-service.html)
and requests only the `UDID` device attribute. The callback accepts attached
CMS SignedData containing a UTF-8 plist, in DER or Apple's streaming BER format.
The parser limits the complete ASN.1 tree to 24 nesting levels and 2,048 nodes
within the 64 KiB body limit. Indefinite lengths are allowed only for constructed
values, with balanced end-of-content markers. Constructed OCTET STRING content
may contain only OCTET STRING chunks. Raw XML callbacks, trailing bytes and
malformed structures are rejected. Modern and legacy UDIDs are normalized to
uppercase. DTD references are inert; external or
internal entity declarations, duplicate keys and nested plist values are
rejected. No runtime OpenSSL process or XML entity resolver is used.

The CMS envelope is decoded, but its signature and Apple certificate trust are
not verified. A collected UDID is user-supplied registration information, not
device attestation or an authentication credential. The invitation challenge
binds the response to the downloaded profile. Apple's [sample device
response](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/iPhoneOTAConfiguration/ConfigurationProfileExamples/ConfigurationProfileExamples.html)
documents this challenge echo. Unity's [Build Automation client
API](https://docs.unity.com/en-us/oas-build-automation-client/2.0.0) also documents
the public CMS callback and 301 handoff to the browser; Hrafnsyn keeps device
identifiers out of its redirect URL.

Automated tests cover both an OpenSSL-signed DER fixture and a signed fixture
produced by Apple's Security framework `CMSEncoder` on macOS, alongside challenge
binding, malformed/oversized input, ownership, expiry and repeated submissions.
The Apple fixture uses a disposable identity imported only into process memory;
it contains synthetic values and is not a captured iPhone response. Its
indefinite containers and constructed OCTET STRING reproduced a rejection by
the original DER-only parser. A physical iPhone installation reported HTTP 400;
successful installation and the Settings-to-Safari handoff still need a device
retest after this compatibility fix.

For valid invitations, callback parse failures log only fixed diagnostic
categories, such as `invalid_cms`, `invalid_plist` or `challenge_mismatch`. They
never include the response body, challenge, invitation token or UDID.
