$ErrorActionPreference = 'Stop'

## To silence the progress bar for Publish-Module
$ProgressPreference = 'SilentlyContinue'

try {
	$null = Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.208' -Force -Verbose

	Import-Module -Name PowerShellGet

	## Don't upload the build scripts to PowerShell Gallery
	$moduleFolderPath = "$env:APPVEYOR_BUILD_FOLDER\PSADSync"
	$null = mkdir $moduleFolderPath
	Get-ChildItem -Path $env:APPVEYOR_BUILD_FOLDER -Filter '*.ps*' | Copy-Item -Destination $moduleFolderPath

	## Publish module to PowerShell Gallery
	$publishParams = @{
		Path = $moduleFolderPath
		NuGetApiKey = $env:nuget_apikey
		Confirm = $false
		Verbose = $true
	}
	Write-Host ($publishParams | Out-String)
	Publish-Module @publishParams

} catch {
	$host.SetShouldExit($LastExitCode)
}