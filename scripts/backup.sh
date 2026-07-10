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
require_command openssl

PG_DUMP_BIN="${PG_DUMP_BIN:-/usr/lib/postgresql/18/bin/pg_dump}"
if [[ ! -x "$PG_DUMP_BIN" ]]; then
  echo "Erro: pg_dump 18 não encontrado em $PG_DUMP_BIN." >&2
  exit 1
fi

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

echo "Versão utilizada: $($PG_DUMP_BIN --version)"
echo "Gerando backup PostgreSQL no formato custom..."
"$PG_DUMP_BIN" \
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

echo "Criptografando backup com AES-256-CBC, PBKDF2 e SHA-256..."
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

FILE_SIZE="$(du -h "$ENCRYPTED_FILE" | cut -f1)"
echo "Backup concluído: $(basename "$ENCRYPTED_FILE") ($FILE_SIZE)"
