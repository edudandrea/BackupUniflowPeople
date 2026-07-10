#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Uso: BACKUP_ENCRYPTION_PASSWORD='senha' DATABASE_URL_DESTINO='postgresql://...' bash scripts/restore.sh arquivo.dump.enc"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

: "${BACKUP_ENCRYPTION_PASSWORD:?Defina BACKUP_ENCRYPTION_PASSWORD}"
: "${DATABASE_URL_DESTINO:?Defina DATABASE_URL_DESTINO}"

command -v openssl >/dev/null 2>&1 || { echo "openssl não encontrado." >&2; exit 1; }
command -v pg_restore >/dev/null 2>&1 || { echo "pg_restore não encontrado." >&2; exit 1; }

ENCRYPTED_FILE="$1"
[[ -f "$ENCRYPTED_FILE" ]] || { echo "Arquivo não encontrado: $ENCRYPTED_FILE" >&2; exit 1; }

TEMP_DUMP="$(mktemp --suffix=.dump)"
cleanup() {
  rm -f "$TEMP_DUMP"
}
trap cleanup EXIT

openssl enc \
  -d \
  -aes-256-cbc \
  -pbkdf2 \
  -iter 200000 \
  -md sha256 \
  -in "$ENCRYPTED_FILE" \
  -out "$TEMP_DUMP" \
  -pass env:BACKUP_ENCRYPTION_PASSWORD

echo "Validando conteúdo do backup..."
pg_restore --list "$TEMP_DUMP" >/dev/null

echo "Restaurando no banco de destino..."
pg_restore \
  --dbname="$DATABASE_URL_DESTINO" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  "$TEMP_DUMP"

echo "Restauração concluída com sucesso."
