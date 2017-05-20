Write-Host 'Installing necessary PowerShell modules...'
$null = Install-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force
$null = Import-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force

$requireModules = @('Pester','ADSIPS')
foreach ($m in $requireModules) {
	Install-Module -Name $m -Force -Confirm:$false
}