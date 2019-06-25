function CleanAdAccountName {
	[OutputType('string')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$AccountName
	)

	$AccountName -replace "'"
	
}