function GetPsAdSyncConfiguration {
	[OutputType('hashtable')]
	[CmdletBinding()]
	param
	()

	$parentFolder = $PSScriptRoot | Split-Path -Parent
	Import-PowerShellDataFile -Path (Join-Path -Path $parentFolder -ChildPath 'Configuration.psd1')

}