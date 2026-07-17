# BackupRemoteToLocal.ps1 (reads configuration from environment variables)
# Optionally populate env vars for this session:
if (Test-Path "$PSScriptRoot\settings.ps1") {
    . "$PSScriptRoot\settings.ps1"
}

# Read configuration from environment variables
$remoteServer   = $env:REMOTE_SERVER
$remoteDatabase = $env:REMOTE_DATABASE
$remoteUser     = $env:REMOTE_USER
$remotePassword = $env:REMOTE_PASSWORD

$localServer    = $env:LOCAL_SERVER
$localDatabase  = $env:LOCAL_DATABASE
$localUser      = $env:LOCAL_USER
$localPassword  = $env:LOCAL_PASSWORD

# Validate required values
$missing = @()
if (-not $remoteServer)   { $missing += 'REMOTE_SERVER' }
if (-not $remoteDatabase) { $missing += 'REMOTE_DATABASE' }
if (-not $remoteUser)     { $missing += 'REMOTE_USER' }
if (-not $remotePassword) { $missing += 'REMOTE_PASSWORD' }
if ($missing.Count -gt 0) {
    Write-Error ("Missing required environment variables: {0}" -f ($missing -join ', '))
    Write-Host "You can populate them for this session by running: . $PSScriptRoot\settings.ps1" -ForegroundColor Yellow
    exit 1
}

$backupFile = $remoteDatabase + "_$(Get-Date -Format 'yyyyMMdd_HHmmss').bacpac"
$tempPath = $env:TEMP

Write-Host "Starting backup from Azure SQL to local SQL Server..." -ForegroundColor Green

# Find SqlPackage.exe
$sqlPackagePaths = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\18\Enterprise\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
    "${env:ProgramFiles}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
    "${env:ProgramFiles}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
    "${env:ProgramFiles}\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe",
    "${env:ProgramFiles(x86)}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
    "${env:ProgramFiles(x86)}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
    "${env:ProgramFiles(x86)}\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe"
)

$sqlPackage = $null
foreach ($path in $sqlPackagePaths) {
    if (Test-Path $path) {
        $sqlPackage = $path
        break
    }
}

if ($null -eq $sqlPackage) {
    Write-Error "SqlPackage.exe not found. Please install SQL Server Data Tools (SSDT)."
    exit 1
}

Write-Host "Found SqlPackage at: $sqlPackage" -ForegroundColor Yellow

# Step 1: Export from Azure SQL to bacpac file
Write-Host "Step 1: Exporting from Azure SQL to $backupFile..." -ForegroundColor Cyan
$exportArgs = @(
    "/Action:Export",
    "/SourceServerName:$remoteServer",
    "/SourceDatabaseName:$remoteDatabase",
    "/SourceUser:$remoteUser",
    "/SourcePassword:$remotePassword",
    "/TargetFile:$tempPath\$backupFile",
    "/p:CommandTimeout=1200"
)

& $sqlPackage $exportArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Export from Azure SQL failed."
    exit 1
}

Write-Host "Export completed successfully." -ForegroundColor Green

# Step 2: Drop existing local database if it exists
Write-Host "Step 2: Dropping existing local database if exists..." -ForegroundColor Cyan
$dropDbQuery = "IF EXISTS (SELECT name FROM sys.databases WHERE name = '$localDatabase') BEGIN ALTER DATABASE [$localDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$localDatabase]; END"

$dropArgs = @(
    "-S", $localServer,
    "-U", $localUser,
    "-P", $localPassword,
    "-Q", $dropDbQuery,
    "-t", "600"
)

& sqlcmd $dropArgs

# Step 3: Import bacpac to local SQL Server
Write-Host "Step 3: Importing to local SQL Server..." -ForegroundColor Cyan
$targetConnString = "Data Source=$localServer;Initial Catalog=$localDatabase;User ID=$localUser;Password=$localPassword;TrustServerCertificate=True;"

$importArgs = @(
    "/Action:Import",
    "/SourceFile:$tempPath\$backupFile",
    "/TargetConnectionString:$targetConnString",
    "/p:CommandTimeout=1200"
)

& $sqlPackage $importArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Import to local SQL Server failed."
    exit 1
}

Write-Host "Import completed successfully." -ForegroundColor Green

# Cleanup
Write-Host "Step 4: Cleaning up temporary file..." -ForegroundColor Cyan
Remove-Item "$tempPath\$backupFile" -ErrorAction SilentlyContinue

Write-Host "Backup completed successfully! Remote Azure database has been copied to local SQL Server." -ForegroundColor Green
