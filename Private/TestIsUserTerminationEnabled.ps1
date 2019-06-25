function TestIsUserTerminationEnabled {
	[OutputType('bool')]
	[CmdletBinding()]
	param
	()

	if ((GetPsAdSyncConfiguration).UserTermination.Enabled) {
		$true
	} else {
		$false
	}
}