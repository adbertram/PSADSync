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
		Invoke-PSScriptAnalyzer -Path $PSScriptRoot -Severity Error
	}

}

InModuleScope $ThisModuleName {

	$script:AllAdsiUsers = 0..10 | foreach {
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
		$props.GetEnumerator() | foreach {
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

	$script:AllCsvUsers = 0..15 | foreach {
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
		$command = Get-Command -Name $commandName
	
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

			$script:csvUsersNullConvert = $script:csvUsers | foreach { if (-not $_.'AD_LOGON') { $_.'AD_LOGON' = 'null' } $_ }
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
			
				$result = & $commandName @PSBoundParameters

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

			(diff $script:csvUsersNullConvert.'AD_LOGON' $result.'AD_LOGON').InputObject | should benullorempty
		}

		it 'when excluding 1 col, should return all expected users: <TestName>' -TestCases $testCases.Exclude1Col {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(diff @('foo2','notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
		}
	
		it 'when excluding 2 cols, should return all expected users: <TestName>' -TestCases $testCases.Exclude2Cols {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(diff @('notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
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
			diff $result @('Header1','Header2','Header3') | should benullorempty
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
		$command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'GetAdUser' {
				$script:AllAdsiUsers | where { $_.Enabled }
			} -ParameterFilter { $LdapFilter }

			mock 'GetAdUser' {
				$script:AllAdsiUsers
			} -ParameterFilter { -not $LdapFilter }
		#endregion
		
		$parameterSets = @(
			@{
				TestName = 'All users'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}

		it 'should return all users: <TestName>' -TestCases $testCases.All {
			param($All,$Credential)
		
			$result = & $commandName @PSBoundParameters
			@($result).Count | should be @($script:AllAdsiUsers).Count
		}

	}

	describe 'FindUserMatch' {
	
		$commandName = 'FindUserMatch'
		$command = Get-Command -Name $commandName
	
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
					AD_LOGON = $null
					PERSON_NUM = 111
				}
			)

			$script:AllblankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = $null
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
				TestName = 'Match on 1 ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatchOnAllIdentifers
				TestName = 'Match on all IDs'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserNoMatch
				TestName = 'No Match'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:OneblankCsvUserIdentifier
				TestName = 'One Blank ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:AllblankCsvUserIdentifier
				TestName = 'All Blank IDs'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			MatchOnOneId = $parameterSets.where({$_.TestName -eq 'Match on 1 ID'})
			MatchOnAllIds = $parameterSets.where({$_.TestName -eq 'Match on all IDs'})
			NoMatch = $parameterSets.where({$_.TestName -eq 'No Match'})
			OneBlankId = $parameterSets.where({ -not $_.CsvUser.AD_LOGON -and ($_.CsvUser.PERSON_NUM) })
			AllBlankIds = $parameterSets.where({ -not $_.CsvUser.AD_LOGON -and (-not $_.CsvUser.PERSON_NUM) })
		}

		context 'When no matches could be found' {
			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.NoMatch {
				param($AdUsers,$CsvUser)
			
				& $commandName @PSBoundParameters | should benullorempty
			}
		}

		context 'When one match can be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.IdMatchedOn = 'AD_LOGON'

			}
		}

		context 'When multiple matches could be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.IdMatchedOn = 'AD_LOGON'

			}
		}

		context 'when one identifer is blank' {

			it 'should do nothing: <TestName>' -TestCases $testCases.OneBlankId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters

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
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				$result.MatchedAdUser.EmployeeId | should be 111
				$result.IdMatchedOn = 'PERSON_NUM'
			}

		}

		context 'when all identifers are blank' {

			it 'should do nothing: <TestName>' -TestCases $testCases.AllBlankIds {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters

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
		
			it 'should return the expected object properties: <TestName>' -TestCases $testCases.OneBlankId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result.MatchedAdUser).foreach({
					$_.PSObject.Properties.Name -contains 'EmployeeId' | should be $true
				})
				$result.IdMatchedOn = 'AD_LOGON'
			}
		
		}
	}

	describe 'FindAttributeMismatch' {
	
		$commandName = 'FindAttributeMismatch'
		$command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'Write-Verbose'

			$script:csvUserMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 123
				OtherAtrrib = 'x'
			}

			$script:csvUserNoMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 1111
				OtherAtrrib = 'y'
			}

			$script:AdUserMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value $null -PassThru

			$script:AdUserNoMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value 1111 -PassThru

			mock 'Get-Member' {
				[pscustomobject]@{
					Name = 'samAccountName'
				}
				[pscustomobject]@{
					Name = 'EmployeeId'
				}
			}
		#endregion
		
		$parameterSets = @(
			@{
				AdUser = $script:AdUserMisMatch
				CsvUser = $script:csvUserMisMatch
				TestName = 'Mismatch'
			}
			@{
				AdUser = $script:AdUserNoMisMatch
				CsvUser = $script:csvUserNoMisMatch
				TestName = 'No Mismatch'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			Mismatch = $parameterSets.where({$_.TestName -eq 'Mismatch'})
			NoMismatch = $parameterSets.where({$_.TestName -eq 'No Mismatch'})
		}

		it 'should find the correct AD property names: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Write-Verbose'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Message -eq "ADUser props: [samAccountName,EmployeeId]" }
			}
			Assert-MockCalled @assMParams
		}

		it 'should find the correct CSV property names: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Write-Verbose'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Message -eq 'CSV properties are: [AD_LOGON,PERSON_NUM,OtherAtrrib]' }
			}

			Assert-MockCalled @assMParams
		}

		context 'when a mismatch is found' {

			it 'should return the expected objects: <TestName>' -TestCases $testCases.Mismatch {
				param($AdUser,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
				$result | should beoftype 'pscustomobject'
				$result.CSVAttributeName | should be 'PERSON_NUM'
				$result.CSVAttributeValue | should be 123
				$result.ADAttributeName | should be 'EmployeeId'
				$result.ADAttributeValue | should be ''
			}
		}

		context 'when no mismatches are found' {

			it 'should return nothing: <TestName>' -TestCases $testCases.NoMismatch {
				param($AdUser,$CsvUser)
			
				& $commandName @PSBoundParameters | should benullorempty
			}

		}
		
		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Verbose' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.All {
				param($AdUser,$CsvUser)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 'error!'
			}
		}
	
	}

	describe 'SyncCompanyUser' {
	
		$commandName = 'SyncCompanyUser'
		$command = Get-Command -Name $commandName

		$script:AdUser = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
		$script:AdUser | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
		$script:AdUser | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value $null -PassThru

		$script:csvUser = [pscustomobject]@{
			AD_LOGON = 'foo'
			PERSON_NUM = 123
			OtherAtrrib = 'x'
		}
	
		$parameterSets = @(
			@{
				AdUser = $script:AdUser
				CsvUser = $script:csvUser
				Attributes = [pscustomobject]@{ 
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = $null
					CSVAttributeName = 'PERSON_NUM'
					CSVAttributeValue = 123
			 	}
				Identifier = 'samAccountName'
				TestName = 'Standard'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'should change only those attributes in the Attributes parameter: <TestName>' -Skip -TestCases $testCases.All {
			param($AdUser,$CsvUser,$Identifier,$Attributes,$Credential,$DomainController)
		
			$result = & $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'Set-AdsiUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = {
					($Replace.EmployeeId -eq 123) -and
					(-not ($Replace.GetEnumerator() | where { $_.Key -ne 'EmployeeId'}))
				 }
			}
			Assert-MockCalled @assMParams
		}

		it 'should change attributes on the expected user account: <TestName>' -Skip -TestCases $testCases.All {
			param($AdUser,$CsvUser,$Identifier,$Attributes,$Credential,$DomainController)
		
			$result = & $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'Set-AdsiUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { [string]$Identity -eq 'foo' }
			}
			Assert-MockCalled @assMParams
		}

		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Verbose' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -Skip -TestCases $testCases.All {
				param($AdUser,$CsvUser,$Identifier,$Attributes,$Credential,$DomainController)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params -Confirm:$false } | should throw 'error!'
			}
		}
	}
		
	describe 'WriteLog' {
	
		$commandName = 'WriteLog'
		$command = Get-Command -Name $commandName

		mock 'Get-Date' {
			'time'
		}

		mock 'Export-Csv'
	
		$parameterSets = @(
			@{
				FilePath = 'C:\log.csv'
				CSVIdentifierValue = 'username'
				CSVIdentifierField = 'employeeid'
				Attributes = [pscustomobject]@{ 
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
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $Path -eq 'C:\log.csv' }
			}
			Assert-MockCalled @assMParams
		}

		it 'should appends to the CSV: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			$result = & $commandName @PSBoundParameters

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
		
			$result = & $commandName @PSBoundParameters

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
		$command = Get-Command -Name $commandName

		#region Mocks

			mock 'Get-CompanyAdUser' {
				$script:AllAdsiUsers | where { $_.Enabled }
			}

			mock 'Get-CompanyCsvUser' {
				$script:AllCsvUsers
			} -ParameterFilter { -not $Exclude }

			mock 'Get-CompanyCsvUser' {
				$script:AllCsvUsers | where { $_.ExcludeCol -ne 'excludeme' }
			} -ParameterFilter { $Exclude }

			mock 'WriteLog'
			
			mock 'Test-Path' {
				$true
			}

			mock 'SyncCompanyUser'

			mock 'Write-Warning'

			mock 'TestCsvHeaderExists' {
				$true
			}
		#endregion
		
	
		$parameterSets = @(
			@{
				CsvFilePath = 'C:\log.csv'
				TestName = 'Sync'
			}
			@{
				CsvFilePath = 'C:\log.csv'
				ReportOnly = $true
				TestName = 'Report'
			}
			@{
				CsvFilePath = 'C:\log.csv'
				Exclude = @{ ExcludeCol = 'excludeme' }
				TestName = 'Excluded valid col'
			}
			@{
				CsvFilePath = 'C:\log.csv'
				Exclude = @{ ColNotHere = 'excludeme' }
				TestName = 'Exclude bogus col'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			ReportOnly = $parameterSets.where({$_.ContainsKey('ReportOnly')})
			Sync = $parameterSets.where({-not $_.ContainsKey('ReportOnly')})
			NoExclusions = $parameterSets.where({-not $_.ContainsKey('Exclude')})
			ExcludeCol = $parameterSets.where({$_.ContainsKey('Exclude') -and (-not $_.Exclude.Keys.Contains('ColNotHere'))})
			ExcludeBogusCol = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Contains('ColNotHere'))})
		}

		context 'when a column is attempted to be excluded does not exist' {

			mock 'TestCsvHeaderExists' {
				$false
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.ExcludeBogusCol {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 'One or more CSV headers excluded with -Exclude do not exist in the CSV file'
			}
		
		}

		it 'should return nothing: <TestName>' -TestCases $testCases.All {
			param($CsvFilePath,$ReportOnly,$Exclude)
		
			& $commandName @PSBoundParameters | should benullorempty
		}

		context 'when a null ID field is encountered in the CSV' {

			mock 'TestNullCsvIdField' {
				$false
			}
		
			it 'should write a warning: <TestName>' -Skip -TestCases $testCases.All {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Write-Warning'
					Times = 1
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { $Message -match 'The CSV user identifier field' }
				}
				Assert-MockCalled @assMParams
			}

		
		}

		context 'When no user can be matched' {

			it 'should write the expected contents to the log file: <TestName>' -Skip -TestCases $testCases.All {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'WriteLog'
					Times = 1
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { 
						$PSBoundParameters.CSVIdentifierField -eq 'AD_LOGON,PERSON_NUM' -and
						$PSBoundParameters.CSVIdentifierValue -eq 'foo,x' -and
						$PSBoundParameters.Attributes.CSVAttributeName -eq 'NoMatch' -and
						$PSBoundParameters.Attributes.CSVAttributeValue -eq 'NoMatch' -and
						$PSBoundParameters.Attributes.ADAttributeName -eq 'NoMatch' -and
						$PSBoundParameters.Attributes.ADAttributeValue -eq 'NoMatch'
					}
				}
				Assert-MockCalled @assMParams
			}

		}

		context 'when AD is already in sync' {

			mock 'FindAttributeMismatch'

			it 'should write the expected contents to the log file: <TestName>' -Skip -TestCases $testCases.All {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'WriteLog'
					Times = 1
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { 
						$IdentifierValu3 -eq 'foo' -and
						$CSVIdentifierField -eq 'EmployeeId'
						$Attributes.CSVAttributeName -eq 'AlreadyInSync' -and
						$Attributes.CSVAttributeValue -eq 'AlreadyInSync' -and
						$Attributes.ADAttributeName -eq 'AlreadyInSync' -and
						$Attributes.ADAttributeValue -eq 'AlreadyInSync'
					}
				}
				Assert-MockCalled @assMParams
			}

		}

		context 'when only reporting' {

			it 'should not attempt to sync the user: <TestName>' -TestCases $testCases.ReportOnly {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'SyncCompanyUser'
					Times = 0
				}
				Assert-MockCalled @assMParams
			}

		}

		context 'when an exception is thrown' {

			it 'should return a non-terminating error: <TestName>' -Skip -TestCases $testCases.All {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				try { $null = & $commandName @PSBoundParameters -ErrorAction SilentlyContinue -ErrorVariable err } catch {}
				$err | should not benullorempty
			}
		}
	}

	Remove-Variable -Name allAdsiUsers -Scope Script
	Remove-Variable -Name allCsvUsers -Scope Script
}
