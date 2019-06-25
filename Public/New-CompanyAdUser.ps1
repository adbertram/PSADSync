function New-CompanyAdUser {
	[OutputType([Microsoft.ActiveDirectory.Management.ADUser])]
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,
		
		[Parameter(Mandatory, ParameterSetName = 'Password')]
		[ValidateNotNullOrEmpty()]
		[securestring]$Password,

		[Parameter(Mandatory, ParameterSetName = 'RandomPassword')]
		[ValidateNotNullOrEmpty()]
		[switch]$RandomPassword,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$Path = (GetPsAdSyncConfiguration).NewUserCreation.Path,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldValueMap,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldSyncMap,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMatchMap,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$UserMatchMap,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$UsernamePattern = (GetPsAdSyncConfiguration).NewUserCreation.AccountNamePattern
	)

	$userName = CleanAdAccountName(NewUserName -CsvUser $CsvUser -Pattern $UsernamePattern -FieldMap $UserMatchMap)

	$firstName = $CsvUser.($UserMatchMap.FirstName)
	$lastName = $CsvUser.($UserMatchMap.LastName)
	$newAdUserParams = @{ 
		Name           = $userName
		samAccountName = $userName
		DisplayName    = "$firstName $lastName"
		PassThru       = $true
		GivenName      = $firstName
		Surname        = $lastName
		Enabled        = $true
		Path           = $Path
	}

	if ($RandomPassword.IsPresent) {
		$pw = NewRandomPassword
	} else {
		$pw = $Password
	}
	$secPw = ConvertTo-SecureString -String $pw -AsPlainText -Force
	$otherAttribs = @{ }
	$FieldSyncMap.GetEnumerator().where({ $_.Value -notin 'sn', 'GivenName' }).foreach({
			if ($_.Value -is 'string') {
				$adAttribName = $_.Value
			} else {
				$adAttribName = EvaluateFieldCondition -Condition $_.Value -Type 'CSV'
			}

			if ($_.Key -is 'string') {
				$key = $_.Key
			} else {
				$key = EvaluateFieldCondition -Condition $_.Key -Type 'CSV'
			}
			
			if ($FieldValueMap -and $FieldValueMap.ContainsKey($key)) {
				$adAttribValue = EvaluateFieldCondition -Condition $FieldValueMap.$key  -Type 'CSV'
			} else {
				$adAttribValue = $CsvUser.$key
			}
			$convertParams = @{
				AttributeName  = $adAttribName
				AttributeValue = $adAttribValue
				Action         = 'Set'
			}
			$otherAttribs.$adAttribName = (ConvertToSchemaAttributeType @convertParams)
		})

	$FieldMatchMap.GetEnumerator().foreach({
			if ($_.Value -is 'string') {
				$adAttribName = $_.Value
			} else {
				$adAttribName = EvaluateFieldCondition -Condition $_.Value -CsvUser $CsvUser
			}
			
			if ($_.Key -is 'string') {
				$key = $_.Key	
			} else {
				$key = EvaluateFieldCondition -Condition $_.Key -CsvUser $CsvUser
			}
			$adAttribValue = $CsvUser.$key
			$convertParams = @{
				AttributeName  = $adAttribName
				AttributeValue = $adAttribValue
				Action         = 'Read'
			}
			$otherAttribs.$adAttribName = (ConvertToSchemaAttributeType @convertParams)
		})

	$newAdUserParams.OtherAttributes = $otherAttribs

	if (Get-AdUser -Filter "samAccountName -eq '$userName'") {
		throw "The user to be created [$($userName)] already exists."
	} else {
		if ($PSCmdlet.ShouldProcess("User: [$($userName)] AD attribs: [$($newAdUserParams | Out-String; $newAdUserParams.OtherAttributes | Out-String)]", 'New AD User')) {
			Write-Verbose -Message 'Creating new AD user...'
			if ($newUser = New-ADUser @newAdUserParams) {
				Set-ADAccountPassword -Identity $newUser.DistinguishedName -Reset -NewPassword $secPw
				$newUser | Add-Member -MemberType NoteProperty -Name 'Password' -Force -Value $pw -PassThru
			}
		}
	}
}