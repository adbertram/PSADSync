function TestShouldCreateNewUser {
	[OutputType('bool')]
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser
	)

	if ((TestIsUserTerminationEnabled) -and (TestUserTerminated -CsvUser $CsvUser)) {
		$false	
	} else {
		if ($csvfield = (GetPsAdSyncConfiguration).NewUserCreation.Exclude.FieldValueSettings.CsvField) {
			$csvValue = (GetPsAdSyncConfiguration).NewUserCreation.Exclude.FieldValueSettings.CsvValue
			if ($CsvUser.$csvField -in $csvValue) {
				$false
			} else {
				$true
			}
		} else {
			$true
		}
	}
}