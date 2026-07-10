# Backup diário do UniFlow People

Backup automatizado do PostgreSQL hospedado no Railway para uma pasta privada do Google Drive.

## Funcionamento

- Execução diária às **02:00 no horário de Brasília** (`05:00 UTC`).
- Execução manual pela aba **Actions** do GitHub.
- Backup PostgreSQL no formato `custom` (`.dump`).
- Criptografia AES-256 antes do envio.
- Upload para uma pasta específica do Google Drive.
- Retenção automática de 30 dias.
- O arquivo não criptografado é removido antes do upload.

## Secrets necessários

No repositório, acesse:

`Settings > Secrets and variables > Actions > New repository secret`

Crie estes secrets:

| Secret | Conteúdo |
|---|---|
| `DATABASE_PUBLIC_URL` | URL pública do PostgreSQL no Railway |
| `BACKUP_ENCRYPTION_PASSWORD` | Senha forte e exclusiva para criptografar e restaurar os backups |
| `