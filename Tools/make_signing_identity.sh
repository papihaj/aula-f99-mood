#!/bin/zsh
# Creates a self-signed code-signing certificate in your login keychain, so
# macOS keeps F99 Mood's permissions (Input Monitoring, Accessibility, audio)
# across rebuilds. Run once; build.sh picks it up automatically.
set -euo pipefail
NAME="${SIGN_IDENTITY:-F99 Mood Local Signing}"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "\"$NAME\" is already in your keychain."; exit 0
fi
DIR=$(mktemp -d); trap 'rm -rf "$DIR"' EXIT
cat > "$DIR/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/cert.cnf" \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" 2>/dev/null
PASS=$(openssl rand -hex 16)
# -legacy: the keychain can't read OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" -out "$DIR/id.p12" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
       -name "$NAME" -passout "pass:$PASS" -out "$DIR/id.p12"
security import "$DIR/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
echo "Created \"$NAME\". Now run ./build.sh."
