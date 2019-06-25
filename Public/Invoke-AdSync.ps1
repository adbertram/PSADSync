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
		[string]$LogFilePath,

		[Parameter()]
		[switch]$LogOverwrite
	)
	begin {
		$ErrorActionPreference = 'Stop'
		$logParams = @{ }
		if ($PSBoundParameters.ContainsKey('LogFilePath')) {
			$logParams["FilePath"] = $LogFilePath
		}
		if ($PSBoundParameters.ContainsKey('LogOverwrite')) {
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

			$FieldSyncMap.GetEnumerator().where({ $_.Value -is 'string' }).foreach({
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
							$csvIdValue = ($CSVAttemptedMatchIds | % { $csvUser.$_ }) -join ','
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