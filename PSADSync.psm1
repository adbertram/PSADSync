Add-Type -AssemblyName 'System.DirectoryServices.AccountManagement'

function ConvertToSchemaAttributeType
{
	[OutputType([bool],[string])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$AttributeName,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$AttributeValue
	)

	switch ($AttributeName)
	{
		'accountExpires' {
			([datetime]$AttributeValue).AddDays(2)
		}
		default {
			$AttributeValue
		}
	}	
	
}

function ConvertToAdUser
{
	[OutputType('string')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory,ParameterSetName = 'String')]
		[ValidateNotNullOrEmpty()]
		[string]$String
	)

	$baseLdapString = '(&(objectCategory=person)(objectClass=user)'
	
	$ldapString = switch -regex ($String)
	{
		'^(?<givenName>\w+)\s+(?<sn>\w+)$' { ## John Doe
			'(&(givenName={0})(sn={1}))'  -f $Matches.givenName,$Matches.sn
		}
		'^(?<sn>\w+),\s?(?<givenName>\w+)$' { ## Doe,John
			'(&(givenName={0})(sn={1}))'  -f $Matches.givenName,$Matches.sn
		}
		'^(?<samAccountName>\w+)$' { ## jdoe
			'(samAccountName={0})' -f $Matches.samAccountName
		}
		'^(?<distinguishedName>(\w+[=]{1}\w+)([,{1}]\w+[=]{1}\w+)*)$' {
			'(distinguishedName={0})' -f $Matches.distinguishedName
		}
		default {
			Write-Warning -Message "Unrecognized input: [$_]: Unable to convert [$($String)] to LDAP filter."
		}
	}
	if ($ldapString) {
		$ldapFilter = '{0}{1})' -f $baseLdapString,$ldapString

		Write-Verbose -Message "LDAP filter is [$($ldapFilter)]"
		Get-AdUser -LdapFilter $ldapFilter
	}
	
}

function SetAdUser
{
	[OutputType([void])]
	[CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
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
		$replaceHt.$attribName = (ConvertToSchemaAttributeType -AttributeName $attrib.Key -AttributeValue $attrib.Value)
	}

	$setParams = @{
		Identity = $Identity
		Replace = $replaceHt
	}
		
	if ($PSCmdlet.ShouldProcess("User: [$($Identity)] AD attribs: [$($replaceHt.Keys -join ',')] to [$($replaceHt.Values -join ',')]",'Set AD attributes')) {
		Write-Verbose -Message "Replacing AD attribs: [$($setParams.Replace | Out-String)]"
		Set-AdUser @setParams
	} 
}

