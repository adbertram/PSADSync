function TestUserTerminated {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser
	)

	$csvField = (GetPsAdSyncConfiguration).UserTermination.FieldValueSettings.CsvField
	$csvValue = (GetPsAdSyncConfiguration).UserTermination.FieldValueSettings.CsvValue
	
	if ($CsvUser.$csvField -in $csvValue) {
		$true
	} else {
		$false
	}
}