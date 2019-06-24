Add-Type -AssemblyName 'System.DirectoryServices.AccountManagement'

function GetPsAdSyncConfiguration {
	[OutputType('hashtable')]
	[CmdletBinding()]
	param
	()

	Import-PowerShellDataFile -Path "$PSScriptRoot\Configuration.psd1"

}

function ConvertToSchemaAttributeType {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$AttributeName,

		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[AllowNull()]
		$AttributeValue,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[ValidateSet('Read', 'Set')]
		[string]$Action
	)

	if ($AttributeValue) {
		switch ($AttributeName) {
			'accountExpires' {
				if ((-not $AttributeValue) -or ($AttributeValue -eq '9223372036854775807')) {
					0
				} else {
					if ([string]$AttributeValue -as [DateTime]) {
						$date = ([datetime]$AttributeValue).Date
					} else {
						$date = ([datetime]::FromFileTime($AttributeValue)).Date
					}
					switch ($Action) {
						'Read' {
							$date.AddDays(-1)
						}
						'Set' {
							$date.AddDays(2)
						}
						default {
							throw "Unrecognized input: [$_]"
						}
					}
				}
			}
			'countryCode' {
				## Load once only
				if (-not (Get-Variable -Name 'countryCodes' -Scope Script -ErrorAction Ignore)) {
					$script:countryCodes = Get-AvailableCountryCodes
				}
				## ie. match on United States or just US
				if (-not ($code = @($script:countryCodes).where({ $_.activeDirectoryName -eq $AttributeValue -or $_.alpha2 -eq $AttributeValue}))) {
					throw "Country code for name [$($AttributeValue)] could not be found."
				}
				$code.Numeric
			}
			'manager' {
				if ($AttributeValue -notmatch '^(?:(?<cn>CN=(?<name>[^,]*)),)?(?:(?<path>(?:(?:CN|OU)=[^,]+,?)+),)?(?<domain>(?:DC=[^,]+,?)+)$') {
					## Assume the Manager field is "<First Name> <Last Name>"
					$managerFirstName = $AttributeValue.Split(' ')[0]
					$managerLastName = $AttributeValue.Split(' ')[1]
					## Find the DN
					if (-not ($managerUser = $script:adUsers | where {$_.GivenName -eq $managerFirstName -and $_.sn -eq $managerLastName})) {
						throw 'Could not find manager distinguished name.'
					} else {
						$managerUser.DistinguishedName
					}
				} else {
					$AttributeValue
				}
			}
			default {
				$AttributeValue
			}
		}
	} else {
		## If $AttributeValue is null, return an emptry string to prevent any references to the value from failing
		''
	}
}

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

function SetAdUser {
	[OutputType([void])]
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Identity,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$ActiveDirectoryAttributes
	)	

	$replaceHt = @{}
	foreach ($attrib in $ActiveDirectoryAttributes.GetEnumerator()) {
		$attribName = $attrib.Key
		$convertParams = @{
			AttributeName  = $attrib.Key
			AttributeValue = $attrib.Value
			Action         = 'Set'
		}
		$replaceHt.$attribName = (ConvertToSchemaAttributeType @convertParams)
	}

	$setParams = @{
		Identity = $Identity
		Replace  = $replaceHt
		Confirm  = $false
	}
		
	if ($PSCmdlet.ShouldProcess("User: [$($Identity)] AD attribs: [$($replaceHt.Keys -join ',')] to [$($ActiveDirectoryAttributes.Values -join ',')]", 'Set AD attributes')) {
		Write-Verbose -Message "Replacing AD attribs: [$($setParams.Replace | Out-String)]"
		Set-AdUser @setParams
	} 
}

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

function GetCsvColumnHeaders {
	[OutputType([string])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvFilePath
	)
	
	(Get-Content -Path $CsvFilePath | Select-Object -First 1).Split(',') -replace '"'
}

# .ExternalHelp PSADSync-Help.xml
function Get-AvailableAdUserAttribute {
	param()

	$schema =[DirectoryServices.ActiveDirectory.ActiveDirectorySchema]::GetCurrentSchema()
	$userClass = $schema.FindClass('user')
	
	foreach ($name in $userClass.GetAllProperties().Name | Sort-Object) {
		
		$output = [ordered]@{
			ValidName  = $name
			CommonName = $null
		}
		switch ($name) {
			'sn' {
				$output.CommonName = 'SurName'
			}
		}
		
		[pscustomobject]$output
	}
}

