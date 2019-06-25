function FindUserMatch {
	[OutputType([pscustomobject])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMatchMap,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser,

		[Parameter()]
		[object[]]$AdUsers = $script:adUsers
	)
	$ErrorActionPreference = 'Stop'

	<# Possibilities
		$FieldMatchMap = @{ 
			@( { if ($_.'NICK_NAME') { 'NICK_NAME' } else { $_.'FIRST_NAME' }}, 'LAST_NAME' )
			@( 'givenName','surName' )
		}

		@($AdUsers).where({ $_.givenName -eq 'nick' -and $_.surName -eq 'last' })

		$FieldMatchMap = @{ 
			@( 'FIRST_NAME', 'LAST_NAME' )
			@( 'givenName', 'surName' )
		}

		@($AdUsers).where({ $_.givenName -eq 'first' -and $_.surName -eq 'last' })

		$CsvUser = [pscustomobject]@{
			NICK_NAME = 'nick'
			FIRST_NAME = 'first'
			LAST_NAME = 'last'
		}

	#>

	$whereFilterElements = @()

	## TODO: Why is Select-Object necessary here?
	[string[]]$fieldVals = $FieldMatchmap.Values | Select-Object
	$fieldKeys = @()

	$i = 0
	$FieldMatchMap.Keys.foreach({
			## @( { if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME'} },'LAST_NAME')
	
			foreach ($k in $_) {
				if ($k -is 'scriptblock') {
					## { if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME'} }

					## 'NICK_NAME'
					$csvProp = EvaluateFieldCondition -Condition $k -CsvUser $CsvUser

				} else {
					$csvProp = $k
				}
				$fieldKeys += $csvProp

				## 'Joel'
				if ($value = $CsvUser.$csvProp) {
					$adProp = $fieldVals[$i]

					$whereFilterElements += '$_.{0} -eq "{1}"' -f $adProp, $value
				}
				$i++

			}
		})

	if (@($FieldMatchMap.Keys).Count -gt 1) {
		$whereFilter = [scriptblock]::Create($whereFilterElements -join ' -or ')
	} else {
		$whereFilter = [scriptblock]::Create($whereFilterElements -join ' -and ')
	}
	if ($adUserMatch = @($AdUsers).where($whereFilter)) {
		if (@($adUserMatch).Count -gt 1) {
			Write-Warning -Message 'More than one AD user found to match found. Skipping user...'
		} else {
			[pscustomobject]@{
				MatchedAdUser        = $adUserMatch
				CSVAttemptedMatchIds = ($fieldKeys -join ',')
				ADAttemptedMatchIds  = ($fieldVals -join ',')
			}
		}
		
	} else {
		Write-Verbose -Message 'No user match found for CSV user'
	}
}