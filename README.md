# Backup diário do UniFlow People

Backup automatizado do PostgreSQL hospedado no Railway para uma pasta privada do Google Drive, executado integralmente pelo GitHub Actions.

## O que o projeto faz

- Executa diariamente às **02:00 no horário de Brasília** (`05:00 UTC`).
- Permite execução manual pela aba **Actions**.
- Gera o backup PostgreSQL no formato `custom` (`.dump`).
- Remove proprietário e privilégios para facilitar a restauração em outro servidor.
- Criptografa o arquivo com AES-256, PBKDF2 e 200.000 iterações.
- Envia somente o arquivo criptografado para o Google Drive.
- Exclui automaticamente backups remotos com mais de 30 dias.
- Apaga arquivos temporários e credenciais do runner ao final.

## Estrutura

```text
.github/workflows/backup.yml  Workflow diário
scripts/backup.sh             Geração e criptografia
scripts/restore.sh            Descriptografia e restauração
config/rclone.conf.example    Exemplo sem credenciais
.gitignore                    Proteção contra commit de segredos e backups
```

## 1. Obter a URL pública do PostgreSQL no Railway

No projeto do Railway:

1. Abra o serviço PostgreSQL.
2. Acesse **Variables** ou **Connect**.
3. Copie a URL pública, normalmente apresentada como `DATABASE_PUBLIC_URL`.
4. A URL deve começar com `postgresql://` ou `postgres://`.

O GitHub Actions executa fora da rede privada do Railway, portanto não pode utilizar a URL interna `postgres.railway.internal`.

## 2. Configurar o rclone com o Google Drive

Esta etapa é feita uma única vez em um computador para autorizar a conta Google. Depois disso, os backups são executados na nuvem e o computador pode permanecer desligado.

### Windows

1. Instale o rclone pelo site oficial ou com Winget:

```powershell
winget install Rclone.Rclone
```

2. Execute:

```powershell
rclone config
```

3. Escolha as opções:

```text
n                  Novo remote
name               gdrive
Storage            drive (Google Drive)
client_id          Enter
client_secret      Enter
scope              1 (acesso completo)
root_folder_id     Enter
service_account    Enter
Edit advanced      n
Use web browser    y
```

4. Faça login na conta Google que armazenará os backups.

5. Confirme que o remote funciona:

```powershell
rclone lsd gdrive:
```

6. Descubra o local do arquivo de configuração:

```powershell
rclone config file
```

Normalmente ele fica em:

```text
C:\Users\SEU_USUARIO\AppData\Roaming\rclone\rclone.conf
```

## 3. Converter a configuração do rclone para Base64

No PowerShell, ajuste o caminho e execute:

```powershell
$path = "$env:APPDATA\rclone\rclone.conf"
[Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Set-Clipboard
```

O conteúdo Base64 ficará na área de transferência. Não publique nem envie esse valor por mensagem, pois ele contém o token de acesso ao Google Drive.

## 4. Criar os GitHub Secrets

No repositório, acesse:

```text
Settings > Secrets and variables > Actions > New repository secret
```

Crie exatamente estes secrets:

| Secret | Conteúdo |
|---|---|
| `DATABASE_PUBLIC_URL` | URL pública do PostgreSQL no Railway |
| `BACKUP_ENCRYPTION_PASSWORD` | Senha forte e exclusiva para criptografar/restaurar |
| `RCLONE_CONFIG_BASE64` | Conteúdo Base64 do `rclone.conf` |

### Recomendação para a senha de criptografia

Use uma senha aleatória com pelo menos 32 caracteres e guarde-a em um gerenciador de senhas. Sem essa senha, o backup não poderá ser restaurado.

Exemplo para gerar uma senha no PowerShell:

```powershell
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 40 | ForEach-Object {[char]$_})
```

## 5. Executar o primeiro teste

1. Abra a aba **Actions** no repositório.
2. Selecione **Backup diário PostgreSQL**.
3. Clique em **Run workflow**.
4. Aguarde a conclusão do job **Gerar e enviar backup**.
5. Confirme no Google Drive a criação da pasta:

```text
UniFlowPeople-Backups
```

O arquivo terá um nome semelhante a:

```text
uniflowpeople_2026-07-10_02-00-00.dump.enc
```

## Agendamento

O GitHub Actions utiliza UTC. O cron configurado é:

```yaml
cron: '0 5 * * *'
```

Isso corresponde a **02:00 em Brasília** enquanto o fuso for UTC-3.

## Política de retenção

O workflow mantém os backups por 30 dias. Para alterar, edite no arquivo `.github/workflows/backup.yml`:

```yaml
RETENTION_DAYS: '30'
```

## Restaurar um backup

> Faça a restauração primeiro em um banco de teste. O script utiliza `--clean --if-exists` e pode substituir objetos existentes no banco de destino.

### Linux, WSL ou Git Bash

Baixe o arquivo `.dump.enc` do Google Drive e execute:

```bash
export BACKUP_ENCRYPTION_PASSWORD='SUA_SENHA'
export DATABASE_URL_DESTINO='postgresql://usuario:senha@host:porta/banco'
bash scripts/restore.sh uniflowpeople_2026-07-10_02-00-00.dump.enc
```

É necessário ter `openssl` e o cliente PostgreSQL (`pg_restore`) instalados.

### Descriptografar manualmente

```bash
openssl enc -d \
  -aes-256-cbc \
  -pbkdf2 \
  -iter 200000 \
  -md sha256 \
  -in backup.dump.enc \
  -out backup.dump \
  -pass env:BACKUP_ENCRYPTION_PASSWORD
```

Depois:

```bash
pg_restore \
  --dbname="$DATABASE_URL_DESTINO" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  backup.dump
```

## Segurança

- Nunca salve a URL do banco, senha de criptografia ou `rclone.conf` no repositório.
- O repositório pode ser público, mas os GitHub Secrets não ficam visíveis no código ou nos logs.
- Restrinja o acesso administrativo ao GitHub e ao Google Drive com autenticação em dois fatores.
- Teste uma restauração pelo menos uma vez por mês.
- Mantenha a senha de criptografia em local separado do Google Drive e do GitHub.
- Revogue o token do rclone imediatamente caso ele seja exposto.

## Diagnóstico de erros

### `connection refused` ou timeout

Confirme que o secret `DATABASE_PUBLIC_URL` usa o host e a porta públicos do Railway, e não `railway.internal`.

### `password authentication failed`

Copie novamente a URL pública do Railway. Senhas com caracteres especiais já devem estar codificadas na URL fornecida pela plataforma.

### `Secret RCLONE_CONFIG_BASE64 não configurado`

Crie o secret com o conteúdo Base64 completo do arquivo `rclone.conf`.

### `couldn't find root directory ID`

Refaça a autorização com `rclone config` e teste localmente com `rclone lsd gdrive:` antes de atualizar o secret.

### Backup criado, mas arquivo não aparece no Drive

Abra os logs do passo **Upload para Google Drive** na execução do GitHub Actions. Confirme também que o remote no arquivo se chama exatamente `gdrive`.