# .ExternalHelp PSADSync-Help.xml
function Get-AvailableCountryCodes {
	[OutputType('pscustomobject')]
	[CmdletBinding()]
	param
	()

	$ErrorActionPreference = 'Stop'

	$countryCodes = Import-PowerShellDataFile -Path "$PSScriptRoot\CountryCodeMap.psd1"
	$countryCodes.Countries
	
}

function TestIsValidAdAttribute {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Name
	)

	if ($Name -in (Get-AvailableAdUserAttribute).ValidName) {
		$true
	} else {
		$false
	}
}

function TestCsvHeaderExists {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvFilePath,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object[]]$Header,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$ParseScriptBlockHeaders
	)

	$csvHeaders = GetCsvColumnHeaders -CsvFilePath $CsvFilePath

	## Parse out the CSV headers used if the field is a scriptblock
	$commonHeaders = @($Header).foreach({
			$_ | ForEach-Object {
				if ($_ -is 'scriptblock') {
					## It's extremely hard to figure out what values inside of the scriptblock are actual CSV headers
					## Give the option here.
					if ($ParseScriptBlockHeaders.IsPresent) {
						ParseScriptBlockHeaders -FieldScriptBlock $_
					}
				} else {
					$_
				}
			}
		})

	## Assuming that ParseScriptBlockHeaders was not used and all of the headers
	## are scriptblocks. We check nothing but still return true.
	if (-not ($commonHeaders = $commonHeaders | Select-Object -Unique)) {
		$true
	} else {
		$matchedHeaders = $csvHeaders | Where-Object { $_ -in $commonHeaders }
		if (@($matchedHeaders).Count -ne @($commonHeaders).Count) {
			$false
		} else {
			$true
		}
	}
}

function ParseScriptBlockHeaders {
	[OutputType('$')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[scriptblock[]]$FieldScriptBlock
	)
	
	$headers = @($FieldScriptBlock).foreach({
			$ast = [System.Management.Automation.Language.Parser]::ParseInput($_.ToString(), [ref]$null, [ref]$null)
			$ast.FindAll({$args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]}, $true).Value
		})
	$headers | Select-Object -Unique
	
}

