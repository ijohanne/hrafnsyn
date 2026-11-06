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
