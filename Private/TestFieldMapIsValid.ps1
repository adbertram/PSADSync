function TestFieldMapIsValid {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory, ParameterSetName = 'Sync')]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldSyncMap,

		[Parameter(Mandatory, ParameterSetName = 'Match')]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMatchMap,

		[Parameter(Mandatory, ParameterSetName = 'Value')]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldValueMap,

		[Parameter(Mandatory, ParameterSetName = 'UserMatch')]
		[ValidateNotNullOrEmpty()]
		[hashtable]$UserMatchMap,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CsvFilePath	
	)

	<#
		FieldSyncMap
		--------------
			Valid: 
				@{ <scriptblock>; <string> }
				@{ { if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME' }} = 'givenName' }

				@{ <string>; <string> }

		FieldMatchMap
		--------------
			Valid: 
				@{ <scriptblock>; <string> }
				@{ <array>; <array> }
				@{ { if ($_.'csvIdField2') { $_.'csvIdField2' } else { $_.'csvIdField3'} } = 'adIdField2' }

				@{ <string>; <string> }

		FieldValueMap
		--------------
			Valid: 
				@{ <string>; <scriptblock> }
				@{ 'SUPERVISOR' = { $supId = $_.'SUPERVISOR_ID'; (Get-AdUser -Filter "EmployeeId -eq '$supId'").DistinguishedName }}
	#>

	if (-not $PSBoundParameters.ContainsKey('CsvFilePath') -and -not $UserMatchMap) {	
		throw 'CSVFilePath is required when testing any map other than UserMatchMap.'
	}

	$result = $true
	switch ($PSCmdlet.ParameterSetName) {
		'Sync' {
			$mapHt = $FieldSyncMap.Clone()
			if ($FieldSyncMap.GetEnumerator().where({ $_.Value -is 'scriptblock' })) {
				Write-Warning -Message 'Scriptblocks are not allowed as a value in FieldSyncMap.'
				$result = $false
			}
		}
		'Match' {
			$mapHt = $FieldMatchMap.Clone()
			if ($FieldMatchMap.GetEnumerator().where({ $_.Value -is 'scriptblock' })) {
				Write-Warning -Message 'Scriptblocks are not allowed as a value in FieldMatchMap.'
				$result = $false
			} elseif ($FieldMatchMap.GetEnumerator().where({ @($_.Key).Count -gt 1 -and @($_.Value).Count -eq 1 })) {
				$result = $false
			}
		}
		'Value' {
			$mapHt = $FieldValueMap.Clone()
			if ($FieldValueMap.GetEnumerator().where({ $_.Value -isnot 'scriptblock' })) {
				Write-Warning -Message 'A scriptblock must be a value in FieldValueMap.'
				$result = $false
			}
			
		}
		'UserMatch' {
			$mapHt = $UserMatchMap.Clone()
			if (@($UserMatchMap.Keys | Where-Object { $_ -in @('FirstName', 'LastName') }).Count -ne 2) {
				$result = $false
			}
		}
		default {
			throw "Unrecognized input: [$_]"
		}
	}
	if ($result -and (-not $UserMatchMap)) {
		if (-not (TestCsvHeaderExists -CsvFilePath $CsvFilePath -Header ([array]($mapHt.Keys)))) {
			Write-Warning -Message 'CSV header check failed.'
			$false
		} else {
			$true
		}
	} else {
		$result
	}
	
}