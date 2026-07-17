# settings.sample.ps1 - sample environment-backed settings (NO SECRETS)
# Copy to SQLScripts\settings.ps1 and edit for your environment:
#   cp SQLScripts\settings.sample.ps1 SQLScripts\settings.ps1
#   # then edit SQLScripts\settings.ps1 to set real values (do NOT commit)

$env:REMOTE_SERVER   = "mydb.database.windows.net,1433"
$env:REMOTE_DATABASE = "MyDatabase"
$env:REMOTE_USER     = "remote_user"
$env:REMOTE_PASSWORD = "REPLACE_WITH_SECRET"

$env:LOCAL_SERVER    = "127.0.0.1\\MYSQLSVR"
# default local DB to remote DB if not set
if ([string]::IsNullOrEmpty($env:LOCAL_DATABASE)) {
	$env:LOCAL_DATABASE = $env:REMOTE_DATABASE
}
$env:LOCAL_USER      = $env:LOCAL_USER
$env:LOCAL_PASSWORD  = "REPLACE_WITH_SECRET"