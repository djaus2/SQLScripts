# Simple script to export SQL Server data to SQL scripts that can be imported into SQLite
# Generates a .sql file with CREATE TABLE and INSERT statements

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

Write-Host "Starting export from SQL Server to SQL script..." -ForegroundColor Green

# Connection string: Default Remote. Switch for LOCAL_DATABASE

# Connect to SQL Server
$sqlConn = New-Object System.Data.SqlClient.SqlConnection($sqlConnString)
$sqlConn.Open()

# Get list of tables
$tablesQuery = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME"
$tablesCmd = New-Object System.Data.SqlClient.SqlCommand($tablesQuery, $sqlConn)
$tablesReader = $tablesCmd.ExecuteReader()

$tables = @()
while ($tablesReader.Read()) {
    $tables += $tablesReader["TABLE_NAME"]
}
$tablesReader.Close()

Write-Host "Found $($tables.Count) tables to export" -ForegroundColor Yellow

# Create output file
$sqlContent = @()
$sqlContent += "-- SQL Server to SQLite Export"
$sqlContent += "-- Generated: $(Get-Date)"
$sqlContent += ""

# Export each table
foreach ($table in $tables) {
    Write-Host "Exporting table: $table" -ForegroundColor Cyan
    
    # Get table schema
    $schemaQuery = @"
        SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH, COLUMNPROPERTY(object_id(TABLE_NAME), COLUMN_NAME, 'IsIdentity') as IsIdentity
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = '$table'
        ORDER BY ORDINAL_POSITION
"@
    $schemaCmd = New-Object System.Data.SqlClient.SqlCommand($schemaQuery, $sqlConn)
    $schemaReader = $schemaCmd.ExecuteReader()
    
    $columns = @()
    $columnTypes = @{}
    $identityColumn = $null
    
    while ($schemaReader.Read()) {
        $colName = $schemaReader["COLUMN_NAME"]
        $dataType = $schemaReader["DATA_TYPE"]
        $isIdentity = $schemaReader["IsIdentity"]
        
        $columns += $colName
        
        if ($isIdentity -eq 1) {
            $identityColumn = $colName
        }
        
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
    
    # Create table statement
    $columnDefs = @()
    foreach ($col in $columns) {
        $def = "[$col] $($columnTypes[$col])"
        if ($col -eq $identityColumn) {
            $def += " PRIMARY KEY AUTOINCREMENT"
        }
        $columnDefs += $def
    }
    
    $sqlContent += "DROP TABLE IF EXISTS [$table];"
    $sqlContent += "CREATE TABLE [$table] ($($columnDefs -join ', '));"
    $sqlContent += ""
    
    # Export data
    $dataQuery = "SELECT * FROM [$table]"
    $dataCmd = New-Object System.Data.SqlClient.SqlCommand($dataQuery, $sqlConn)
    $dataReader = $dataCmd.ExecuteReader()
    
    $rowCount = 0
    while ($dataReader.Read()) {
        $values = @()
        foreach ($col in $columns) {
            $value = $dataReader[$col]
            if ($value -eq [System.DBNull]::Value) {
                $values += "NULL"
            }
            elseif ($columnTypes[$col] -eq "INTEGER" -or $columnTypes[$col] -eq "REAL") {
                $values += $value
            }
            else {
                # Escape single quotes by doubling them
                $escapedValue = $value.ToString().Replace("'", "''")
                $values += "'$escapedValue'"
            }
        }
        
        $insertSql = "INSERT INTO [$table] ($($columns -join ', ')) VALUES ($($values -join ', '));"
        $sqlContent += $insertSql
        $rowCount++
        
        # Write in batches to avoid memory issues
        if ($rowCount % 1000 -eq 0) {
            $sqlContent | Out-File -FilePath $outputPath -Encoding UTF8 -Append
            $sqlContent = @()
        }
    }
    $dataReader.Close()
    
    # Write remaining content
    if ($sqlContent.Count -gt 0) {
        $sqlContent | Out-File -FilePath $outputPath -Encoding UTF8 -Append
        $sqlContent = @()
    }
    
    Write-Host "  Exported $rowCount rows" -ForegroundColor Gray
}

# Cleanup
$sqlConn.Close()

Write-Host "Export completed successfully!" -ForegroundColor Green
Write-Host "SQL script created at: $outputPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "To import into SQLite:" -ForegroundColor Cyan
Write-Host "  sqlite3 output.db < $outputFile" -ForegroundColor Yellow
