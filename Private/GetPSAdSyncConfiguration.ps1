function GetPsAdSyncConfiguration {
	[OutputType('hashtable')]
	[CmdletBinding()]
	param
	()

	$parentFolder = $PSScriptRoot | Split-Path -Parent
	Import-PowerShellDataFile -Path "$parentFolder\Configuration.psd1"

}