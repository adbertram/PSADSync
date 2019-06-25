function TestIsUserCreationEnabled {
	[OutputType('bool')]
	[CmdletBinding()]
	param
	()

	(GetPsAdSyncConfiguration).UserCreation.Enabled
}