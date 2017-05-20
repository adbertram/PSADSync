try {
	$ErrorActionPreference = 'Stop'

	Write-Host (ls env:\ | Out-String)
	## Update module version in manifest
	$manifestFilePath = "$env:APPVEYOR_BUILD_FOLDER\PSADSync.psd1"
	((Get-Content -Path $manifestFilePath) -replace "ModuleVersion = '.*'","ModuleVersion = '$env:APPVEYOR_BUILD_VERSION'") | Set-Content -Path $manifestFilePath

	## Export only certain functions
	((Get-Content -Path $manifestFilePath) -replace "FunctionsToExport = '\*'","FunctionsToExport = 'Invoke-AdSync'") | Set-Content -Path $manifestFilePath

	## Publish module to PowerShell Gallery
	Publish-Module -Path $env:APPVEYOR_BUILD_FOLDER -NuGetApiKey $env:nuget_apikey

} catch {
	throw $_.Exception.Message
}