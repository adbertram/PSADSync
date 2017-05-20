try {
	$ErrorActionPreference = 'Stop'

	## Update module version in manifest
	$manifestFilePath = "$env:APPVEYOR_BUILD_FOLDER\PSADSync.psd1"

	$manifestKeys = @{
		ModuleVersion = $env:APPVEYOR_BUILD_VERSION
		FunctionsToExport = 'Invoke-AdSync'
	}
	
	$updateParams = @{
		Path = $manifestFilePath
		OutputPath = $manifestFilePath
	}

	$manifestKeys.GetEnumerator() | foreach {
		$updateParams.$_.Key = $_.Value
		Update-ModuleManifest @updateParams
	}

	## Publish module to PowerShell Gallery
	Publish-Module -Path $env:APPVEYOR_BUILD_FOLDER -NuGetApiKey $env:nuget_apikey -Confirm:$false

} catch {
	throw $_.Exception.Message
}