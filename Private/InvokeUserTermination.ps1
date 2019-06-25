function InvokeUserTermination {
	[OutputType('void')]
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[scriptblock]$UserTerminationAction
	)

	switch ((GetPsAdSyncConfiguration).UserTermination.Action) {
		'Disable' {
			if ($PSCmdlet.ShouldProcess("AD User [$($AdUser.Name)]", 'Disable')) {
				Disable-AdAccount -Identity $AdUser.samAccountName -Confirm:$false	
			}
		}
		'Custom' {
			if (-not $PSBoundParameters.ContainsKey('UserTerminationAction')) {
				throw 'Custom user termination action chosen in configuration but no custom action was specified.'
			}
			& $
		}
		default {
			throw "Unrecognized user termination action: [$_]"
		}
	}
	
}