function Get-CompanyCsvUser {
	[OutputType([pscustomobject])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path -Path $_ -PathType Leaf})]
		[string]$CsvFilePath,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Exclude,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateSet('Comma', 'Tab')]
		[string]$Delimiter = 'Comma'
	)
	begin {
		$ErrorActionPreference = 'Stop'
		Write-Verbose -Message "Enumerating all users in CSV file [$($CsvFilePath)]"
	}
	process {
		try {
			$whereFilter = { '*' }
			if ($PSBoundParameters.ContainsKey('Exclude')) {
				$conditions = $Exclude.GetEnumerator() | ForEach-Object { "(`$_.'$($_.Key)' -ne '$($_.Value)')" }
				$whereFilter = [scriptblock]::Create($conditions -join ' -and ')
			}

			$importCsvParams = @{
				Path = $CsvFilePath
			}
			if ($Delimiter -eq 'Comma') {
				$importCsvParams.Delimiter = ','
			} elseif ($Delimiter -eq 'Tab') {
				$importCsvParams.Delimiter = "`t"
			}

			Import-Csv @importCsvParams | Where-Object -FilterScript $whereFilter
		} catch {
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}

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
	$otherAttribs = @{}
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
			if (($UserMatchMap.Keys | Where-Object { $_ -in @('FirstName', 'LastName') }).Count -ne 2) {
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

function EvaluateFieldCondition {
	[OutputType('string')]
	[CmdletBinding(DefaultParameterSetName = 'CSVUser')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[scriptblock]$Condition,

		[Parameter(Mandatory, ParameterSetName = 'CSVUser')]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,

		[Parameter(Mandatory, ParameterSetName = 'ADUser')]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser
	)

	if ($PSBoundParameters.ContainsKey('CsvUser')) {
		$replace = '$CsvUser'
	} elseif ($PSBoundParameters.ContainsKey('AdUser')) {
		$replace = 'ADUser'
	}
	
	$fieldScript = $Condition.ToString() -replace '\$_', $replace
	& ([scriptblock]::Create($fieldScript))
	
}

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

function NewRandomPassword {
	<#
    .Synopsis
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .DESCRIPTION
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .EXAMPLE
       New-SWRandomPassword
       C&3SX6Kn

       Will generate one password with a length between 8  and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -MinPasswordLength 8 -MaxPasswordLength 12 -Count 4
       7d&5cnaB
       !Bh776T"Fw
       9"C"RxKcY
       %mtM7#9LQ9h

       Will generate four passwords, each with a length of between 8 and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4 -FirstChar abcdefghijkmnpqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString that will start with a letter from 
       the string specified with the parameter FirstChar
    .OUTPUTS
       [String]
    .NOTES
       Written by Simon Wåhlin, blog.simonw.se
       I take no responsibility for any issues caused by this script.
    .FUNCTIONALITY
       Generates random passwords
    .LINK
       http://blog.simonw.se/powershell-generating-random-password-for-active-directory/
   
    #>
	[CmdletBinding(DefaultParameterSetName='RandomLength', ConfirmImpact='None')]
	[OutputType([String])]
	Param
	(
		# Specifies minimum password length
		[Parameter(Mandatory=$false,
			ParameterSetName='RandomLength')]
		[ValidateScript({$_ -gt 0})]
		[Alias('Min')] 
		[int]$MinPasswordLength = 12,
        
		# Specifies maximum password length
		[Parameter(Mandatory=$false,
			ParameterSetName='RandomLength')]
		[ValidateScript({
				if($_ -ge $MinPasswordLength){$true}
				else{Throw 'Max value cannot be lesser than min value.'}})]
		[Alias('Max')]
		[int]$MaxPasswordLength = 15,

		# Specifies a fixed password length
		[Parameter(Mandatory=$false,
			ParameterSetName='FixedLength')]
		[ValidateRange(1, 2147483647)]
		[int]$PasswordLength = 8,
        
		# Specifies an array of strings containing charactergroups from which the password will be generated.
		# At least one char from each group (string) will be used.
		[String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '23456789', '!"#%&'),

		# Specifies a string containing a character group from which the first character in the password will be generated.
		# Useful for systems which requires first char in password to be alphabetic.
		[String] $FirstChar,
        
		# Specifies number of passwords to generate.
		[ValidateRange(1, 2147483647)]
		[int]$Count = 1
	)
	Begin {
		Function Get-Seed{
			# Generate a seed for randomization
			$RandomBytes = New-Object -TypeName 'System.Byte[]' 4
			$Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
			$Random.GetBytes($RandomBytes)
			[BitConverter]::ToUInt32($RandomBytes, 0)
		}
	}
	Process {
		For($iteration = 1; $iteration -le $Count; $iteration++){
			$Password = @{}
			# Create char arrays containing groups of possible chars
			[char[][]]$CharGroups = $InputStrings

			# Create char array containing all chars
			$AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

			# Set password length
			if($PSCmdlet.ParameterSetName -eq 'RandomLength') {
				if($MinPasswordLength -eq $MaxPasswordLength) {
					# If password length is set, use set length
					$PasswordLength = $MinPasswordLength
				} else {
					# Otherwise randomize password length
					$PasswordLength = ((Get-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
				}
			}

			# If FirstChar is defined, randomize first char in password from that string.
			if($PSBoundParameters.ContainsKey('FirstChar')){
				$Password.Add(0, $FirstChar[((Get-Seed) % $FirstChar.Length)])
			}
			# Randomize one char from each group
			Foreach($Group in $CharGroups) {
				if($Password.Count -lt $PasswordLength) {
					$Index = Get-Seed
					While ($Password.ContainsKey($Index)){
						$Index = Get-Seed                        
					}
					$Password.Add($Index, $Group[((Get-Seed) % $Group.Count)])
				}
			}

			# Fill out with chars from $AllChars
			for($i=$Password.Count; $i -lt $PasswordLength; $i++) {
				$Index = Get-Seed
				While ($Password.ContainsKey($Index)){
					$Index = Get-Seed                        
				}
				$Password.Add($Index, $AllChars[((Get-Seed) % $AllChars.Count)])
			}
			Write-Output -InputObject $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
		}
	}
}

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

function TestUserTerminated {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser
	)

	$csvField = (GetPsAdSyncConfiguration).UserTermination.FieldValueSettings.CsvField
	$csvValue = (GetPsAdSyncConfiguration).UserTermination.FieldValueSettings.CsvValue
	
	if ($CsvUser.$csvField -in $csvValue) {
		$true
	} else {
		$false
	}
}

function TestIsUserTerminationEnabled {
	[OutputType('bool')]
	[CmdletBinding()]
	param
	()

	if ((GetPsAdSyncConfiguration).UserTermination.Enabled) {
		$true
	} else {
		$false
	}
}

function TestIsUserCreationEnabled {
	[OutputType('bool')]
	[CmdletBinding()]
	param
	()

	(GetPsAdSyncConfiguration).UserCreation.Enabled
}

function SyncCompanyUser {
	[OutputType()]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Identity,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable[]]$ActiveDirectoryAttributes
	)

	$ErrorActionPreference = 'Stop'
	try {
		foreach ($ht in $ActiveDirectoryAttributes) {
			SetAdUser -Identity $Identity -ActiveDirectoryAttributes $ht
		}
		
	} catch {
		$PSCmdlet.ThrowTerminatingError($_)
	}
}

function WriteLog {
	[OutputType([void])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$FilePath = "$PSScriptRoot\PSAdSync.csv",

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierField,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierValue,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Attributes,

		[Parameter()]
		[switch]$Overwrite
	)
	
	$ErrorActionPreference = 'Stop'
	
	$time = Get-Date -Format 'g'
	$Attributes['CsvIdentifierValue'] = $CsvIdentifierValue
	$Attributes['CsvIdentifierField'] = $CsvIdentifierField
	$Attributes['Time'] = $time
	
	if (!($Overwrite)) {
		([pscustomobject]$Attributes) | Export-Csv -Path $FilePath -Append -NoTypeInformation -Confirm:$false
	} else {
		([pscustomobject]$Attributes) | Export-Csv -Path $FilePath -NoTypeInformation -Confirm:$false
	}


}

function GetCsvIdField {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMatchMap
	)


	$FieldMatchMap.Keys | ForEach-Object { 
		[pscustomobject]@{
			Field = $_
			Value = $CSVUser.$_
		}
	}
	
}

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

