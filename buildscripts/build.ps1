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

	## Publish module to PowerShell Gallery
	Publish-Module -Path $env:APPVEYOR_BUILD_FOLDER -NuGetApiKey $env:nuget_apikey -Confirm:$false

} catch {
	$host.SetShouldExit($LastExitCode)
}