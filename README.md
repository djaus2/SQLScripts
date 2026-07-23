# SQLScripts

## About
Some scripts for backing up/duplicating a SQL Server database, including tools to export to SQLite.

> These versions of scripts are parameterised versions of original scripts that were used. Settings communicated here through env settings. These versions not yet tested. _{Later)_

## Reference

[SQL Server Database Export/Import Guide blog post](https://davidjones.sportronics.com.au/db/SQL_Server-Database_Export-Import_Guide-db.html)

## Directory
- `SQLScripts/`
  - `settings.sample.ps1` — Sample environment-backed settings. Copy to `settings.ps1` and edit for local use.
  - `settings.ps1` — (Local) environment settings. Do NOT commit secrets; this file should be in `.gitignore`.
  - `BackupRemoteToLocal.ps1` — Export an Azure SQL database to a .bacpac and import into a local SQL Server instance.
  - `ExportToSqlite.ps1` — Export tables from SQL Server into a .sql file suitable for importing into SQLite.
  - `ExportToSqliteSimple.ps1` — Export tables from SQL Server into a .sql file suitable and complete importing into SQLite using the file.
## Usage
1. Populate environment variables for the current session:
   - `. $PSScriptRoot\SQLScripts\settings.ps1`
2. Run a script:
   - `pwsh .\SQLScripts\BackupRemoteToLocal.ps1`
   - `pwsh .\SQLScripts\ExportToSqliteSimple.ps1`

## Security
Do not commit `settings.ps1` with real credentials. Edit copy of `settings.sample.ps1`  in the repo as  `settings.ps1`  and add `SQLScripts/settings.ps1` to `.gitignore`.
