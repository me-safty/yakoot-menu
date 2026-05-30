param(
	[switch]$Unregister
)

$ErrorActionPreference = "Stop"
$TaskNames = @("YakootCaddy", "YakootPocketBase")

foreach ($TaskName in $TaskNames) {
	Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
	if ($Unregister) {
		Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
	}
}