function Get-CompanyAdUser
{
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
	begin
	{
		$ErrorActionPreference = 'Stop'
	}
	process
	{
		try
		{
			$userProperties = ([array]($FieldMatchMap.Values) + [array]($FieldSyncMap.Values)) | Select-Object -Unique
			Write-Verbose -Message "Finding all AD users in domain with properties: $($userProperties -join ',')"
			@(Get-AdUser -Filter '*' -Properties $userProperties).where({
				$adUser = $_
				## Ensure at least one ID field is populated
				@($FieldMatchMap.Values).where({ $adUser.($_) })
			})
		}
		catch
		{
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}

function GetCsvColumnHeaders
{
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

function Get-AvailableAdUserAttribute {
	param()

	$schema =[DirectoryServices.ActiveDirectory.ActiveDirectorySchema]::GetCurrentSchema()
	$userClass = $schema.FindClass('user')
	
	foreach ($name in $userClass.GetAllProperties().Name | Sort-Object) {
		
		$output = [ordered]@{
			ValidName = $name
			CommonName = $null
		}
		switch ($name)
		{
			'sn' {
				$output.CommonName = 'SurName'
			}
		}
		
		[pscustomobject]$output
	}
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

function TestCsvHeaderExists
{
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvFilePath,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object[]]$Header
	)

	$csvHeaders = GetCsvColumnHeaders -CsvFilePath $CsvFilePath

	## Parse out the CSV headers used if the field is a scriptblock
	$commonHeaders = @($Header).foreach({
		if ($_ -is 'scriptblock') {
			ParseScriptBlockHeaders -FieldScriptBlock $_
		} else {
			$_
		}
	})
	$commonHeaders = $commonHeaders | Select-Object -Unique

	$matchedHeaders = $csvHeaders | Where-Object { $_ -in $commonHeaders }
	if (@($matchedHeaders).Count -ne @($commonHeaders).Count) {
		$false
	} else {
		$true
	}
}

function ParseScriptBlockHeaders
{
	[OutputType('$')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[scriptblock[]]$FieldScriptBlock
	)
	
	$headers = @($FieldScriptBlock).foreach({
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($_.ToString(),[ref]$null,[ref]$null)
		$ast.FindAll({$args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]},$true).Value
	})
	$headers | Select-Object -Unique
	
}

function Get-CompanyCsvUser
{
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
		[hashtable]$FieldValueMap,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Exclude
	)
	begin
	{
		$ErrorActionPreference = 'Stop'
		Write-Verbose -Message "Enumerating all users in CSV file [$($CsvFilePath)]"
	}
	process
	{
		try
		{
			$selectParams = @{
				Property = '*'
			}
			if ($PSBoundParameters.ContainsKey('FieldValueMap'))
			{
				$selectParams.ExcludeProperty = $FieldValueMap.Keys
				$selectParams.Property = @('*')
				$FieldValueMap.GetEnumerator().foreach({
					if ($_.Value -isnot 'scriptblock') {
						throw 'A value in FieldValueMap is not a scriptblock'
					}
					$selectParams.Property += @{ 'Name' = $_.Key; Expression = $_.Value }
				})
			}
			
			$whereFilter = { '*' }
			if ($PSBoundParameters.ContainsKey('Exclude'))
			{
				$conditions = $Exclude.GetEnumerator() | ForEach-Object { "(`$_.'$($_.Key)' -ne '$($_.Value)')" }
				$whereFilter = [scriptblock]::Create($conditions -join ' -and ')
			}

			Import-Csv -Path $CsvFilePath | Where-Object -FilterScript $whereFilter | Select-Object @selectParams | foreach {
				if ($FieldValueMap -and (-not $_.($FieldValueMap.Keys))) {
					Write-Warning -Message "The CSV [$($FieldValueMap.Keys)] field in FieldValueMap returned nothing."
				} else {
					$_
				}
			}
		}
		catch
		{
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}

function New-CompanyAdUser
{
    [OutputType([void])]
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Attributes
    )

	## Create the New-AdUser parameters
	$newAdUserParamNames = @(
		'City'
        'Company'
        'DisplayName'
        'EmailAddress'
        'EmployeeID'
        'EmployeeNumber'
        'GivenName'
        'HomePage'
        'Office'
        'POBox'
        'PostalCode'
        'State'
        'StreetAddress'
        'UserPrincipalName'
	)
    $newAdUserParams = @{ Name = $Identity }
	$Attributes.GetEnumerator().where({ $_.Key -in $newAdUserParamNames }).foreach({ $newAdUserParams[$_.Key] = $_.Value })
	$newAdUserParams.AccountPassword = (NewRandomPassword)

	## If any, create the Set-AdUser parameters
	$setAdUserParams = @{ 
		Identity = $Identity
	}
	$setAdUserAddHt = @{}
	$Attributes.GetEnumerator().where({ $_.Key -notin $newAdUserParamNames }).foreach({ $setAdUserAddHt[$_.Key] = $_.Value})

	if ($setAdUserAddHt.Keys -gt 0) {
		$confirmMsg = ($newAdUserParams + $setAdUserParams) | Out-String
	} else {
		$confirmMsg = $newAdUserParams | Out-String
	}
    if ($PSCmdlet.ShouldProcess("User: [$($Identity)] AD attribs: [$($confirmMsg)]",'New AD User')) {
		New-ADUser @newAdUserParams
		if ($setAdUserAddHt.Keys -gt 0) {
			$setAdUserParams.Add = $setAdUserAddHt
			Set-Aduser @setAdUserParams
		}
	}
}

function FindUserMatch
{
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

	foreach ($matchId in $FieldMatchMap.GetEnumerator()) { ## FieldMatchMap = @{ 'AD_LOGON' = 'samAccountName' }
		$adMatchField = $matchId.Value
		$csvMatchField = $matchId.Key
		Write-Verbose "Match fields: CSV - [$($csvMatchField)], AD - [$($adMatchField)]"
		if ($csvMatchVal = $CsvUser.$csvMatchField) {
			Write-Verbose -Message "CsvFieldMatchValue is [$($csvMatchVal)]"
			if ($matchedAdUser = @($AdUsers).where({ $_.$adMatchField -eq $csvMatchVal })) {
				Write-Verbose -Message "Found AD match for CSV user [$csvMatchVal]: [$($matchedAdUser.$adMatchField)]"
				[pscustomobject]@{
					MatchedAdUser = $matchedAdUser
					CsvIdMatchedOn = $csvMatchField
					AdIdMatchedOn = $adMatchField
				}
				## Stop after making a single match
				break
			} else {
				Write-Verbose -Message "No user match found for CSV user [$csvMatchVal]"
			}
		} else {
			Write-Verbose -Message "CSV field match value [$($csvMatchField)] could not be found."
		}
	}
}

function FindAttributeMismatch
{
	[OutputType([hashtable])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser,

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
			Write-Verbose -Message 'The CSV attribute is a scriptblock. Evaluating scriptblock to determine field name...'
			## Replace $_ with $CsvUser
			$csvFieldScript = $_.Key.ToString() -replace '\$_','$CsvUser'
			$csvFieldName = & ([scriptblock]::Create($csvFieldScript))
		} else {
			$csvFieldName = $_.Key
		}
		Write-Verbose -Message "Checking CSV field [$($csvFieldName)] for mismatches..."
		$adAttribName = $_.Value
		Write-Verbose -Message "Checking AD attribute [$($adAttribName)] for mismatches..."
		
		## Remove the null fields
		if (-not $AdUser.$adAttribName) {
			$AdUser | Add-Member -MemberType NoteProperty -Name $adAttribName -Force -Value ''
		}
		if ($CsvUser.$csvFieldName) {
			if (-not ($csvValue = ConvertToSchemaAttributeType -AttributeName $adAttribName -AttributeValue $CsvUser.$csvFieldName)) {
				$false
			} else {
				Write-Verbose -Message "Comparing AD attribute [$($Aduser.$adAttribName)] with converted CSV value [$($csvValue)]..."
				
				## Compare the two property values and return the AD attribute name and value to be synced
				if ($AdUser.$adAttribName -ne $csvValue) {
					@{
						ActiveDirectoryAttribute = @{ $adAttribName = $AdUser.$adAttribName }
						CSVField = @{ $csvFieldName = $CsvUser.$csvFieldName }
						ADShouldBe = @{ $adAttribName = $CsvUser.$csvFieldName }
					}
					Write-Verbose -Message "AD attribute mismatch found on AD attribute: [$($adAttribName)]."
				}
			}
		}
	})
}

