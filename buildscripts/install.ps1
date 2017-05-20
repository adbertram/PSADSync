Write-Host 'Installing necessary PowerShell modules...'
$null = Install-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force
$null = Import-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force

$requiredModules = @('Pester','ADSIPS')
foreach ($m in $requiredModules) {
	Install-Module -Name $m -Force -Confirm:$false
}