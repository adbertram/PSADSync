try {
	$ErrorActionPreference = 'Stop'

	## Update module version in manifest
	$manifestFilePath = "$env:APPVEYOR_BUILD_FOLDER\PSADSync.psd1"
	$manifestContent = Get-Content -Path $manifestFilePath 

	## Update the module version based on the build version and limit exported functions
	$replacements = @{
		"ModuleVersion = '.*'" = "ModuleVersion = '$env:APPVEYOR_BUILD_VERSION'"
		"FunctionsToExport = '\*'" = "FunctionsToExport = 'Invoke-AdSync'"
	}		

	$replacements.GetEnumerator() | foreach {
		$manifestContent = $manifestContent -replace $_.Key,$_.Value
	}

	$manifestContent | Set-Content -Path $manifestFilePath

	## Publish module to PowerShell Gallery
	Publish-Module -Path $env:APPVEYOR_BUILD_FOLDER -NuGetApiKey $env:nuget_apikey

} catch {
	throw $_.Exception.Message
}