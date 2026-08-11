#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Creates the self-signed code-signing identity "macdraw-local-signing" in the
# login keychain (one-time setup). Needed by dist.sh to produce an app that:
#   - runs on macOS 15+ (unsigned apps are refused),
#   - doesn't show the "damaged, move to bin" dialog (ad-hoc signed apps do),
#   - shows the normal "unidentified developer" prompt instead, which
#     right-click -> Open accepts.
#
# Requires Homebrew OpenSSL 3 (`brew install openssl@3`) for the legacy p12
# format that the Keychain importer understands.

set -euo pipefail
OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_ca
[dn]
CN = macdraw-local-signing
[v3_ca]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/sign.key" -out "$WORK/sign.crt" \
  -days 3650 -config "$WORK/cert.cnf"

"$OPENSSL" pkcs12 -export -legacy \
  -inkey "$WORK/sign.key" -in "$WORK/sign.crt" \
  -out "$WORK/sign.p12" -passout pass:macdraw

security import "$WORK/sign.p12" -k ~/Library/Keychains/login.keychain-db \
  -P macdraw -T /usr/bin/codesign

echo "Identity 'macdraw-local-signing' installed."
echo "Verify: codesign --sign 'macdraw-local-signing' <file>"
