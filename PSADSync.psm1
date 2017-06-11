Add-Type -AssemblyName 'System.DirectoryServices.AccountManagement'

function FindAdUser
{
	[OutputType([System.DirectoryServices.SearchResult])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.DirectoryServices.DirectorySearcher]$DirectorySearcher
	)

	$DirectorySearcher.FindAll()
}

function GetCurrentDomainName
{
	[OutputType('string')]
	[CmdletBinding()]
	param
	()

	[System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
	
}

function NewDirectorySearcherUserFilter
{
	[OutputType('string')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Elements
	)
	
	$baseString = '(&(objectCategory=person)(objectClass=User)'

	$keyValPairs = $Elements.GetEnumerator().foreach({
		'({0}={1})' -f $_.Key,$_.Value
	})

	'{0}(&{1}))' -f $baseString,($keyValPairs -join '')

}

function GetAdUser
{
	[CmdletBinding()]
	param
	(
		[OutputType('System.DirectoryServices.AccountManagement.UserPrincipal','System.DirectoryServices.SearchResult')]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Identity,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateSet('SearchResult','UserPrincipal')]
		[string]$OutputAs = 'UserPrincipal'
	)

	$domainDn = $(([adsisearcher]"").Searchroot.path)

	$DirectorySearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher
	$DirectorySearcher.PageSize = 1000
	$DirectorySearcher.SearchRoot = $domainDN

	if ($PSBoundParameters.ContainsKey('Identity')) {
		$idField = ([array]$Identity.Keys)[0]
		$idValue = ([array]$Identity.Values)[0]

		$filter = NewDirectorySearcherUserFilter -Elements $Identity
		$DirectorySearcher.Filter = $filter
	}

	$result = FindAdUser -DirectorySearcher $DirectorySearcher
	if ($OutputAs -eq 'SearchResult') {
		$result
	} else {
		$Context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', (GetCurrentDomainName))
		@($result).foreach({
			foreach ($user in ([System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($Context, ($_.path -replace 'LDAP://')))) {
				$user.GetUnderlyingObject().Properties
			}
		})
	}
}

function PutAdUser {
	[OutputType([void])]
	[CmdletBinding()]
	param(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.DirectoryServices.DirectoryEntry]$AdsUser,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$AttributeName,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object]$AttributeValue
	)
	$AdsUser.Put($AttributeName,$AttributeValue)
	$AdsUser.SetInfo()
}

function SaveAdUser
{
	[OutputType([void])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.DirectoryServices.DirectoryEntry]$AdsUser,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$AttributeName,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object]$AttributeValue
	)
	if ([string]$AttributeValue -as [DateTime]) {
		$AttributeValue = [datetime]$AttributeValue
	}

	PutAdUser -AdsUser $AdsUser -AttributeName $AttributeName -AttributeValue $AttributeValue
	
}

function ConvertToSchemaAttribute
{
	[OutputType('string')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Attribute
	)

	switch ($Attribute)
	{
		'accountExpires' {
			'AccountExpirationDate'
		}
		default {
			$_
		}
	}	
	
}

function ConvertToIdentity
{
	[OutputType('hashtable')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$String
	)

	switch -regex ($String)
	{
		'^(?<givenName>\w+)\s+(?<sn>\w+)$' { ## John Doe
			@{ givenName = $Matches.givenName; sn = $Matches.sn }
		}
		'^(?<sn>\w+),\s?(?<givenName>\w+)$' { ## Doe,John
			@{ givenName = $Matches.givenName; sn = $Matches.sn }
		}
		'^(?<samAccountName>\w+)$' { ## jdoe
			@{ samAccountName = $Matches.samAccountName }
		}
		'^(?<distinguishedName>(\w+[=]{1}\w+)([,{1}]\w+[=]{1}\w+)*)$' {
			@{ distinguishedName = $Matches.distinguishedName }
		}
		default {
			throw "Unrecognized input: [$_]: Unable to convert to identity hashtable."
		}
	}
	
}

function ConvertToSchemaValue
{
	[OutputType('string')]
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
		'manager' {
			$identity = ConvertToIdentity -String $AttributeValue
			$user = GetAdUser -Identity $identity
			$user.DistinguishedName
		}
		default {
			$AttributeValue
		}
	}

}

function SetAdUser
{
	[OutputType([void])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Identity,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$ActiveDirectoryAttributes
	)	
	$srcResultUser = GetAdUser -Identity $Identity -OutputAs SearchResult
	$adspath = $srcResultUser.Properties.adspath -as [string]
	$AdsUser = $adspath -as [adsi]

	foreach ($attrib in $ActiveDirectoryAttributes.GetEnumerator()) {
		$saveAdParams = @{
			AdsUser = $AdsUser
			AttributeName = (ConvertToSchemaAttribute -Attribute $attrib.Key)
			AttributeValue = (ConvertToSchemaValue -AttributeName $attrib.Key -AttributeValue $attrib.Value)
		}
		Write-Verbose -Message "Running SaveAdUser with params: [$($saveAdParams | Out-String)]"
		SaveAdUser @saveAdParams
	} 
}

