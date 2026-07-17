# settings.ps1
# Populate environment variables used by scripts for the current session.
# Dot-source to load them into this session: . $PSScriptRoot\settings.ps1
# To persist for new shells, use: setx REMOTE_SERVER "value" (new shells only)

$env:REMOTE_SERVER   = "mydatabase.database.windows.net,1433"
$env:REMOTE_DATABASE = "MyDatabase"
$env:REMOTE_USER     = "remote_user"
$env:REMOTE_PASSWORD = "remote_password"

$env:LOCAL_SERVER    = "127.0.0.1\MYSQLSVR"

if ([string]::IsNullOrEmpty($env:LOCAL_DATABASE)) {
    $env:LOCAL_DATABASE = $env:REMOTE_DATABASE
}
$env:LOCAL_USER     = $env:REMOTE_USER
$env:LOCAL_PASSWORD = $env:REMOTE_PASSWORD


