$ErrorActionPreference = 'Stop'

try {

	## Update the module version based on the build version and limit exported functions
	$replacements = @{
		"ModuleVersion = '.*'" = "ModuleVersion = '$env:APPVEYOR_BUILD_VERSION'"
		"FunctionsToExport = '\*'" = "FunctionsToExport = 'Invoke-AdSync'"
	}		

	$replacements.GetEnumerator() | foreach {
		$manifestContent -replace $_.Key,$_.Value
	}

	$manifestContent | Set-Content -Path $manifestFilePath

} catch {
	$host.SetShouldExit($LastExitCode)
}