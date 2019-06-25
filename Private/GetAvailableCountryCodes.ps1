# .ExternalHelp PSADSync-Help.xml
function Get-AvailableCountryCodes {
	[OutputType('pscustomobject')]
	[CmdletBinding()]
	param
	()

	$ErrorActionPreference = 'Stop'

	$countryCodes = Import-PowerShellDataFile -Path "$PSScriptRoot\CountryCodeMap.psd1"
	$countryCodes.Countries
	
}

function TestIsValidAdAttribute {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Name
	)

	if ($Name -in (Get-AvailableAdUserAttribute).ValidName) {
		$true
	} else {
		$false
	}
}