#!/usr/bin/env bash
# Erstellt ein lokales Self-Signed-Code-Signing-Zertifikat "BlitzText Local Dev"
# in der Login-Keychain. Damit bleiben TCC-Berechtigungen über Builds stabil,
# weil der Code-Hash + Signing-Identity (Designated Requirement) stabil bleibt.
#
# macOS prompts ggf. einmalig nach Passwort/Touch-ID, um das Cert in die
# Keychain zu importieren bzw. ein Trust-Setting zu setzen.

set -euo pipefail

CERT_NAME="BlitzText Local Dev"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# 1) OpenSSL-Konfig mit Code-Signing-Extensions
cat > "$WORK_DIR/cs.cnf" <<'CNF'
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = v3_codesign

[ dn ]
CN = BlitzText Local Dev

[ v3_codesign ]
basicConstraints       = CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CNF

# 2) Cert + Key generieren
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -sha256 \
    -keyout "$WORK_DIR/key.pem" \
    -out    "$WORK_DIR/cert.pem" \
    -config "$WORK_DIR/cs.cnf"

# 3) In P12 packen
openssl pkcs12 -export -legacy \
    -inkey "$WORK_DIR/key.pem" \
    -in    "$WORK_DIR/cert.pem" \
    -name  "$CERT_NAME" \
    -out   "$WORK_DIR/identity.p12" \
    -passout pass:blitztext

# 4) In Login-Keychain importieren — codesign darf zugreifen
security import "$WORK_DIR/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P blitztext \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# 5) ACL aktualisieren (manchmal nötig, sonst wird codesign blockiert)
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" \
    "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true

echo
echo "✓ Code-Signing-Identität '$CERT_NAME' erstellt."
echo "Verfügbare Identitäten:"
security find-identity -v -p codesigning login.keychain
