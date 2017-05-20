$ErrorActionPreference = 'Stop'

try {
	## Don't upload the build scripts to PowerShell Gallery
	$moduleFolderPath = "$env:APPVEYOR_BUILD_FOLDER\Module"
	$null = mkdir $moduleFolderPath
	Get-ChildItem -Path $env:APPVEYOR_BUILD_FOLDER -Filter '*.ps*' | Copy-Item -Destination $moduleFolderPath

	## Publish module to PowerShell Gallery
	Publish-Module -Path $moduleFolderPath -NuGetApiKey $env:nuget_apikey -Confirm:$false

} catch {
	$host.SetShouldExit($LastExitCode)
}