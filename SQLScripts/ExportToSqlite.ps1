# Script to export local SQL Server database to SQLite
# Requires System.Data.SqlClient and System.Data.SQLite

# Configuration
if (Test-Path "$PSScriptRoot\settings.ps1") {
    . "$PSScriptRoot\settings.ps1"
}


if($true) # Set to $false to use local db
{
    # Read configuration from environment variables
    $remoteServer   = $env:REMOTE_SERVER
    $remoteDatabase = $env:REMOTE_DATABASE
    $remoteUser     = $env:REMOTE_USER
    $remotePassword = $env:REMOTE_PASSWORD



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
    $sqlConnString = "Server=$remoteServer;Database=$remoteDatabase;User Id=$remoteUser;Password=$remotePassword;TrustServerCertificate=True;"

    $outputFile = "$remoteDatabase_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
}
else
{
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
    $sqlConnString = "Server=$localServer;Database=$localDatabase;User Id=$localUser;Password=$localPassword;TrustServerCertificate=True;"


    $outputFile = "$localDatabase_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
}
$outputPath = Join-Path $PSScriptRoot $outputFile

Write-Host "Starting export from SQL Server to SQLite..." -ForegroundColor Green

# Load required assemblies
Add-Type -Path "C:\Windows\Microsoft.NET\assembly\GAC_MSIL\System.Data.SqlClient\v4.0_4.0.0.0__b03f5f7f11d50a3a\System.Data.SqlClient.dll" -ErrorAction SilentlyContinue

# Check if SQLite is available
$sqlitePaths = @(
    "${env:ProgramFiles}\System.Data.SQLite\bin\System.Data.SQLite.dll",
    "${env:ProgramFiles(x86)}\System.Data.SQLite\bin\System.Data.SQLite.dll"
)

$sqliteDll = $null
foreach ($path in $sqlitePaths) {
    if (Test-Path $path) {
        $sqliteDll = $path
        break
    }
}

if ($null -eq $sqliteDll) {
    Write-Error "System.Data.SQLite not found. Please install SQLite from https://system.data.sqlite.org/"
    Write-Host "Alternative: Use 'dotnet tool install --global dotnet-sqlite' and use that tool instead."
    exit 1
}

Add-Type -Path $sqliteDll

# Connection strings
$sqlConnString = "Server=$sqlServer;Database=$sqlDatabase;User Id=$sqlUser;Password=$sqlPassword;TrustServerCertificate=True;"
$sqliteConnString = "Data Source=$outputPath;Version=3;"

# Create SQLite database
Write-Host "Creating SQLite database..." -ForegroundColor Cyan
$sqliteConn = New-Object System.Data.SQLite.SQLiteConnection($sqliteConnString)
$sqliteConn.Open()

# Get list of tables from SQL Server
Write-Host "Getting table list from SQL Server..." -ForegroundColor Cyan
$sqlConn = New-Object System.Data.SqlClient.SqlConnection($sqlConnString)
$sqlConn.Open()

$tablesQuery = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME"
$tablesCmd = New-Object System.Data.SqlClient.SqlCommand($tablesQuery, $sqlConn)
$tablesReader = $tablesCmd.ExecuteReader()

$tables = @()
while ($tablesReader.Read()) {
    $tables += $tablesReader["TABLE_NAME"]
}
$tablesReader.Close()

Write-Host "Found $($tables.Count) tables to export" -ForegroundColor Yellow

# Export each table
foreach ($table in $tables) {
    Write-Host "Exporting table: $table" -ForegroundColor Cyan
    
    # Get table schema from SQL Server
    $schemaQuery = @"
        SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = '$table'
        ORDER BY ORDINAL_POSITION
"@
    $schemaCmd = New-Object System.Data.SqlClient.SqlCommand($schemaQuery, $sqlConn)
    $schemaReader = $schemaCmd.ExecuteReader()
    
    $columns = @()
    $columnTypes = @{}
    while ($schemaReader.Read()) {
        $colName = $schemaReader["COLUMN_NAME"]
        $dataType = $schemaReader["DATA_TYPE"]
        $maxLength = $schemaReader["CHARACTER_MAXIMUM_LENGTH"]
        $columns += $colName
        
        # Map SQL Server types to SQLite types
        $sqliteType = switch ($dataType) {
            "int" { "INTEGER" }
            "bigint" { "INTEGER" }
            "smallint" { "INTEGER" }
            "tinyint" { "INTEGER" }
            "bit" { "INTEGER" }
            "decimal" { "REAL" }
            "numeric" { "REAL" }
            "float" { "REAL" }
            "real" { "REAL" }
            "datetime" { "TEXT" }
            "datetime2" { "TEXT" }
            "date" { "TEXT" }
            "time" { "TEXT" }
            "char" { "TEXT" }
            "varchar" { "TEXT" }
            "nchar" { "TEXT" }
            "nvarchar" { "TEXT" }
            "text" { "TEXT" }
            "ntext" { "TEXT" }
            "uniqueidentifier" { "TEXT" }
            default { "TEXT" }
        }
        $columnTypes[$colName] = $sqliteType
    }
    $schemaReader.Close()
    
    # Create table in SQLite
    $columnDefs = @()
    foreach ($col in $columns) {
        $columnDefs += "[$col] $($columnTypes[$col])"
    }
    $createTableSql = "CREATE TABLE IF NOT EXISTS [$table] ($($columnDefs -join ', '))"
    
    $createCmd = New-Object System.Data.SQLite.SQLiteCommand($createTableSql, $sqliteConn)
    $createCmd.ExecuteNonQuery() | Out-Null
    
    # Copy data
    $dataQuery = "SELECT * FROM [$table]"
    $dataCmd = New-Object System.Data.SqlClient.SqlCommand($dataQuery, $sqlConn)
    $dataReader = $dataCmd.ExecuteReader()
    
    $columnList = $columns -join ', '
    $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
    
    $insertSql = "INSERT INTO [$table] ($columnList) VALUES ($paramList)"
    
    $rowCount = 0
    while ($dataReader.Read()) {
        $insertCmd = New-Object System.Data.SQLite.SQLiteCommand($insertSql, $sqliteConn)
        
        foreach ($col in $columns) {
            $value = $dataReader[$col]
            if ($value -eq [System.DBNull]::Value) {
                $value = [System.DBNull]::Value
            }
            $param = $insertCmd.Parameters.AddWithValue("@$col", $value)
        }
        
        $insertCmd.ExecuteNonQuery() | Out-Null
        $rowCount++
    }
    $dataReader.Close()
    
    Write-Host "  Exported $rowCount rows" -ForegroundColor Gray
}

# Cleanup
$sqlConn.Close()
$sqliteConn.Close()

Write-Host "Export completed successfully!" -ForegroundColor Green
Write-Host "SQLite database created at: $outputPath" -ForegroundColor Yellow
