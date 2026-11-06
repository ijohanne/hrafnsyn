`callback.der` is an attached DER CMS SignedData message containing
`callback.plist`, signed with a disposable self-signed test certificate.
Neither the identifier nor the challenge belongs to a real device or invitation.
The private key was generated in a temporary directory and deleted afterward.

Reproduce using OpenSSL in a Nix shell:

```fish
set -l fixture_key_dir (mktemp -d)
openssl req -x509 -newkey rsa:2048 -nodes -subj '/CN=Hrafnsyn test fixture' \
  -keyout "$fixture_key_dir/key.pem" -out "$fixture_key_dir/cert.pem" -days 1
openssl cms -sign -binary -nodetach -outform DER \
  -in test/fixtures/devices/callback.plist -out test/fixtures/devices/callback.der \
  -signer "$fixture_key_dir/cert.pem" -inkey "$fixture_key_dir/key.pem"
rm -r "$fixture_key_dir"
```

The application extracts the bounded CMS payload and checks the invitation
challenge. It does not verify Apple signer trust or use UDIDs as authentication.

`callback-apple.ber` contains the same synthetic `callback.plist`, signed by
Apple's Security framework `CMSEncoder` on macOS. It exercises indefinite-length
SEQUENCE/context-specific containers and a constructed indefinite OCTET STRING,
which Apple's encoder produces even for this small payload. This is an encoder
compatibility fixture, not a response captured from an iPhone or iPad.

`encode-apple-cms.m` reproduces it on macOS 15 or newer. It imports the disposable
PKCS#12 identity with `kSecImportToMemoryOnly`, explicitly preventing reads or
writes of user keychains. Its signer-only chain option avoids trust-chain
discovery. From the repository's Nix developer shell, using fish:

```fish
set -l fixture_key_dir (mktemp -d)
openssl req -x509 -newkey rsa:2048 -nodes \
  -subj '/CN=Hrafnsyn-Synthetic-Apple-CMS' -days 1 \
  -keyout "$fixture_key_dir/key.pem" -out "$fixture_key_dir/cert.pem"
openssl pkcs12 -export -inkey "$fixture_key_dir/key.pem" \
  -in "$fixture_key_dir/cert.pem" -out "$fixture_key_dir/identity.p12" \
  -passout pass:synthetic-fixture
env -u SDKROOT -u DEVELOPER_DIR PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/xcrun clang -mmacosx-version-min=15.0 \
  -framework Foundation -framework Security \
  test/fixtures/devices/encode-apple-cms.m -o "$fixture_key_dir/encode"
"$fixture_key_dir/encode" "$fixture_key_dir/identity.p12" \
  test/fixtures/devices/callback.plist test/fixtures/devices/callback-apple.ber
rm -r "$fixture_key_dir"
```

Only signed CMS bytes and the public certificate are retained. Neither fixture
requires OpenSSL, Apple frameworks or a private key when running the test suite
or the production application.
