function FindAttributeMismatch {
	[OutputType([hashtable])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		$AdUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldSyncMap,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser
	)

	$ErrorActionPreference = 'Stop'

	Write-Verbose -Message "Starting AD attribute mismatch check..."
	$FieldSyncMap.GetEnumerator().foreach({
			if ($_.Key -is 'scriptblock') {
				$csvFieldName = EvaluateFieldCondition -Condition $_.Key -CsvUser $CsvUser
			} else {
				$csvFieldName = $_.Key
			}
			$adAttribName = $_.Value
		
			$adAttribValue = $AdUser.$adAttribName
			$csvAttribValue = $CsvUser.$csvFieldName
			## Do not return mismatches if either the CSV value or the field is null. The field can be null either when
			## the actual CSV field is null in the file or the expression evaluates to null.
			if ($csvAttribValue -and $csvFieldName) {
				Write-Verbose -Message "Checking CSV field [$($csvFieldName)] / AD field [$($adAttribName)] for mismatches..."
				$adConvertParams = @{
					AttributeName  = $adAttribName
					AttributeValue = $adAttribValue
					Action         = 'Read'
				}

				$adAttribValue = ConvertToSchemaAttributeType @adConvertParams

				$csvConvertParams = @{
					AttributeName  = $csvFieldName
					AttributeValue = $csvAttribValue
					Action         = 'Read'
				}

				$csvAttribValue = ConvertToSchemaAttributeType @csvConvertParams
				Write-Verbose -Message "Comparing AD attribute value [$($adattribValue)] with CSV value [$($csvAttribValue)]..."
			
				## Compare the two property values and return the AD attribute name and value to be synced
				if ($adattribValue -ne $csvAttribValue) {
					@{
						ActiveDirectoryAttribute = @{ $adAttribName = $adattribValue }
						CSVField                 = @{ $csvFieldName = $csvAttribValue }
						ADShouldBe               = @{ $adAttribName = $csvAttribValue }
					}
					Write-Verbose -Message "AD attribute mismatch found on AD attribute: [$($adAttribName)]."
				} else {
					Write-Verbose -Message "AD <--> CSV attribute [$($csvFieldName)] are in sync."
				}
			}
		})
}