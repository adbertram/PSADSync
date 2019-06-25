function GetPsAdSyncConfiguration {
	[OutputType('hashtable')]
	[CmdletBinding()]
	param
	()

	Import-PowerShellDataFile -Path "$PSScriptRoot\Configuration.psd1"

}