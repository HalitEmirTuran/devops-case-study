$ErrorActionPreference = "Stop"

$SecretsDir = Join-Path $PSScriptRoot "..\secrets"

if (!(Test-Path $SecretsDir)) {
    New-Item -ItemType Directory -Force -Path $SecretsDir | Out-Null
}

$Chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".ToCharArray()
$Password = -join (1..32 | ForEach-Object { $Chars | Get-Random })

Set-Content -Path "$SecretsDir\postgres.db" -Value "petclinic" -NoNewline
Set-Content -Path "$SecretsDir\postgres.user" -Value "petclinic_app" -NoNewline
Set-Content -Path "$SecretsDir\postgres.password" -Value $Password -NoNewline
Set-Content -Path "$SecretsDir\spring.datasource.url" -Value "jdbc:postgresql://postgres:5432/petclinic" -NoNewline

Write-Host "B: Secrets basariyla olusturuldu:: ./secrets"
Write-Host "U: Secrets altinda commitleme!:: ./secrets"