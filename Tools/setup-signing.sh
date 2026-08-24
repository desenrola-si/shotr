#!/bin/bash
# Cria (uma vez) um certificado local de assinatura e o importa no keychain do login.
# Sem ele o app é assinado ad-hoc, e cada rebuild vira "outro app" para o macOS —
# a permissão de Gravação de Tela cai toda vez.
set -euo pipefail

cd "$(dirname "$0")/.."
NAME="Shotr Local Signing"
DIR=".signing"
P12="$DIR/shotr-signing.p12"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "✓ identidade \"$NAME\" já está no keychain"
  exit 0
fi

mkdir -p "$DIR"
if [ ! -f "$P12" ]; then
  echo "▸ gerando certificado…"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -days 3650 \
    -subj "/CN=$NAME/O=Shotr" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"
  openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -out "$P12" \
    -passout pass:shotr -name "$NAME" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
  rm -f "$DIR/key.pem" "$DIR/cert.pem"
fi

security import "$P12" -k ~/Library/Keychains/login.keychain-db -P shotr -T /usr/bin/codesign -A
echo "✓ identidade importada — rode ./build.sh de novo"
