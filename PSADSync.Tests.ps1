,#region import modules
$ThisModule = "$($MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$', '').psd1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psd1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force

Import-Module -Name $ThisModule -Force -ErrorAction Stop
#endregion

describe 'Module-level tests' {
	
	it 'should validate the module manifest' {
	
		{ Test-ModuleManifest -Path $ThisModule -ErrorAction Stop } | should not throw
	}

	it 'should pass all error-level script analyzer rules' {

		$excludedRules = @(
			'PSUseShouldProcessForStateChangingFunctions',
			'PSUseToExportFieldsInManifest',
			'PSAvoidInvokingEmptyMembers',
			'PSUsePSCredentialType',
			'PSAvoidUsingPlainTextForPassword'
		)

		Invoke-ScriptAnalyzer -Path $PSScriptRoot -ExcludeRule $excludedRules -Severity Error | should benullorempty
	}
}

InModuleScope $ThisModuleName {

	$script:AllAdsiUsers = 0..10 | ForEach-Object {
		$i = $_
		$adsiUser = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
		$amParams = @{
			MemberType = 'NoteProperty'
			Force = $true
		}
		$props = @{
			'Name' = 'nameval'
			'Enabled' = $true
			'SamAccountName' = 'samval'
			'GivenName' = 'givennameval'
			'Surname' = 'surnameval'
			'DisplayName' = 'displaynameval'
			'OtherProperty' = 'otherval'
			'EmployeeId' = 1
			'Title' = 'titleval'
		}
		$props.GetEnumerator() | ForEach-Object {
			if ($_.Key -eq 'Enabled') {
				if ($i % 2) {
					$adsiUser | Add-Member @amParams -Name $_.Key -Value $false
				} else {
					$adsiUser | Add-Member @amParams -Name $_.Key -Value $true
				}
			} else {
				$adsiUser | Add-Member @amParams -Name $_.Key -Value "$($_.Value)$i"
			}
		}
		if ($i -eq 5) {
			$adsiUser | Add-Member @amParams -Name 'samAccountName' -Value $null
		}
		if ($i -eq 6) { 
			$adsiUser | Add-Member @amParams -Name 'EmployeeId' -Value $null
		}
		$adsiUser
	}

	$script:AllCsvUsers = 0..15 | ForEach-Object {
		$i = $_
		$output = @{ 
			AD_LOGON = "nameval$i"
			PERSON_NUM = "1$i" 
			ExcludeCol = 'dontexcludeme'
		}
		if ($i -eq (Get-Random -Maximum 9)) {
			$output.'AD_LOGON' = $null
			$output.ExcludeCol = 'excludeme'
		}
		if ($i -eq (Get-Random -Maximum 9)) {
			$output.'PERSON_NUM' = $null
		}
		[pscustomobject]$output 
	}

	describe 'Get-CompanyCsvUser' {
	
		$commandName = 'Get-CompanyCsvUser'
	
		#region Mocks
			$script:csvUsers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 123
					OtherAtrrib = 'x'
					ExcludeCol = 'excludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'foo2'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'excludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = 12345
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
			)

			mock 'Import-Csv' {
				$script:csvUsers
			}

			mock 'Test-Path' {
				$true
			}

			$script:csvUsersNullConvert = $script:csvUsers | ForEach-Object { if (-not $_.'AD_LOGON') { $_.'AD_LOGON' = 'null' } $_ }
		#endregion
		
		$parameterSets = @(
			@{
				CsvFilePath = 'C:\users.csv'
				TestName = 'All users'
			}
			@{
				CsvFilePath = 'C:\users.csv'
				Exclude = @{ ExcludeCol = 'excludeme' }
				TestName = 'Exclude 1 col'
			}
			@{
				CsvFilePath = 'C:\users.csv'
				Exclude = @{ ExcludeCol = 'excludeme';ExcludeCol2 = 'excludeme' }
				TestName = 'Exclude 2 cols'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			Exclude = $parameterSets.where({$_.ContainsKey('Exclude')})
			Exclude1Col = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Count -eq 1)})
			Exclude2Cols = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Count -eq 2)})
			NoExclusions = $parameterSets.where({ -not $_.ContainsKey('Exclude')})
		}

		context 'when at least one column is excluded' {

			mock 'Where-Object' {
				[pscustomobject]@{
					AD_LOGON = 'foo2'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'excludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = 12345
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
			} -ParameterFilter { $FilterScript.ToString() -notmatch '\*' }
		
			it 'should create the expected where filter: <TestName>' -TestCases $testCases.Exclude {
				param($CsvFilePath,$Exclude)
			
				& $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Where-Object'
					Times = $script:csvUsers.Count
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { 
						$PSBoundParameters.FilterScript.ToString() -like "(`$_.`'*' -ne '*')*" }
				}
				Assert-MockCalled @assMParams
			}
		
		}

		it 'when excluding no cols, should return all expected users: <TestName>' -TestCases $testCases.NoExclusions {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object $script:csvUsersNullConvert.'AD_LOGON' $result.'AD_LOGON').InputObject | should benullorempty
		}

		it 'when excluding 1 col, should return all expected users: <TestName>' -TestCases $testCases.Exclude1Col {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object @('foo2','notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
		}
	
		it 'when excluding 2 cols, should return all expected users: <TestName>' -TestCases $testCases.Exclude2Cols {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object @('notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
		}
	}

	describe 'GetCsvColumnHeaders' {
		
		#region Mocks
			mock 'Get-Content' {
				@(
					'"Header1","Header2","Header3"'
					'"Value1","Value2","Value3"'
					'"Value4","Value5","Value6"'
				)
			}
		#endregion

		it 'should return expected headers' {
		
			$result = & GetCsvColumnHeaders -CsvFilePath 'foo.csv'
			Compare-Object $result @('Header1','Header2','Header3') | should benullorempty
		}
		
	}

	describe 'TestCsvHeaderExists' {
		
		#region Mocks
			mock 'GetCsvColumnHeaders' {
				'Header1','Header2','Header3'
			}
		#endregion


		context 'when a header is not in the CSV' {
		
			it 'should return $false' {
			
				TestCsvHeaderExists -CsvFilePath 'foo.csv' -Header 'nothere' | should be $false
			}	
		
		}

		context 'when all headers are in the CSV' {

			it 'should return $true' {
				TestCsvHeaderExists -CsvFilePath 'foo.csv' -Header 'Header1','Header2','Header3' | should be $true
			}
	
		}

		context 'when one header is in the CSV' {

			it 'should return $true' {		
				TestCsvHeaderExists -CsvFilePath 'foo.csv' -Header 'Header1' | should be $true
			}

		}
		
	}

	describe 'Get-CompanyAdUser' {
	
		$commandName = 'Get-CompanyAdUser'

	
		#region Mocks
			mock 'GetAdUser' {
				$script:AllAdsiUsers | Where-Object { $_.Enabled }
			} -ParameterFilter { $LdapFilter }

			mock 'GetAdUser' {
				$script:AllAdsiUsers
			} -ParameterFilter { -not $LdapFilter }
		#endregion
		
		$parameterSets = @(
			@{
				FieldMatchMap = @{ 'csvid' = 'adid' }
				TestName = 'All users'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}

		it 'should return all users: <TestName>' -TestCases $testCases.All {
			param($All,$Credential,$FieldMatchMap)
		
			$result = & $commandName @PSBoundParameters
			@($result).Count | should be @($script:AllAdsiUsers).Count
		}

	}

	describe 'FindUserMatch' {
	
		$commandName = 'FindUserMatch'
		
	
		#region Mocks
			mock 'Write-Warning'

			$script:csvUserMatchOnOneIdentifer = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 'nomatch'
				}
			)

			$script:csvUserMatchOnAllIdentifers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 123
				}
			)

			$script:OneblankCsvUserIdentifier = @(
				[pscustomobject]@{
					PERSON_NUM = $null
					AD_LOGON = 'foo'
				}
			)

			$script:AllblankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = $null
				}
			)
			
			$script:noBlankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = 'ffff'
					PERSON_NUM = '111111'
				}
			)

			$script:csvUserNoMatch = @(
				[pscustomobject]@{
					AD_LOGON = 'NotInAd'
					PERSON_NUM = 'nomatch'
				}
			)

			$script:AdUsers = @(
				[pscustomobject]@{
					samAccountName = 'foo'
					EmployeeId = 123
				}
				[pscustomobject]@{
					samAccountName = 'foo2'
					EmployeeId = 111
				}
				[pscustomobject]@{
					samAccountName = 'NotinCSV'
					EmployeeId = 12345
				}
			)

			mock 'Write-Verbose'
		#endregion
		
		$parameterSets = @(
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatchOnOneIdentifer
				FieldMatchMap = @{ 'AD_LOGON' = 'samAccountName' }
				TestName = 'Match on 1 ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatchOnAllIdentifers
				FieldMatchMap = @{ 'PERSON_NUM' = 'EmployeeId' }
				TestName = 'Match on all IDs'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserNoMatch
				FieldMatchMap = @{ 'PERSON_NUM' = 'EmployeeId' }
				TestName = 'No Match'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:OneblankCsvUserIdentifier
				FieldMatchMap = [ordered]@{ 
					'PERSON_NUM' = 'EmployeeId'
					'AD_LOGON' = 'samAccountName'
				}
				TestName = 'One Blank ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:AllblankCsvUserIdentifier
				FieldMatchMap = @{ 
					'PERSON_NUM' = 'EmployeeId'
					'AD_LOGON' = 'samAccountName'
				}
				TestName = 'All Blank IDs'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			MatchOnOneId = $parameterSets.where({$_.TestName -eq 'Match on 1 ID'})
			MatchOnAllIds = $parameterSets.where({$_.TestName -eq 'Match on all IDs'})
			NoMatch = $parameterSets.where({$_.TestName -eq 'No Match'})
			OneBlankId = $parameterSets.where({ $_.CsvUser.AD_LOGON -and -not $_.CsvUser.PERSON_NUM })
			AllBlankIds = $parameterSets.where({ -not $_.CsvUser.AD_LOGON -and (-not $_.CsvUser.PERSON_NUM) })
		}

		context 'When no matches could be found' {
			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.NoMatch {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				& $commandName @PSBoundParameters | should benullorempty
			}
		}

		context 'When one match can be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.CsvIdMatchedOn | should be 'AD_LOGON'
				$result.AdIdMatchedOn | should be 'samAccountName'

			}
		}

		context 'When multiple matches could be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.CsvIdMatchedOn | should be 'PERSON_NUM'
				$result.AdIdMatchedOn | should be 'employeeid'

			}
		}

		context 'when a blank identifier is queried before finding a match' {

			it 'should do nothing: <TestName>' -TestCases $testCases.OneBlankId {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				& $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Write-Verbose'
					Times = 1
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { $PSBoundParameters.Message -match '^CSV field match value' }
				}
				Assert-MockCalled @assMParams
			}

			it 'should return the expected object properties: <TestName>' -TestCases $testCases.OneBlankId {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				$result.MatchedAdUser.samAccountName | should be 'foo'
				$result.CsvIdMatchedOn | should be 'AD_LOGON'
				$result.AdIdMatchedOn | should be 'samAccountName'
			}

		}

		context 'when all identifers are blank' {

			it 'should do nothing: <TestName>' -TestCases $testCases.AllBlankIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				& $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Write-Verbose'
					Times = 2
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { $PSBoundParameters.Message -match '^CSV field match value' }
				}
				Assert-MockCalled @assMParams
			}

		}

		context 'when all identifiers are valid' {
		
			it 'should return the expected object properties: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				@($result.MatchedAdUser).foreach({
					$_.PSObject.Properties.Name -contains 'EmployeeId' | should be $true
				})
				$result.CsvIdMatchedOn | should be 'PERSON_NUM'
				$result.AdIdMatchedOn | should be 'employeeId'
			}
		
		}
	}

	describe 'FindAttributeMismatch' {
	
		$commandName = 'FindAttributeMismatch'
		
		#region Mocks
			mock 'Write-Verbose'

			$script:csvUserMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 123
				OtherAttrib = 'x'
			}

			$script:csvUserNoMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 1111
				OtherAttrib = 'y'
			}

			$script:AdUserMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value $null
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'otherattribmap' -Force -Value $null -PassThru

			$script:AdUserNoMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value 1111
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'otherattribmap' -Force -Value 'y' -PassThru

			mock 'Get-Member' {
				[pscustomobject]@{
					Name = 'samAccountName'
				}
				[pscustomobject]@{
					Name = 'EmployeeId'
				}
				[pscustomobject]@{
					Name = 'otherattribmap'
				}
			}
		#endregion
		
		$parameterSets = @(
			@{
				AdUser = $script:AdUserMisMatch
				CsvUser = $script:csvUserMisMatch
				FieldSyncMap = @{ 'OtherAttrib' = 'otherattribmap' }
				TestName = 'Mismatch'
			}
			@{
				AdUser = $script:AdUserNoMisMatch
				CsvUser = $script:csvUserNoMisMatch
				FieldSyncMap = @{ 'OtherAttrib' = 'otherattribmap' }
				TestName = 'No Mismatch'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			Mismatch = $parameterSets.where({$_.TestName -eq 'Mismatch'})
			NoMismatch = $parameterSets.where({$_.TestName -eq 'No Mismatch'})
		}

		it 'should find the correct AD property names: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser,$FieldSyncMap)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Write-Verbose'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Message -eq "ADUser props: [samAccountName,EmployeeId,otherattribmap]" }
			}
			Assert-MockCalled @assMParams
		}

		it 'should find the correct CSV property names: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser,$FieldSyncMap)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Write-Verbose'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Message -eq 'CSV properties are: [AD_LOGON,PERSON_NUM,OtherAttrib]' }
			}

			Assert-MockCalled @assMParams
		}

		context 'when a mismatch is found' {

			it 'should return the expected objects: <TestName>' -TestCases $testCases.Mismatch {
				param($AdUser,$CsvUser,$FieldSyncMap)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
				$result | should beoftype 'hashtable'
				$result.CSVAttributeName | should be 'OtherAttrib'
				$result.CSVAttributeValue | should be 'x'
				$result.ADAttributeName | should be 'otherattribmap'
				$result.ADAttributeValue | should be ''
			}
		}

		context 'when no mismatches are found' {

			it 'should return nothing: <TestName>' -TestCases $testCases.NoMismatch {
				param($AdUser,$CsvUser,$FieldSyncMap)
			
				& $commandName @PSBoundParameters | should benullorempty
			}

		}
		
		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Verbose' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.All {
				param($AdUser,$CsvUser,$FieldSyncMap)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 'error!'
			}
		}
	
	}

	describe 'SetAduser' {
	
		$commandName = 'SetAduser'
		

		mock 'SaveAdUser'

		mock 'GetAdUser' {
			$obj = New-MockObject -Type 'System.DirectoryServices.SearchResult'
			$obj | Add-Member -MemberType NoteProperty -Name 'Properties' -PassThru -Force -Value ([pscustomobject]@{
				adsPath = 'adspathhere'
			})
		} -ParameterFilter { $OutputAs -eq 'SearchResult' }

		mock 'GetAdUser' {
			New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
		} -ParameterFilter { $OutputAs -ne 'SearchResult' }
	
		$parameterSets = @(
			@{
				Identity = @{ samAccountName = 'samnamehere'}
				Attribute = @{ employeeId = 'empidhere' }
			}
			@{
				Identity = @{ employeeId = 'empidhere'}
				Attribute = @{ displayName = 'displaynamehere' }
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'returns nothing' -TestCases $testCases.All {
			param($Identity,$Attribute)

			& $commandName @PSBoundParameters | should benullorempty
		}

		it 'should save the expected attribute' -TestCases $testCases.All {
			param($Identity,$Attribute)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'SaveAdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					(-not (Compare-Object $PSBoundParameters.Parameters.Attribute.Keys $Attribute.Keys)) -and
					(-not (Compare-Object $PSBoundParameters.Parameters.Attribute.Values $Attribute.Values))
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'should save on the expected identity' -TestCases $testCases.All {
			param($Identity,$Attribute)

			& $commandName @PSBoundParameters
		
			$assMParams = @{
				CommandName = 'SaveAdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Parameters.AdsPath -eq 'adspathhere'
				}
			}
			Assert-MockCalled @assMParams
		}
	
	}

	describe 'SyncCompanyUser' {
	
		$commandName = 'SyncCompanyUser'
		$command = Get-Command -Name $commandName

		$script:AdUserUpn = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
		$script:AdUserUpn | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'samaccountnameval'
		$script:AdUserUpn | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value 'empidhere' -PassThru

		$script:csvUser = [pscustomobject]@{
			AD_LOGON = 'foo'
			PERSON_NUM = 123
			OtherAtrrib = 'x'
		}
	
		#region Mocks
			mock 'SetAdUser'
		#endregion
	
		$testCases = @(
			@{
				Label = 'SamAccountName Identifier, 1 Attributes hashtable'
				Parameters = @{
					AdUser = $script:AdUserUpn
					CsvUser = $script:csvUser
					Attributes = @{ 
						ADAttributeName = 'EmployeeId'
						ADAttributeValue = $null
						CSVAttributeName = 'username'
						CSVAttributeValue = 'newattribvalue1'
					}
					Identifier = 'samAccountName'
					Confirm = $false
				}
				Expect = @(
					@{
						Type = 'Function parameters'
						Name = 'SetAdUser'
						Parameters = @(
							@{
								Identity = @{ samAccountName = 'samaccountnameval' }
								Attribute = @{ EmployeeId = 'newattribvalue1' }
							}
						)
					}
				)
			}
			@{
				Label = 'EmployeeId Identifier, 2 Attributes hashtable'
				Parameters = @{
					AdUser = $script:AdUserUpn
					CsvUser = $script:csvUser
					Attributes = @(
						@{ 
							ADAttributeName = 'EmployeeId'
							ADAttributeValue = $null
							CSVAttributeName = 'username'
							CSVAttributeValue = 'newattribvalue1'
						},
						@{ 
							ADAttributeName = 'attribneedchanged'
							ADAttributeValue = 'thisneedschanged'
							CSVAttributeName = 'username'
							CSVAttributeValue = 'newattribvalue2'
						}
					)
					Identifier = 'employeeId'
					Confirm = $false
				}
				Expect = @(
					@{
						Type = 'Function parameters'
						Name = 'SetAdUser'
						Parameters = @(
							@{
								Identity = @{ employeeId = 'empidhere' }
								Attribute = @{ EmployeeId = 'newattribvalue1' }
							}
							@{
								Identity = @{ employeeId = 'empidhere' }
								Attribute = @{ attribneedchanged = 'newattribvalue2' }
							}
						)
					}
				)
			}
		)
	
		foreach ($testCase in $testCases) {
	
			context $testcase.Label {
	
				$expect = $testcase.Expect
				$funcParams = $testCase.Parameters
	
				$result = & $commandName @funcParams
	
				it 'should return nothing' {
					$result | should benullorempty
				}
	
				it 'should change only those attributes in the Attributes parameter' {

					$expectedParams = $expect.where({ $_.Name -eq 'SetAdUser'})

					$assMParams = @{
						CommandName = 'SetAdUser'
						Times = @($funcParams.Attributes).Count
						Exactly = $true
						ParameterFilter = {
							foreach ($paramHt in $expectedParams.Parameters) { 
								$PSBoundParameters.Attribute.Keys -in $paramHt.Attribute.Keys -and
								$PSBoundParameters.Attribute.Values -in $paramHt.Attribute.Values
							}
						}
					}
					Assert-MockCalled @assMParams
				}

				it 'should change attributes on the expected user account' {

					$expectedParams = $expect.where({ $_.Name -eq 'SetAdUser'})

					$assMParams = @{
						CommandName = 'SetAdUser'
						Times = @($funcParams.Attributes).Count
						Exactly = $true
						ParameterFilter = {
							foreach ($i in $expectedParams.Parameters) {
								$PSBoundParameters.Idenity.Keys -in $i.Idenity.Keys -and
								$PSBoundParameters.Identity.Values -in $i.Identity.Values
							}
						}
					}
					Assert-MockCalled @assMParams
				}

				context 'when a non-terminating error occurs in the function' {

					mock 'Write-Verbose' {
						Write-Error -Message 'error!'
					}

					it 'should throw an exception' {
					
						$params = @{} + $funcParams
						{ & $commandName @params } | should throw 'error!'
					}
				}
			}
		}
	}
		
	describe 'WriteLog' {
	
		$commandName = 'WriteLog'
		

		mock 'Get-Date' {
			'time'
		}

		mock 'Export-Csv'
	
		$parameterSets = @(
			@{
				FilePath = 'C:\log.csv'
				CSVIdentifierValue = 'username'
				CSVIdentifierField = 'employeeid'
				Attributes = @{ 
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = $null
					CSVAttributeName = 'PERSON_NUM'
					CSVAttributeValue = 123
				}
				TestName = 'Standard'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'should export a CSV to the expected path: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $PSBoundParameters.Path -eq $FilePath }
			}
			Assert-MockCalled @assMParams
		}

		it 'should appends to the CSV: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $Append }
			}
			Assert-MockCalled @assMParams
		}

		it 'should export as CSV with the expected values: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$InputObject.Time -eq 'time' -and
					$InputObject.CSVIdentifierValue -eq $CSVIdentifierValue -and
					$InputObject.CSVIdentifierField -eq $CSVIdentifierField -and
					$InputObject.ADAttributeName -eq 'EmployeeId' -and
					$InputObject.ADAttributeValue -eq $null -and
					$InputObject.CSVAttributeName -eq 'PERSON_NUM' -and
					$InputObject.CSVAttributeValue -eq 123
				}
			}
			Assert-MockCalled @assMParams
		}
	}

	describe 'Invoke-AdSync' {
	
		$commandName = 'Invoke-AdSync'
	
		#region Mocks
			$script:testAdUser = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
				$amParams = @{
					MemberType = 'NoteProperty'
					Force = $true
				}
				$props = @{
					'Name' = 'nameval'
					'Enabled' = $true
					'SamAccountName' = 'samval'
					'GivenName' = 'givennameval'
					'Surname' = 'surnameval'
					'DisplayName' = 'displaynameval'
					'OtherProperty' = 'otherval'
					'EmployeeId' = 1
					'Title' = 'titleval'
				}
				$props.GetEnumerator() | ForEach-Object {
					$script:testAdUser | Add-Member @amParams -Name $_.Key -Value $_.Value
				}
				$script:testAdUser

			mock 'WriteLog'
			
			mock 'Test-Path' {
				$true
			}

			mock 'SyncCompanyUser'

			mock 'Write-Warning'

			mock 'TestCsvHeaderExists' {
				$true
			}

			mock 'Get-CompanyAdUser' {
				$script:allAdsiUsers
			}

			mock 'Get-CompanyCsvUser' {
				[pscustomobject]@{ 
					AD_LOGON = "nameval"
					PERSON_NUM = "1"
					SyncAttrib1 = 'sync1'
					SyncAttrib2 = 'sync2'
				}
			}

			mock 'FindUserMatch'

			mock 'GetCsvIdField' {
				[pscustomobject]@{
					Field = 'x'
					Value = 'y'
				}
			}

			mock 'Write-Host'
		#endregion

		$parameterSets = @(
			@{
				Label = 'ReportOnly'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 'csvfield1' = 'adfield1' }
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
					ReportOnly = $true
				}
			}
			@{
				Label = 'Single sync /single match field'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 'csvfield1' = 'adfield1' }
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
				}
			}
			@{
				Label = 'Multi sync/Multi match field'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 
						'csvfield1' = 'adfield1'
						'csvfield2' = 'adfield2'
					}
					FieldMatchMap = @{ 
						PERSON_NUM = 'EmployeeId'
						AD_LOGON = 'samAcountName'
					}
				}
			}
			@{
				Label = 'Exclude'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldMatchMap = @{ 'csvmatchfield1' = 'admatchfield1' }
					FieldSyncMap = @{ 'csvfield1' = 'adfield1' }
					Exclude = @{ ExcludeCol = 'excludeme' }
				}
			}
		)

		$testCases = $parameterSets

		foreach ($testCase in $testCases) {

			$parameters = $testCase.Parameters

			context $testCase.Label {

				$result = & $commandName @parameters

				if ($parameters.ContainsKey('Exclude')) {

					context 'when excluding a CSV column' {

						$result = & $commandName @parameters

						context 'when a header does not exist' {
						
							mock 'TestCsvHeaderExists' {
								$false
							}

							it 'should throw an exception' {
								$params = @{} + $parameters
								{ & $commandName @params } | should throw 'One or more CSV headers excluded with -Exclude do not exist in the CSV file'
							}
						
						}

						context 'when all headers exist' {
						
							mock 'TestCsvHeaderExists' {
								$true
							}

							$result = & $commandName @parameters

							it 'should pass Exclude to Get-CompanyCsvUser' {

								$assMParams = @{
									CommandName = 'Get-CompanyCsvUser'
									Times = 1
									Exactly = $true
									ParameterFilter = { 
										$PSBoundParameters.Exclude.Keys -eq 'ExcludeCol' -and
										$PSBoundParameters.Exclude.Values -eq 'excludeme'
									}
								}
								Assert-MockCalled @assMParams
								
							}
						}
					}
				}

				context 'when no AD users are found' {
					
					mock 'Get-CompanyAdUser'

					it 'should throw an exception' {
					
						$params = @{} + $parameters
						{ & $commandName @params } | should throw 'No AD users found'
					}
				}

				context 'when no CSV users are found' {
					
					mock 'Get-CompanyCsvUser'

					it 'should throw an exception' {
					
						$params = @{} + $parameters
						{ & $commandName @params } | should throw 'No CSV users found'
					}
					
				}

				context 'when at least one AD user and one CSV user is found' {

					$result = & $commandName @parameters
					
					it 'should return nothing' {
						$result | should benullorempty
					}
					
					context 'when a user match cannot be found' {

						mock 'FindUserMatch'
					
						context 'when no CSV ID fields can be found' {

							mock 'GetCsvIdField'

							it 'should throw an exception' {
							
								$params = @{} + $parameters
								{ & $commandName @params } | should throw 'No CSV ID fields were found'
							}			
						}

						context 'when at least one CSV ID field can be found' {

							context 'when a populated CSV ID field exists' {
								
								mock 'GetCsvIdField' {
									[pscustomobject]@{
										Field = $null
										Value = 'val1'
									}
									[pscustomobject]@{
										Field = $null
										Value = 'val2'
									}
									[pscustomobject]@{
										Field = 'populatedfield1'
										Value = 'val1'
									}
								}

								$result = & $commandName @parameters
								
								it 'should pass the ID as the CSV id field for WriteLog' {

									$assMParams = @{
										CommandName = 'WriteLog'
										Times = 1
										Exactly = $true
										ParameterFilter = { 
											$PSBoundParameters.CSVIdentifierField -eq 'populatedfield1' 
										}
									}
									Assert-MockCalled @assMParams
								}
							
							}

							context 'when no CSV ID fields are populated' {
							
								mock 'GetCsvIdField' {
									[pscustomobject]@{
										Field = 'field1'
										Value = $null
									}
									[pscustomobject]@{
										Field = 'field2'
										Value = $null
									}
								}

								$result = & $commandName @parameters

								it 'should pass N/A as the CSV id field for WriteLog' {

									$assMParams = @{
										CommandName = 'WriteLog'
										Times = 1
										Exactly = $true
										ParameterFilter = { 
											$PSBoundParameters.CsvIdentifierValue -eq 'N/A' -and
											$PSBoundParameters.CSVIdentifierField -eq 'field1,field2'
										}
									}
									Assert-MockCalled @assMParams
								}
							}
						}
					}

					context 'when a user match can be found' {

						mock 'FindUserMatch' {
							[pscustomobject]@{
								MatchedAdUser = $script:testAdUser
								CsvIdMatchedOn = 'PERSON_NUM'
								AdIdMatchedOn = 'EmployeeId'
							}
						}
					
						context 'when an attribute mismatch is found' {

							mock 'FindAttributeMismatch' {
								@{
									CSVAttributeName = 'x'
									CSVAttributeValue = 'y'
									ADAttributeName = 'z'
									ADAttributeValue = 'i'
								}
							}

							if ($parameters.ContainsKey('ReportOnly')) {
								context 'when only reporting' {

									$result = & $commandName @parameters

									it 'should not attempt to sync the user' {
									
										$assMParams = @{
											CommandName = 'SyncCompanyUser'
											Times = 0
											Exactly = $true
										}
										Assert-MockCalled @assMParams
									}
								}
							} else {
								context 'when syncing' {

									$result = & $commandName @parameters

									it 'should sync the expected user' {

										$assMParams = @{
											CommandName = 'SyncCompanyUser'
											Times = 1
											Exactly = $true
											ParameterFilter = { 
												$PSBoundParameters.AdUser.Name -eq 'nameval' -and
												$PSBoundParameters.AdUser.Enabled -eq $true -and
												$PSBoundParameters.AdUser.SamAccountName -eq 'samval' -and
												$PSBoundParameters.AdUser.GivenName -eq 'givennameval' -and
												$PSBoundParameters.AdUser.Surname -eq 'surnameval' -and
												$PSBoundParameters.AdUser.DisplayName -eq 'displaynameval' -and
												$PSBoundParameters.AdUser.OtherProperty -eq 'otherval' -and
												$PSBoundParameters.AdUser.EmployeeId -eq 1 -and
												$PSBoundParameters.AdUser.Title -eq 'titleval' #-and
												$PSBoundParameters.CsvUser.AD_LOGON -eq 'nameval' -and
												$PSBoundParameters.CsvUser.PERSON_NUM -eq "1" -and
												$PSBoundParameters.CsvUser.SyncAttrib1 -eq 'sync1' -and
												$PSBoundParameters.CsvUser.SyncAttrib2 -eq 'sync2' -and
												$PSBoundParameters.Attributes.CSVAttributeName -eq 'x' -and
												$PSBoundParameters.Attributes.CSVAttributeValue -eq 'y' -and
												$PSBoundParameters.Attributes.ADAttributeName -eq 'z' -and
												$PSBoundParameters.Attributes.ADAttributeValue -eq 'i'
											}
										}
										Assert-MockCalled @assMParams
									}
								}
							}
						}

						context 'when all attributes are in sync' {

							mock 'FindAttributeMismatch'

							$result = & $commandName @parameters
						
							it 'should pass the expected attributes to WriteLog' {

									$assMParams = @{
										CommandName = 'WriteLog'
										Times = 1
										Exactly = $true
										ParameterFilter = { 
											$PSBoundParameters.Attributes.CSVAttributeName -eq 'AlreadyInSync' -and
											$PSBoundParameters.Attributes.CSVAttributeValue -eq 'AlreadyInSync' -and
											$PSBoundParameters.Attributes.ADAttributeName -eq 'AlreadyInSync' -and
											$PSBoundParameters.Attributes.ADAttributeValue -eq 'AlreadyInSync'
										}
									}
									Assert-MockCalled @assMParams
								}
						}
					}
				}
			}
		}
	}

	Remove-Variable -Name allAdsiUsers -Scope Script
	Remove-Variable -Name allCsvUsers -Scope Script
}
