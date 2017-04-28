$config = Import-PowerShellDataFile -Path "$PSScriptRoot\Configuration.psd1"
$Defaults = $config.Defaults
$AdToCsvFieldMap = $config.FieldMap

## Load the System.Web type to generate random password
Add-Type -AssemblyName 'System.Web'

#region Functions
function GetCompanyAdUser
{
	[OutputType([Microsoft.ActiveDirectory.Management.ADUser])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$All
	)
	begin
	{
		$ErrorActionPreference = 'Stop'
		Write-Verbose -Message "Finding all enabled AD users in domain with the $($Defaults.FieldMatchIds.AD) field used."
	}
	process
	{
		try
		{
			## Find all users that have the unique AD ID and are enabled
			$params = @{
				Properties = [array]$AdToCsvFieldMap.Keys
			}
			if ($All.IsPresent) {
				$params.Filter = '*'
			} else {
				$params.LDAPFilter = "(&($($Defaults.FieldMatchIds.AD)=*)(!userAccountControl:1.2.840.113556.1.4.803:=2))"
			}
			
			if ($Defaults.Credential) {
				$params.Credential = $Defaults.Credential
			}
			if ($Defaults.DomainController) {
				$params.Server = $Defaults.DomainController
			}
			Get-AdUser @params
		}
		catch
		{
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}

function GetCompanyCsvUser
{
	[OutputType([pscustomobject])]
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path -Path $_ -PathType Leaf})]
		[string]$CsvFilePath = $Defaults.InputCsvFilePath
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
			Import-Csv -Path $CsvFilePath
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
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object[]]$AdUsers = (GetCompanyAdUser),

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[pscustomobject[]]$CsvUsers = (GetCompanyCsvUser)
	)
	begin
	{
		$ErrorActionPreference = 'Stop'
		Write-Verbose -Message "Beginning Company AD <--> CSV compare..."
	}
	process
	{
		try
		{
			Write-Verbose -Message "Found [$($adUsers.Count)] enabled AD users."
			Write-Verbose -Message "Found [$($csvUsers.Count)] users in CSV."
			
			@($csvUsers).foreach({
				$output = @{
					CsvUser = $_
					AdUser = $null
					Match = $false
				}
				if ($adUserMatch = FindUserMatch -AdUsers $adUsers -CsvUser $_) {
					$output.AdUser = $adUserMatch
					$output.Match = $true 
				}
				[pscustomobject]$output
			})
		}
		catch
		{
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}

function FindUserMatch
{
	[OutputType()]
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

	$csvMatchFieldValue = $CsvUser.($Defaults.FieldMatchIds.CSV)
	if ($matchedAdUser = @($AdUsers).where({ $_.($Defaults.FieldMatchIds.AD) -eq $csvMatchFieldValue })) {
		Write-Verbose -Message "Found AD match for CSV user [$csvMatchFieldValue]: [$($matchedAdUser.($Defaults.FieldMatchIds.AD))]"
		$matchedAdUser
	} else {
		Write-Verbose -Message "No user match found for CSV user [$csvMatchFieldValue]"
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
		[object]$CsvUser
	)

	foreach ($csvProp in ($CsvUser.PSObject.Properties | Where { ($_.Name -in $AdToCsvFieldMap.Values) })) {
		
		## Ensure we're going to be checking the value on the correct CSV property and AD attribute
		$matchingAdAttribName = ($AdToCsvFieldMap.GetEnumerator() | where { $_.Value -eq $csvProp.Name }).Name
		if ($adAttribMatch = $AdUser.PSObject.Properties | where { $_.Name -eq $matchingAdAttribName }) {
			if (-not $adAttribMatch.Value) {
				$adAttribMatch.Value = ''
			}
			if (-not $csvProp.Value) {
				$csvProp.Value = ''
			}
			if ($adAttribMatch.Value -ne $csvProp.Value) {
				[pscustomobject]@{
					CSVAttributeName = $csvProp.Name
					CSVAttributeValue = $csvProp.Value
					ADAttributeName = $adAttribMatch.Name
					ADAttributeValue = $adAttribMatch.Value
				}
				Write-Verbose -Message "AD attribute mismatch found on CSV property: [$($csvProp.Name)]. Value is [$($adAttribMatch.Value)] and should be [$($csvProp.Value)]"
			}
		}
	}
}

function SyncCompanyUser
{
	[OutputType([hashtable])]
	[CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[Microsoft.ActiveDirectory.Management.ADUser]$AdUser,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser
	)

	$id = $CsvUser.($Defaults.FieldMatchIds.CSV)

	if ($attribMismatches = FindAttributeMismatch -AdUser $AdUser -CsvUser $CsvUser) {
		$replaceHt = @{}
		foreach ($obj in $attribMismatches) {
			$replaceHt.($obj.ADAttributeName) = $obj.CSVAttributeValue
		}

		$params = @{
			Identity = $id
			Replace = $replaceHt
			#WhatIf = $true
		}
		if ($Defaults.Credential) {
			$params.Credential = $Credential
		}
		if ($Defaults.DomainController) {
			$params.Server = $Defaults.DomainController
		}
		if ($PSCmdlet.ShouldProcess("User: [$id] AD attribs: $($replaceHt.Keys -join ',')",'Set AD attributes'))
		{
			Write-Verbose -Message "Setting the following AD attributes for user [$id]: $($replaceHt | Out-String)"
			Set-AdUser @params	
		}
	} else {
		Write-Verbose -Message "No attributes found to be mismatched between CSV and AD user account for user [$id]"
		$attribMisMatches = [pscustomobject]@{
			CSVAttributeName = 'AlreadyInSync'
			CSVAttributeValue = 'AlreadyInSync'
			ADAttributeName = 'AlreadyInSync'
			ADAttributeValue = 'AlreadyInSync'
		}
	}
	$attribMismatches

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

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Identifier,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[pscustomobject[]]$Attributes
	)
	begin
	{
		$ErrorActionPreference = 'Stop'
	}
	process
	{
		try
		{
			$Attributes | foreach {
				$_ | Add-Member -MemberType NoteProperty -Name 'Identifier' -Force -Value $Identifier
			}
			
			$Attributes | Export-Csv -Path $FilePath -Append -NoTypeInformation
		}
		catch
		{
			$PSCmdlet.ThrowTerminatingError($_)
		}
	}
}

function Invoke-AdSync
{
	[OutputType()]
	[CmdletBinding()]
	param
	()
	begin
	{
		$ErrorActionPreference = 'Stop'
	}
	process
	{
		try
		{
			$userCompareResults = CompareCompanyUser
			foreach ($user in $userCompareResults) {
				$id = $user.CSVUser.($Defaults.FieldMatchIds.CSV)
				if ($user.Match) {
					$syncedAttribs = SyncCompanyUser -AdUser $user.ADUser -CsvUser $user.CSVUser
					WriteLog -Identifier $id -Attributes $syncedAttribs	
				} else {
					WriteLog -Identifier $id -Attributes ([pscustomobject]@{
						CSVAttributeName = 'NoMatch'
						CSVAttributeValue = 'NoMatch'
						ADAttributeName = 'NoMatch'
						ADAttributeValue = 'NoMatch'
					})
				}
			}
		}
		catch
		{
			$PSCmdlet.ThrowTerminatingError($_)
		}
	}
}
#endregion