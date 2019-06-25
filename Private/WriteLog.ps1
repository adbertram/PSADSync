function WriteLog {
	[OutputType([void])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$FilePath = "$PSScriptRoot\PSAdSync.csv",

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierField,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierValue,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Attributes,

		[Parameter()]
		[switch]$Overwrite
	)
	
	$ErrorActionPreference = 'Stop'
	
	$time = Get-Date -Format 'g'
	$Attributes['CsvIdentifierValue'] = $CsvIdentifierValue
	$Attributes['CsvIdentifierField'] = $CsvIdentifierField
	$Attributes['Time'] = $time
	
	if (!($Overwrite)) {
		([pscustomobject]$Attributes) | Export-Csv -Path $FilePath -Append -NoTypeInformation -Confirm:$false
	} else {
		([pscustomobject]$Attributes) | Export-Csv -Path $FilePath -NoTypeInformation -Confirm:$false
	}
}