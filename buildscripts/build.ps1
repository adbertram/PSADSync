$ErrorActionPreference = 'Stop'

try {

	## Update module version in manifest
	$manifestFilePath = "$env:APPVEYOR_BUILD_FOLDER\PSADSync.psd1"

	$updateParams = @{
		Path = $manifestFilePath
		OutputPath = $manifestFilePath
		ModuleVersion = $env:APPVEYOR_BUILD_VERSION
		FunctionsToExport = 'Invoke-AdSync'
	}
	Update-ModuleManifest @updateParams

	## Don't upload the build scripts to PowerShell Gallery
	$moduleFolderPath = "$env:APPVEYOR_BUILD_FOLDER\Module"
	$null = mkdir $moduleFolderPath
	Get-ChildItem -Path $env:APPVEYOR_BUILD_FOLDER -Filter '*.ps*' | where { -not $_.PSIsContainer } | Copy-Item -Destination $moduleFolderPath

	## Publish module to PowerShell Gallery
	Publish-Module -Path $moduleFolderPath -NuGetApiKey $env:nuget_apikey -Confirm:$false

} catch {
	$host.SetShouldExit($LastExitCode)
}