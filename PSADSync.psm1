$config = Import-PowerShellDataFile -Path "$PSScriptRoot\Configuration.psd1"
$Defaults = $config.Defaults
$AdToCsvFieldMap = $config.FieldMap

## Load the System.Web type to generate random password
Add-Type -AssemblyName 'System.Web'

function Get-CompanyAdUser
{
	[OutputType([Microsoft.ActiveDirectory.Management.ADUser])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$All,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[pscredential]$Credential = $Defaults.Credential,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$DomainController = $Defaults.DomainController,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string[]]$Properties = '*'
	)
	begin
	{
		$ErrorActionPreference = 'Stop'
		Write-Verbose -Message "Finding all enabled AD users in domain with field(s) used: $($Defaults.FieldMatchIds.AD -join ',')"
	}
	process
	{
		try
		{
			## Find all users that have the unique AD ID and are enabled
			$params = @{
				Properties = $Properties
			}
			if ($Credential)
			{
				$params.Credential = $Credential
			}

			if ($DomainController) {
				$params.Server = $DomainController
			}

			$whereFilter = { $adUser = $_; $Defaults.FieldMatchIds.AD | where { $adUser.$_ }}
			if ($All.IsPresent) {
				$params.Filter = '*'
			} else {
				$params.LDAPFilter = "(!userAccountControl:1.2.840.113556.1.4.803:=2)"
			}
			@(Get-AdUser @params).where($whereFilter)
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
		[string]$CsvFilePath = $Defaults.InputCsvFilePath,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string[]]$Header
	)

	$csvHeaders = GetCsvColumnHeaders -CsvFilePath $CsvFilePath
	$matchedHeaders = $csvHeaders | where { $_ -in $Header }
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
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path -Path $_ -PathType Leaf})]
		[string]$CsvFilePath = $Defaults.InputCsvFilePath,

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
				$conditions = $Exclude.GetEnumerator() | foreach { "(`$_.'$($_.Key)' -ne '$($_.Value)')" }
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

function CompareCompanyUser
{
	[OutputType([pscustomobject])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object[]]$AdUsers,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject[]]$CsvUsers
	)

	$ErrorActionPreference = 'Stop'
	Write-Verbose -Message "Beginning Company AD <--> CSV compare..."
	Write-Verbose -Message "Found [$(@($AdUsers).Count)] enabled AD users."
	Write-Verbose -Message "Found [$(@($csvUsers).Count)] users in CSV."
	
	@($csvUsers).foreach({
		$output = @{
			CsvUser = $_
			AdUser = $null
			IdMatchedOn = $null
			Match = $false
		}
		if ($adUserMatch = FindUserMatch -AdUsers $AdUsers -CsvUser $_) {
			$output.AdUser = $adUserMatch.MatchedAdUser
			$output.IdMatchedOn = $adUserMatch.IdMatchedOn
			$output.Match = $true 
		}
		[pscustomobject]$output
	})
}

