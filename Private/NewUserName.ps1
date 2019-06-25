function NewUserName {
	[OutputType('string')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Pattern,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMap
	)

	if (-not (TestFieldMapIsValid -UserMatchMap $FieldMap)) {
		throw 'One or more values in FieldMap parameter are missing.'
	}

	switch ($Pattern) {
		'FirstInitialLastName' {
			'{0}{1}' -f ($CsvUser.($FieldMap.FirstName)).SubString(0, 1), $CsvUser.($FieldMap.LastName)
		}
		'FirstNameLastName' {
			'{0}{1}' -f $CsvUser.($FieldMap.FirstName), $CsvUser.($FieldMap.LastName)
		}
		'FirstNameDotLastName' {
			'{0}.{1}' -f $CsvUser.($FieldMap.FirstName), $CsvUser.($FieldMap.LastName)
		}
		'LastNameFirstTwoFirstNameChars' {
			'{0}{1}' -f $CsvUser.($FieldMap.LastName), ($CsvUser.($FieldMap.FirstName)).SubString(0, 2)
		}
		default {
			throw "Unrecognized UserNamePattern: [$_]"
		}
	}
}