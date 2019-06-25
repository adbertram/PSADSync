function SendStaleAccountEmail {
	[OutputType([void])]
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$Subject = (GetPsAdSyncConfiguration).Email.Templates.UnusedAccount.Subject,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$FromEmailAddress = (GetPsAdSyncConfiguration).Email.Templates.UnusedAccount.FromEmailAddress,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$FromEmailName = (GetPsAdSyncConfiguration).Email.Templates.UnusedAccount.FromEmailName,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$SmtpServer = (GetPsAdSyncConfiguration).Email.SmtpServer

	)
	begin {
		$ErrorActionPreference = 'Stop'
	}
	process {
		try {
			if (-not $AdUser.Manager) {
				throw "No manager defined for user: [$($AdUser.name)]. Cannot send email."
			}
			if (-not ($managerEmail = GetManagerEmailAddress -AdUser $AdUser)) {
				throw "Could not find a manager email address for user [$($AdUser.Name)]"
			}
			$emailBody = ReadEmailTemplate -Name UnusedSccount
			$emailBody = $emailBody -f $managerEmail, $AdUser.Name, (GetPsAdSyncConfiguration).CompanyName

			$sendParams = @{
				To         = $managerEmail
				From       = "$FromEmailName <$FromEmailAddress>"
				Subject    = $Subject
				Body       = $emailBody
				SmtpServer = $SmtpServer
			}
			if ($PSCmdlet.ShouldProcess($managerEmail, "Send email about account [$($AdUser.Name)]")) {
				Send-MailMessage @sendParams
			}
		} catch {
			$PSCmdlet.ThrowTerminatingError($_)
		}
	}
}