function FindUserMatch
{
	[OutputType([pscustomobject])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object[]]$AdUsers,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser
	)
	$ErrorActionPreference = 'Stop'

	foreach ($matchId in $Defaults.FieldMatchIds) {
		$adMatchField = $matchId.AD
		$csvMatchField = $matchId.CSV
		Write-Verbose "Match fields: CSV - [$($csvMatchField)], AD - [$($adMatchField)]"
		if ($csvMatchVal = $CsvUser.$csvMatchField) {
			Write-Verbose -Message "CsvFieldMatchValue is [$($csvMatchVal)]"
			if ($matchedAdUser = @($AdUsers).where({ $_.$adMatchField -eq $csvMatchVal })) {
				Write-Verbose -Message "Found AD match for CSV user [$csvMatchVal]: [$($matchedAdUser.$adMatchField)]"
				[pscustomobject]@{
					MatchedAdUser = $matchedAdUser
					IdMatchedOn = $csvMatchField
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
	[OutputType([pscustomobject])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser
	)

	$ErrorActionPreference = 'Stop'

	Write-Verbose "AD-CSV field map values are [$($AdToCsvFieldMap.Values | Out-String)]"
	$csvPropertyNames = $CsvUser.PSObject.Properties.Name
	$AdPropertyNames = ($AdUser | Get-Member -MemberType Property).Name
	Write-Verbose "CSV properties are: [$($csvPropertyNames -join ',')]"
	Write-Verbose "ADUser props: [$($AdPropertyNames -join ',')]"
	foreach ($csvProp in ($csvPropertyNames | Where { ($_ -in @($AdToCsvFieldMap.Values)) })) {
		
		## Ensure we're going to be checking the value on the correct CSV property and AD attribute
		$matchingAdAttribName = ($AdToCsvFieldMap.GetEnumerator() | where { $_.Value -eq $csvProp }).Name
		Write-Verbose -Message "Matching AD attrib name is: [$($matchingAdAttribName)]"
		Write-Verbose -Message "Matching CSV field is: [$($csvProp)]"
		if ($adAttribMatch = $AdPropertyNames | where { $_ -eq $matchingAdAttribName }) {
			Write-Verbose -Message "ADAttribMatch: [$($adAttribMatch)]"
			if (-not $AdUser.$adAttribMatch) {
				Write-Verbose -Message "[$($adAttribMatch)] value is null. Converting to empty string,.."
				$AdUser | Add-Member -MemberType NoteProperty -Name $adAttribMatch -Force -Value ''
			}
			if (-not $CsvUser.$csvProp) {
				$CsvUser.$csvProp = ''
			}
			if ($AdUser.$adAttribMatch -ne $CsvUser.$csvProp) {
				[pscustomobject]@{
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
		[Microsoft.ActiveDirectory.Management.ADUser]$AdUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject[]]$Attributes,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Identifier,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[pscredential]$Credential = $Defaults.Credential,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$DomainController = $Defaults.DomainController
	)

	$ErrorActionPreference = 'Stop'

	$replaceHt = @{}
	foreach ($obj in $Attributes) {
		$replaceHt.($obj.ADAttributeName) = $obj.CSVAttributeValue
	}

	$adIdentity = $AdUser.$Identifier

	$params = @{
		Identity = $adIdentity
		Replace = $replaceHt
	}
	if ($Credential) {
		$params.Credential = $Credential
	}
	if ($DomainController) {
		$params.Server = $DomainController
	}
	if ($PSCmdlet.ShouldProcess("User: [$Identifier] AD attribs: $($replaceHt.Keys -join ',')",'Set AD attributes'))
	{
		Write-Verbose -Message "Setting the following AD attributes for user [$Identifier]: $($replaceHt | Out-String)"
		Set-AdUser @params	
	}
}

function NewRandomPassword
{
	[CmdletBinding()]
	[OutputType([System.Security.SecureString])]
	param
	(
		[Parameter()]
		[ValidateRange(8, 64)]
		[uint32]$Length = (Get-Random -Minimum 20 -Maximum 32),

		[Parameter()]
		[ValidateRange(0, 8)]
		[uint32]$Complexity = 3
	)

	try
	{
		$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop;

		# Generate a password with the specified length and complexity.
		$password = [System.Web.Security.Membership]::GeneratePassword($Length, $Complexity);

		# Remove any restricted characters that makes the password unfriendly to XML.
		@('"', "'", '<', '>', '&', '/') | ForEach-Object {
			$password = $password.Replace($_, '');
		}

		# Convert the password to a secure string so we don't put plain text passwords on the pipeline.
		[pscustomobject]@{
			SecurePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
			PlainTextPassword = $password
		}
	}
	catch
	{
		Write-Error -Message $_.Exception.Message
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
		[string]$FilePath = "$PSScriptRoot\CsvToActiveDirectorySync.log",

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierField,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvIdentifierValue,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject[]]$Attributes
	)
	
	$ErrorActionPreference = 'Stop'
	
	$time = Get-Date -Format 'g'
	$Attributes | foreach {
		$_ | Add-Member -MemberType NoteProperty -Name 'CsvIdentifierValue' -Force -Value $CsvIdentifierValue
		$_ | Add-Member -MemberType NoteProperty -Name 'CsvIdentifierField' -Force -Value $CsvIdentifierField
		$_ | Add-Member -MemberType NoteProperty -Name 'Time' -Force -Value $time
	}
	
	$Attributes | Export-Csv -Path $FilePath -Append -NoTypeInformation

}

function TestNullCsvIdField
{
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[object]$CsvUser
	)


	if (-not ($Defaults.FieldMatchIds.CSV | where { $CSVUser.$_ })) {
		$false
	} else {
		$true
	}
}

function Invoke-AdSync
{
	[OutputType()]
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CsvFilePath = $Defaults.InputCsvFilePath,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$ReportOnly,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Exclude,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$DomainController
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

			$getAdUserParams = @{
				Properties = ([array]$AdToCsvFieldMap.Keys)
			}
			if ($PSBoundParameters.ContainsKey('DomainController'))
			{
				$getAdUserParams.DomainController = $DomainController
			}
			
			$compParams = @{
				CsvUsers = Get-CompanyCsvUser @getCsvParams
				AdUsers = Get-CompanyAdUser @getAdUserParams
			}
			$userCompareResults = CompareCompanyUser @compParams
			foreach ($user in $userCompareResults) {
				if ($user.Match) {
					$csvIdValue = $user.CsvUser.($user.IdMatchedOn)
					$csvIdField = $user.IdMatchedOn
					$attribMismatches = FindAttributeMismatch -AdUser $user.ADUser -CsvUser $user.CSVUser
					if ($attribMismatches) {
						$logAttribs = $attribMismatches
						if (-not $ReportOnly.IsPresent) {
							SyncCompanyUser -AdUser $user.ADUser -CsvUser $user.CSVUser -Attributes $attribMismatches -Identifier $user.IdMatchedOn
						}
					} else {
						Write-Verbose -Message "No attributes found to be mismatched between CSV and AD user account for user [$csvIdValue]"
						$logAttribs = [pscustomobject]@{
							CSVAttributeName = 'AlreadyInSync'
							CSVAttributeValue = 'AlreadyInSync'
							ADAttributeName = 'AlreadyInSync'
							ADAttributeValue = 'AlreadyInSync'
						}
					}
				} else {
					
					if (-not (TestNullCsvIdField -CsvUser $user.CsvUser)) {
						$csvIdValue = 'N/A'
						Write-Warning -Message 'The CSV user identifier field could not be found!'
					} else {
						$csvIdFields = $Defaults.FieldMatchIds.CSV
						$csvIdField = $csvIdFields -join ','
						$csvIdValue = ($csvIdFields | foreach { $user.CSVUser.$_ }) -join ','
						$logAttribs = ([pscustomobject]@{
							CSVAttributeName = 'NoMatch'
							CSVAttributeValue = 'NoMatch'
							ADAttributeName = 'NoMatch'
							ADAttributeValue = 'NoMatch'
						})
					}
				}
				WriteLog -CsvIdentifierField $csvIdField -CsvIdentifierValue $csvIdValue -Attributes $logAttribs
			}
		}
		catch
		{
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}