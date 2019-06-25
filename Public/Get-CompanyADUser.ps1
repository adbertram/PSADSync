function Get-CompanyAdUser {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMatchMap,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldSyncMap
	)
	begin {
		$ErrorActionPreference = 'Stop'
	}
	process {
		try {
			$userSyncProperties = [array]($FieldSyncMap.Values)
			@($FieldMatchMap.GetEnumerator()).foreach({
					if ($_.Value -is 'scriptblock') {
						$userSyncProperties += ParseScriptBlockHeaders -FieldScriptBlock $_.Value | Select-Object -Unique
					} else {
						$userSyncProperties += $_.Value
					}
				})

			$userIdProperties = [array]($FieldMatchMap.Values)

			@(Get-AdUser -Filter 'Enabled -eq $true' -Properties '*').where({
					$adUser = $_
					## Ensure at least one ID field is populated
					@($userIdProperties).where({ $adUser.($_) })
				})
		} catch {
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}