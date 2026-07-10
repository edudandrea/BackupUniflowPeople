#!/usr/bin/env bash
set -Eeuo pipefail

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Erro: variável $name não configurada." >&2
    exit 1
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Erro: comando '$1' não encontrado." >&2
    exit 1
  }
}

require_var DATABASE_PUBLIC_URL
require_var BACKUP_ENCRYPTION_PASSWORD
require_command pg_dump
require_command openssl

BACKUP_DIR="${BACKUP_DIR:-backup-output}"
TIMESTAMP="$(TZ=America/Sao_Paulo date '+%Y-%m-%d_%H-%M-%S')"
PLAIN_FILE="$BACKUP_DIR/uniflowpeople_${TIMESTAMP}.dump"
ENCRYPTED_FILE="${PLAIN_FILE}.enc"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

cleanup() {
  rm -f "$PLAIN_FILE"
}
trap cleanup EXIT

echo "Gerando backup PostgreSQL no formato custom..."
pg_dump \
  --dbname="$DATABASE_PUBLIC_URL" \
  --format=custom \
  --compress=9 \
  --no-owner \
  --no-privileges \
  --file="$PLAIN_FILE"

test -s "$PLAIN_FILE" || {
  echo "Erro: o arquivo de backup foi criado vazio." >&2
  exit 1
}

echo "Criptografando backup com AES-256-GCM compatível via OpenSSL..."
openssl enc \
  -aes-256-cbc \
  -salt \
  -pbkdf2 \
  -iter 200000 \
  -md sha256 \
  -in "$PLAIN_FILE" \
  -out "$ENCRYPTED_FILE" \
  -pass env:BACKUP_ENCRYPTION_PASSWORD

chmod 600 "$ENCRYPTED_FILE"
test -s "$ENCRYPTED_FILE" || {
  echo "Erro: o arquivo criptografado foi criado vazio." >&2
  exit 1
}

sha256sum "$ENCRYPTED_FILE" > "${ENCRYPTED_FILE}.sha256"
rm -f "${ENCRYPTED_FILE}.sha256" # checksum é usado apenas na validação local; não expor metadados extras

FILE_SIZE="$(du -h "$ENCRYPTED_FILE" | cut -f1)"
echo "Backup concluído: $(basename "$ENCRYPTED_FILE") ($FILE_SIZE)"
