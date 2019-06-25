function GetManagerEmailAddress {
	[OutputType('string')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser
	)

	$ErrorActionPreference = 'Stop'

	if ($AdUser.Manager -and ($managerAdAccount = Get-ADUser -Filter "DistinguishedName -eq '$($AdUser.Manager)'" -Properties EmailAddress)) {
		$managerAdAccount.EmailAddress
	}	

}