function ReadEmailTemplate {
	[OutputType('string')]
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Name	
	)
	
	if ($template = Get-ChildItem -Path "$PSScriptRoot\EmailTemplates" -Filter "$Name.txt") {
		Get-Content -Path $template.FullName -Raw
	}
}

function WriteProgressHelper {
	param (
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[int]$StepNumber,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Message
	)
	Write-Progress -Activity 'Active Directory Report/Sync' -Status $Message -PercentComplete (($StepNumber / $script:totalSteps) * 100)
}

function TestShouldCreateNewUser {
	[OutputType('bool')]
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser
	)

	if ((TestIsUserTerminationEnabled) -and (TestUserTerminated -CsvUser $CsvUser)) {
		$false	
	} else {
		if ($csvfield = (GetPsAdSyncConfiguration).NewUserCreation.Exclude.FieldValueSettings.CsvField) {
			$csvValue = (GetPsAdSyncConfiguration).NewUserCreation.Exclude.FieldValueSettings.CsvValue
			if ($CsvUser.$csvField -in $csvValue) {
				$false
			} else {
				$true
			}
		} else {
			$true
		}
	}
}

# .ExternalHelp PSADSync-Help.xml
function Invoke-AdSync {
	[OutputType([void])]
	[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvFilePath,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldSyncMap,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMatchMap,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldValueMap,

		[Parameter(Mandatory, ParameterSetName = 'CreateNewUsers')]
		[ValidateNotNullOrEmpty()]
		[hashtable]$UserMatchMap,

		[Parameter(Mandatory, ParameterSetName = 'CreateNewUsers')]
		[ValidateNotNullOrEmpty()]
		[ValidateSet('FirstInitialLastName', 'FirstNameLastName', 'FirstNameDotLastName', 'LastNameFirstTwoFirstNameChars')]
		[string]$UsernamePattern,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[scriptblock]$UserTerminationAction,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$ReportOnly,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Exclude,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$logFilePath,

		[Parameter()]
		[switch]$logOverwrite
	)
	begin {
		$ErrorActionPreference = 'Stop'
		$logParams = @{}
		if ($logFilePath) {
			$logParams["FilePath"] = $logFilePath
		}
		if ($logOverwrite) {
			$logParams["Overwrite"] = $true
		}
	}
	process {
		try {
			$getCsvParams = @{
				CsvFilePath = $CsvFilePath
			}

			if ($PSBoundParameters.ContainsKey('Exclude')) {
				if (-not (TestCsvHeaderExists -CsvFilePath $CsvFilePath -Header ([array]$Exclude.Keys))) {
					throw 'One or more CSV headers excluded with -Exclude do not exist in the CSV file.'
				}
				$getCsvParams.Exclude = $Exclude
			}

			if (-not (TestFieldMapIsValid -FieldSyncMap $FieldSyncMap -CsvFilePath $CsvFilePath)) {
				throw 'Invalid attribute found in FieldSyncMap.'
			}
			if (-not (TestFieldMapIsValid -FieldMatchMap $FieldMatchMap -CsvFilePath $CsvFilePath)) {
				throw 'Invalid attribute found in FieldMatchMap.'
			}

			if ($PSBoundParameters.ContainsKey('FieldValueMap')) {
				if (-not (TestFieldMapIsValid -FieldValueMap $FieldValueMap -CsvFilePath $CsvFilePath)) {
					throw 'Invalid attribute found in FieldValueMap.'
				}	
			}

			$FieldSyncMap.GetEnumerator().where({$_.Value -is 'string'}).foreach({
					if (-not (TestIsValidAdAttribute -Name $_.Value)) {
						throw 'One or more AD attributes in FieldSyncMap do not exist. Use Get-AvailableAdUserAttribute for a list of available attributes.'
					}
				})

			Write-Output 'Enumerating all Active Directory users. This may take a few minutes depending on the number of users...'
			if (-not ($script:adUsers = Get-CompanyAdUser -FieldMatchMap $FieldMatchMap -FieldSyncMap $FieldSyncMap)) {
				throw 'No AD users found'
			}

			Write-Output 'Enumerating all CSV users...'
			if (-not ($csvusers = Get-CompanyCsvUser @getCsvParams)) {
				throw 'No CSV users found'
			}

			$script:totalSteps = @($csvusers).Count
			$stepCounter = 0
			$rowsProcessed = 1
			@($csvUsers).foreach({
					try {
						## account for the CSV header row
						$csvRow = $rowsProcessed + 1
						$logEntry = $true
						if ($ReportOnly.IsPresent) {
							$prgMsg = "Attempting to find attribute mismatch for user in CSV row [$($stepCounter + 1)]"
						} else {
							$prgMsg = "Attempting to find and sync AD any attribute mismatches for user in CSV row [$($stepCounter + 1)]"
						}
						WriteProgressHelper -Message $prgMsg -StepNumber ($stepCounter++)
						$csvUser = $_
						if ($adUserMatch = FindUserMatch -CsvUser $csvUser -FieldMatchMap $FieldMatchMap) {
							$CSVAttemptedMatchIds = $aduserMatch.CSVAttemptedMatchIds
							$csvIdValue = ($CSVAttemptedMatchIds | % {$csvUser.$_}) -join ','
							$csvIdField = $CSVAttemptedMatchIds -join ','

							#region FieldValueMap check
							if ($PSBoundParameters.ContainsKey('FieldValueMap')) {
								$selectParams = @{ 
									Property = @('*') 
									Exclude  = [array]($FieldValueMap.Keys)
								}
								@($FieldValueMap.GetEnumerator()).foreach({
										$selectParams.Property += @{ 
											Name       = $_.Key
											Expression = $_.Value
										}
									})
								$csvUser = $csvUser | Select-Object @selectParams
							}
							#endregion
						
							## User termination check
							if ((TestIsUserTerminationEnabled) -and (TestUserTerminated -CsvUser $csvUser)) {
								if (-not $ReportOnly.IsPresent) {
									$termParams = @{
										AdUser = $adUserMatch.MatchedAduser
									}
									if ($PSBoundParameters.ContainsKey('UserTerminationAction')) {
										$termParams.UserTerminationAction = $UserTerminationAction
									}
									InvokeUserTermination @termParams
								}

								$logAttribs = @{
									CSVAttributeName  = 'UserTermination'
									CSVAttributeValue = 'UserTermination'
									ADAttributeName   = 'UserTermination'
									ADAttributeValue  = 'UserTermination'
									Message           = $_.Exception.Message
								}
							} else {
								$findParams = @{
									AdUser       = $adUserMatch.MatchedAdUser
									CsvUser      = $csvUser
									FieldSyncMap = $FieldSyncMap
								}
								$attribMismatches = FindAttributeMismatch @findParams
								if ($attribMismatches) {
									$logEntry = $false
									$attribMismatches | foreach {
										$logAttribs = @{
											CSVAttributeName  = 'AttributeChange - {0}' -f [string]($_.CSVField.Keys)
											CSVAttributeValue = [string]($_.CSVField.Values)
											ADAttributeName   = 'AttributeChange - {0}' -f [string]($_.ActiveDirectoryAttribute.Keys)
											ADAttributeValue  = [string]($_.ActiveDirectoryAttribute.Values)
											Message           = $null
										}
										WriteLog -CsvIdentifierField $csvIdField -CsvIdentifierValue $csvIdValue -Attributes $logAttribs @logParams 
									}
									
									if (-not $ReportOnly.IsPresent) {
										$syncParams = @{
											CsvUser                   = $csvUser
											ActiveDirectoryAttributes = $attribMismatches.ADShouldBe
											Identity                  = $adUserMatch.MatchedAduser.samAccountName
										}
										Write-Verbose -Message "Running SyncCompanyUser with params: [$($syncParams | Out-String)]"
										SyncCompanyUser @syncParams
									}
								} elseif ($attribMismatches -eq $false) {
									throw 'Error occurred in FindAttributeMismatch'
								} else {
									Write-Verbose -Message "No attributes found to be mismatched between CSV and AD user account for user [$csvIdValue]"
									$logAttribs = @{
										CSVAttributeName  = 'AlreadyInSync'
										CSVAttributeValue = 'AlreadyInSync'
										ADAttributeName   = 'AlreadyInSync'
										ADAttributeValue  = 'AlreadyInSync'
										Message           = $null
									}
								}
							}
						} else {
							## No user match was found
							if (-not ($csvIds = @(GetCsvIdField -CsvUser $csvUser -FieldMatchMap $FieldMatchMap).where({ $_.Field }))) {
								Write-Warning -Message  'No CSV ID fields were found.'
								$csvIdField = "CSV Row: $csvRow"
								$csvIdValue = "CSV Row: $csvRow"

								$logAttribs = @{
									CSVAttributeName  = "CSV Row: $csvRow"
									CSVAttributeValue = "CSV Row: $csvRow"
									ADAttributeName   = 'NoMatch'
									ADAttributeValue  = 'NoMatch'
									Message           = $null
								}
							} elseif ($PSBoundParameters.ContainsKey('UserMatchMap') -and (TestShouldCreateNewUser -CsvUser $csvUser)) {
								$csvIdField = $csvIds.Field -join ','
								if (-not $ReportOnly.IsPresent) {
									$newUserParams = @{
										CsvUser         = $csvUser
										UsernamePattern = $UsernamePattern
										UserMatchMap    = $UserMatchMap
										RandomPassword  = $true
										FieldSyncMap    = $FieldSyncMap
										FieldMatchMap   = $FieldMatchMap
									}
									if ($PSBoundParameters.ContainsKey('FieldValueMap')) {
										$newUserParams.FieldValueMap = $FieldValueMap
									}
									$newAdUser = New-CompanyAdUser @newUserParams
								}

								$logAttribs = @{
									CSVAttributeName  = 'NewUserCreated'
									CSVAttributeValue = 'NewUserCreated'
									ADAttributeName   = 'NewUserCreated'
									ADAttributeValue  = 'NewUserCreated'
									Message           = "UserName: [$($newAdUser.Name)] - Password: [$($newAdUser.Password)]"
								}
								$csvIdValue = ($csvIds | foreach { $csvUser.($_.Field) })
							} else {
								$csvIdField = $csvIds.Field -join ','
								$csvIdValue = "CSV Row: $csvRow"

								$logAttribs = @{
									CSVAttributeName  = "CSV Row: $csvRow"
									CSVAttributeValue = "CSV Row: $csvRow"
									ADAttributeName   = 'NoMatch'
									ADAttributeValue  = 'NoMatch'
									Message           = $null
								}
							}
						}
					
					} catch {
						$csvIdField = "CSV Row: $csvRow"
						$csvIdValue = "CSV Row: $csvRow"
						$logAttribs = @{
							CSVAttributeName  = 'Error'
							CSVAttributeValue = 'Error'
							ADAttributeName   = 'Error'
							ADAttributeValue  = 'Error'
							Message           = $_.Exception.Message
						}
					} finally {
						if ($logEntry) {
							WriteLog -CsvIdentifierField $csvIdField -CsvIdentifierValue $csvIdValue -Attributes $logAttribs @logParams 
						}
						$rowsProcessed++
					}
				})
		} catch {
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		} finally {
			Remove-Variable -Scope Script -Name adUsers -ErrorAction Ignore
		}
	}
}