function NewRandomPassword
{
	[CmdletBinding()]
	[OutputType([System.Security.SecureString])]
	param
	(
		[Parameter()]
		[ValidateRange(8, 64)]
		[int]$Length = (Get-Random -Minimum 20 -Maximum 32),

		[Parameter()]
		[ValidateRange(0, 8)]
		[int]$Complexity = 3
	)
	$ErrorActionPreference = 'Stop'

	Add-Type -AssemblyName 'System.Web'

	# Generate a password with the specified length and complexity.
	Write-Verbose ('Generating password {0} characters in length and with a complexity of {1}.' -f $Length, $Complexity);
	$password = [System.Web.Security.Membership]::GeneratePassword($Length, $Complexity);

	# Convert the password to a secure string so we don't put plain text passwords on the pipeline.
	ConvertTo-SecureString -String $password -AsPlainText -Force;
	
}

function ConvertToAdAttribute
{
	[OutputType([hashtable])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMap
	)

	$adAttributes = @{}
	@($CsvUser.PsObject.Properties).foreach({
		$csvField = $_
		$adAttrib = $FieldMap.($csvField.Name)
		$adAttributes.$adAttrib = $csvField.Value
	})

	$adAttributes

}

function SyncCompanyUser
{
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

function WriteLog
{
	[OutputType([void])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$FilePath = '.\PSAdSync.csv',

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierField,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierValue,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Attributes
	)
	
	$ErrorActionPreference = 'Stop'
	
	$time = Get-Date -Format 'g'
	$Attributes['CsvIdentifierValue'] = $CsvIdentifierValue
	$Attributes['CsvIdentifierField'] = $CsvIdentifierField
	$Attributes['Time'] = $time
	
	([pscustomobject]$Attributes) | Export-Csv -Path $FilePath -Append -NoTypeInformation

}

function GetCsvIdField
{
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

function Write-ProgressHelper {
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

function Invoke-AdSync
{
	[OutputType()]
	[CmdletBinding(SupportsShouldProcess)]
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

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$ReportOnly,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Exclude
	)
	begin
	{
		$ErrorActionPreference = 'Stop'
	}
	process
	{
		try
		{
			$getCsvParams = @{
				CsvFilePath = $CsvFilePath
			}
			if ($PSBoundParameters.ContainsKey('FieldValueMap'))
			{
				$getCsvParams.FieldValueMap = $FieldValueMap	
			}

			if ($PSBoundParameters.ContainsKey('Exclude'))
			{
				if (-not (TestCsvHeaderExists -CsvFilePath $CsvFilePath -Header ([array]$Exclude.Keys))) {
					throw 'One or more CSV headers excluded with -Exclude do not exist in the CSV file.'
				}
				$getCsvParams.Exclude = $Exclude
			}

			if (-not (TestCsvHeaderExists -CsvFilePath $CsvFilePath -Header ([array]$FieldMatchMap.Keys))) {
				throw 'One or more CSV headers in FieldMatchMap do not exist in the CSV file.'
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
			Write-Output 'Active Directory user enumeration complete.'
			Write-Output 'Enumerating all CSV users...'
			if (-not ($csvusers = Get-CompanyCsvUser @getCsvParams)) {
				throw 'No CSV users found'
			}
			Write-Output 'CSV user enumeration complete.'

			$script:totalSteps = @($csvusers).Count
			$stepCounter = 0
			@($csvUsers).foreach({
				if ($ReportOnly.IsPresent) {
					$prgMsg = "Attempting to find attribute mismatch for user in CSV row [$($stepCounter + 1)]"
				} else {
					$prgMsg = "Attempting to find and sync AD any attribute mismatches for user in CSV row [$($stepCounter + 1)]"
				}
				Write-ProgressHelper -Message $prgMsg -StepNumber ($stepCounter++)
				$csvUser = $_
				if ($adUserMatch = FindUserMatch -CsvUser $csvUser -FieldMatchMap $FieldMatchMap) {
					Write-Verbose -Message 'Match'
					$csvIdMatchedon = $aduserMatch.CsvIdMatchedOn
					$csvIdValue = $csvUser.$csvIdMatchedon
					$csvIdField = $csvIdMatchedon
					$findParams = @{
						AdUser = $adUserMatch.MatchedAdUser
						CsvUser = $csvUser
						FieldSyncMap = $FieldSyncMap
					}
					$attribMismatches = FindAttributeMismatch @findParams
					if ($attribMismatches) {
						$logAttribs = @{
							CSVAttributeName = ([array]($attribMismatches.CSVField.Keys))[0]
							CSVAttributeValue = ([array]($attribMismatches.CSVField.Values))[0]
							ADAttributeName = ([array]($attribMismatches.ActiveDirectoryAttribute.Keys))[0]
							ADAttributeValue = ([array]($attribMismatches.ActiveDirectoryAttribute.Values))[0]
						}
						if (-not $ReportOnly.IsPresent) {
							$syncParams = @{
								CsvUser = $csvUser
								ActiveDirectoryAttributes = $attribMismatches.ADShouldBe
								Identity = $adUserMatch.MatchedAduser.samAccountName
							}
							Write-Verbose -Message "Running SyncCompanyUser with params: [$($syncParams | Out-String)]"
							SyncCompanyUser @syncParams
						}
					} elseif ($attribMismatches -eq $false) {
						$logAttribs = @{
							CSVAttributeName = 'SyncError'
							CSVAttributeValue = 'SyncError'
							ADAttributeName = 'SyncError'
							ADAttributeValue = 'SyncError'
						}

					} else {
						Write-Verbose -Message "No attributes found to be mismatched between CSV and AD user account for user [$csvIdValue]"
						$logAttribs = @{
							CSVAttributeName = 'AlreadyInSync'
							CSVAttributeValue = 'AlreadyInSync'
							ADAttributeName = 'AlreadyInSync'
							ADAttributeValue = 'AlreadyInSync'
						}
					}
				} else {
					if (-not ($csvIds = @(GetCsvIdField -CsvUser $csvUser -FieldMatchMap $FieldMatchMap).where({ $_.Field }))) {
						throw 'No CSV id fields were found.'
					}

					$csvIdField = $csvIds.Field -join ','
					## No ID fields are populated
					if (-not ($csvIds | Where-Object {$_.Value})) {
						$csvIdValue = 'N/A'
						Write-Verbose -Message 'No CSV user identifier could be found'
					} elseif ($csvIds | Where-Object { $_.Value}) { ## at least one ID field is populated
						$csvIdValue = $csvIds.Value -join ','
					}
					$logAttribs = @{
						CSVAttributeName = 'NoMatch'
						CSVAttributeValue = 'NoMatch'
						ADAttributeName = 'NoMatch'
						ADAttributeValue = 'NoMatch'
					}

				}
				WriteLog -CsvIdentifierField $csvIdField -CsvIdentifierValue $csvIdValue -Attributes $logAttribs
			})
		}
		catch
		{
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}