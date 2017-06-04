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

	$context = New-Object -TypeName System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList 'Domain',$Env:USERDNSDOMAIN
	$DirectoryEntry = New-Object -TypeName DirectoryServices.DirectoryEntry
	$DirectorySearcher = new-object -TypeName System.DirectoryServices.DirectorySearcher
	$DirectorySearcher.PageSize = 1000
	$DirectorySearcher.SearchRoot = $DirectoryEntry
	if (-not $PSBoundParameters.ContainsKey('Identity')) {
		$result = FindAdUser -DirectorySearcher $DirectorySearcher
	} else {
		$DirectorySearcher.Filter = "(&(objectCategory=user)({0}={1}))" -f ([array]$Identity.Keys)[0],([array]$Identity.Values)[0]
		$result = FindAdUser -DirectorySearcher $DirectorySearcher
	}

	if ($OutputAs -eq 'SearchResult') {
		$result
	} else {
		@($result).foreach({
			[System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($Context, ($_.path -replace 'LDAP://'))
		})
	}
}

function SaveAdUser
{
	[OutputType([void])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Parameters
	)

	$adsPath = [adsi]$adsPath
	$adspath.Put(([array]$Parameters.Attribute.Keys)[0], ([array]$Parameters.Attribute.Values)[0])
	$adspath.SetInfo()
	
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
		[hashtable]$Attribute
	)

	$user = GetAdUser -Identity $Identity -OutputAs 'SearchResult'
	$adspath = $user.Properties.adspath -as [string]
	SaveAdUser -Parameters @{ AdsPath = $adspath; Attribute = $Attribute }
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
		[string[]]$Header
	)

	$csvHeaders = GetCsvColumnHeaders -CsvFilePath $CsvFilePath
	$matchedHeaders = $csvHeaders | Where-Object { $_ -in $Header }
	if (@($matchedHeaders).Count -ne @($Header).Count) {
		$false
	} else {
		$true
	}
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

	Write-Verbose "AD-CSV field map values are [$($FieldSyncMap.Values | Out-String)]"
	$csvPropertyNames = $CsvUser.PSObject.Properties.Name
	$AdPropertyNames = ($AdUser | Get-Member -MemberType Property).Name
	Write-Verbose "CSV properties are: [$($csvPropertyNames -join ',')]"
	Write-Verbose "ADUser props: [$($AdPropertyNames -join ',')]"
	foreach ($csvProp in ($csvPropertyNames | Where-Object { $_ -in @($FieldSyncMap.Keys) })) {
		## Ensure we're going to be checking the value on the correct CSV property and AD attribute
		$matchingAdAttribName = ($FieldSyncMap.GetEnumerator() | Where-Object { $_.Key -eq $csvProp }).Value
		Write-Verbose -Message "Matching AD attrib name is: [$($matchingAdAttribName)]"
		Write-Verbose -Message "Matching CSV field is: [$($csvProp)]"
		if ($adAttribMatch = $AdPropertyNames | Where-Object { $_ -eq $matchingAdAttribName }) {
			Write-Verbose -Message "ADAttribMatch: [$($adAttribMatch)]"
			if (-not $AdUser.$adAttribMatch) {
				Write-Verbose -Message "[$($adAttribMatch)] value is null. Converting to empty string,.."
				$AdUser | Add-Member -MemberType NoteProperty -Name $adAttribMatch -Force -Value ''
			}
			if (-not $CsvUser.$csvProp) {
				$CsvUser.$csvProp = ''
			}
			if ($AdUser.$adAttribMatch -ne $CsvUser.$csvProp) {
				@{
					CSVAttributeName = $csvProp
					CSVAttributeValue = $CsvUser.$csvProp
					ADAttributeName = $adAttribMatch
					ADAttributeValue = $AdUser.$adAttribMatch
				}
				Write-Verbose -Message "AD attribute mismatch found on CSV property: [$($csvProp)]. Value is [$($AdUser.$adAttribMatch)] and should be [$($CsvUser.$csvProp)]"
			}
		}
	}
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
		[hashtable[]]$Attributes,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Identifier
	)

	$ErrorActionPreference = 'Stop'
	try {
		$setParams = @{
			Identity = @{ $Identifier = $AdUser.$Identifier }
		}
		foreach ($attrib in $Attributes) {
			$setParams.Attribute = @{ $attrib.ADAttributeName = $attrib.CSVAttributeValue }
			if ($PSCmdlet.ShouldProcess("User: [$($AdUser.$Identifier)] AD attribs: [$($setParams.Attribute.Keys -join ',')]",'Set AD attributes')) {
				Write-Verbose -Message "Setting the following AD attributes for user [$Identifier]: $($setParams.Attribute | Out-String)"
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
				Write-ProgressHelper -Message "Attempting to find attribute mismatch for user in CSV row [$($stepCounter + 1)]" -StepNumber ($stepCounter++)
				$csvUser = $_
				if ($adUserMatch = FindUserMatch -CsvUser $csvUser -FieldMatchMap $FieldMatchMap) {
					Write-Verbose -Message 'Match'
					$csvIdMatchedon = $aduserMatch.CsvIdMatchedOn
					$adIdMatchedon = $aduserMatch.AdIdMatchedOn
					$csvIdValue = $csvUser.$csvIdMatchedon
					$csvIdField = $csvIdMatchedon
					$attribMismatches = FindAttributeMismatch -AdUser $adUserMatch.MatchedAdUser -CsvUser $csvUser -FieldSyncMap $FieldSyncMap
					if ($attribMismatches) {
						$logAttribs = $attribMismatches
						if (-not $ReportOnly.IsPresent) {
							SyncCompanyUser -AdUser $adUserMatch.MatchedADUser -CsvUser $csvUser -Attributes $attribMismatches -Identifier $adIdMatchedOn
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