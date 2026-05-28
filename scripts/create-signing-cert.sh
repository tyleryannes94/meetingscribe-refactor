#!/usr/bin/env bash
#
# Creates a self-signed code-signing certificate in the login keychain.
# Once installed, every `make app` run signs MeetingScribe with the SAME
# identity, so TCC permissions (Screen Recording, Microphone, Calendar,
# Notifications, Accessibility) persist across rebuilds.
#
# This is a one-time setup. Safe to re-run — it no-ops if the identity exists.
set -euo pipefail

CERT_NAME="MeetingScribe Local Signer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p basic "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ Code-signing identity '$CERT_NAME' already exists. Nothing to do."
    security find-identity -p basic "$KEYCHAIN" | grep "$CERT_NAME"
    exit 0
fi

echo "→ Creating self-signed code-signing certificate '$CERT_NAME'..."
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext

[dn]
CN = ${CERT_NAME}

[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -new -x509 -nodes -newkey rsa:2048 \
    -keyout "$TMP/key.pem" \
    -out "$TMP/cert.pem" \
    -days 3650 \
    -config "$TMP/openssl.cnf" \
    >/dev/null 2>&1

# Bundle private key + cert into a PKCS#12 (.p12) blob for keychain import.
# Use a Homebrew openssl if present (supports modern + legacy PKCS#12), else
# fall back to LibreSSL with explicit algorithm flags it accepts.
if [ -x /opt/homebrew/opt/openssl@3/bin/openssl ]; then
    OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
    P12_FLAGS="-legacy"
else
    OPENSSL=$(command -v openssl)
    P12_FLAGS=""
fi

$OPENSSL pkcs12 -export $P12_FLAGS \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" \
    -passout pass:tempp12pass \
    -name "$CERT_NAME"

# Import into the login keychain. `-T /usr/bin/codesign` whitelists codesign to
# use the private key without prompting on every signing operation.
security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" \
    -P tempp12pass \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -A >/dev/null

# Make sure codesign can use the key without a per-command prompt.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -k "" \
    "$KEYCHAIN" >/dev/null 2>&1 || true

echo "✓ Created identity:"
security find-identity -p basic "$KEYCHAIN" | grep "$CERT_NAME"
echo ""
echo "Next: run 'make install' to rebuild and reinstall MeetingScribe with the"
echo "stable signing identity. After granting permissions ONCE more, future"
echo "rebuilds will preserve them."
