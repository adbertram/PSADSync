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