function Get-CompanyAdUser
{
	[OutputType([System.DirectoryServices.AccountManagement.UserPrincipal])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$FieldMatchMap
	)
	begin
	{
		$ErrorActionPreference = 'Stop'
		Write-Verbose -Message "Finding all AD users in domain with properties: $($FieldMatchMap.Values -join ',')"
	}
	process
	{
		try
		{
			$whereFilter = { $adUser = $_; $FieldMatchMap.Values | Where-Object { $adUser.$_ }}
			@(GetAdUser).where({$whereFilter})
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

function Get-AvailableAdUserAttributes {
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
	[OutputType('bool')]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Name
	)

	if ($Name -in (Get-AvailableAdUserAttributes).ValidName) {
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
			$whereFilter = { '*' }
			if ($PSBoundParameters.ContainsKey('Exclude'))
			{
				$conditions = $Exclude.GetEnumerator() | ForEach-Object { "(`$_.'$($_.Key)' -ne '$($_.Value)')" }
				$whereFilter = [scriptblock]::Create($conditions -join ' -and ')
			}
			Import-Csv -Path $CsvFilePath | Where-Object -FilterScript $whereFilter
		}
		catch
		{
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
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

	$FieldSyncMap.GetEnumerator().foreach({
		if ($_.Key -is 'scriptblock') {
			## Replace $_ with $CsvUser
			$csvFieldScript = $_.Key.ToString() -replace '$_','$CsvUser'
			$csvFieldName = & ([scriptblock]::Create($csvFieldScript))
		} else {
			$csvFieldName = $_.Key
		}
		$adAttribName = $_.Value
		
		## Remove the null fields
		if (-not $AdUser.$adAttribName) {
			$AdUser | Add-Member -MemberType NoteProperty -Name $adAttribName -Force -Value ''
		}
		if (-not $CsvUser.$csvFieldName) {
			$CsvUser.$csvFieldName = ''
		}

		## Compare the two property values and return the AD attribute name and value to be synced
		if ($AdUser.$adAttribName -ne $CsvUser.$csvFieldName) {
			@{
				ActiveDirectoryAttribute = @{ $adAttribName = $AdUser.$adAttribName }
				CSVField = @{ $csvFieldName = $CsvUser.$csvFieldName }
				ADShouldBe = @{ $adAttribName = $CsvUser.$csvFieldName }
			}
			Write-Verbose -Message "AD attribute mismatch found on AD attribute: [$($adAttribName)]. Value is [$($AdUser.$adAttribName)] and should be [$($CsvUser.$csvFieldName)]"
		}
	})
}

function SyncCompanyUser
{
	[OutputType()]
	[CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable[]]$ActiveDirectoryAttributes,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Identifier
	)

	$ErrorActionPreference = 'Stop'
	try {
		$setParams = @{
			Identity = @{ $Identifier = [string]($AdUser.$Identifier) }
		}
		foreach ($ht in $ActiveDirectoryAttributes) {
			$setParams.ActiveDirectoryAttributes = $ht
			if ($PSCmdlet.ShouldProcess("User: [$($AdUser.$Identifier)] AD attribs: [$($ht.Keys -join ',')] to [$($ht.Values -join ',')]",'Set AD attributes')) {
				Write-Verbose -Message "Running SetAdUser with params: [$($setParams | Out-String)]"
				SetAdUser @setParams
			}
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
					throw 'One or more AD attributes in FieldSyncMap do not exist. Use Get-AvailableAdUserAttributes for a list of available attributes.'
				}
			})

			Write-Host 'Enumerating all Active Directory users. This may take a few minutes depending on the number of users...'
			if (-not ($script:adUsers = Get-CompanyAdUser -FieldMatchMap $FieldMatchMap)) {
				throw 'No AD users found'
			}
			Write-Host 'Active Directory user enumeration complete.'
			Write-Host 'Enumerating all CSV users...'
			if (-not ($csvusers = Get-CompanyCsvUser @getCsvParams)) {
				throw 'No CSV users found'
			}
			Write-Host 'CSV user enumeration complete.'

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
					$adIdMatchedon = $aduserMatch.AdIdMatchedOn
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
								AdUser = $adUserMatch.MatchedADUser
								CsvUser = $csvUser
								ActiveDirectoryAttributes = $attribMismatches.ADShouldBe
								Identifier = $adIdMatchedOn
							}
							Write-Verbose -Message "Running SyncCompanyUser with params: [$($syncParams | Out-String)]"
							SyncCompanyUser @syncParams
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