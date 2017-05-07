$ThisModule = "$($MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$', '').psm1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psm1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force

Import-Module -Name $ThisModule,'ActiveDirectory' -Force -ErrorAction Stop

InModuleScope $ThisModuleName {

	describe 'Get-CompanyAdUser' {
	
		$commandName = 'Get-CompanyAdUser'
		$command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'Get-AdUser' {
				@(
					[pscustomobject]@{
						Name = 'foo'
						SamAccountName = 'samname'
						GivenName = 'givenamehere'
						Surname = 'surnamehere'
						DisplayName = 'displaynamehere'
						Title = 'titlehere'
						OtherProperty = 'other'
					}
					[pscustomobject]@{
						Name = 'foo2'
						SamAccountName = 'samname2'
						GivenName = 'givenamehere2'
						Surname = 'surnamehere2'
						DisplayName = 'displaynamehere2'
						Title = 'titlehere2'
						OtherProperty = 'other2'
					}
					[pscustomobject]@{
						Name = 'foo3'
						SamAccountName = 'samname2'
						GivenName = 'givenamehere3'
						Surname = 'surnamehere3'
						DisplayName = 'displaynamehere3'
						Title = 'titlehere3'
						OtherProperty = 'other3'
					}
				)
			} -ParameterFilter { (diff $Properties @('GivenName','SurName','DisplayName','Title')) -ne $null }

			mock 'Get-AdUser' {
				@(
					[pscustomobject]@{
						GivenName = 'givenamehere'
						Surname = 'surnamehere'
					}
					[pscustomobject]@{
						GivenName = 'givenamehere2'
						Surname = 'surnamehere2'
					}
					[pscustomobject]@{
						GivenName = 'givenamehere3'
						Surname = 'surnamehere3'
					}
				)
			} -ParameterFilter { -not (diff $Properties @('GivenName','SurName')) }
		#endregion
		
		$parameterSets = @(
			@{
				TestName = 'Only enabled users'
			}
			@{
				All = $true
				TestName = 'All users'
			}
			@{
				Properties = 'GivenName','SurName'
				TestName = 'All users'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			AllUsers = $parameterSets.where({$_.ContainsKey('All')})
			EnabledUsers = $parameterSets.where({-not $_.ContainsKey('All')})
			SpecificProperties = $parameterSets.where({$_.ContainsKey('Properties')})
			AllProperties = $parameterSets.where({-not $_.ContainsKey('Properties')})
		}

		it 'when All is used, it returns all users: <TestName>' -TestCases $testCases.AllUsers {
			param($All,$Properties)
		
			$result = & $commandName @PSBoundParameters
			@($result).Count | should be 3

			$assMParams = @{
				CommandName = 'Get-AdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$Filter -eq 'objectClass -like "*"' 
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'when All is not used, it only returns enabled users: <TestName>' -TestCases $testCases.EnabledUsers {
			param($All,$Properties)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Get-AdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = {
					$LDAPFilter -eq "(&(samAccountName=*)(!userAccountControl:1.2.840.113556.1.4.803:=2))" 
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'when Properties is passed, it returns expected properties: <TestName>' -TestCases $testCases.SpecificProperties {
			param($All,$Properties)
		
			$result = & $commandName @PSBoundParameters
			@($result).foreach({
				(diff $_.PSObject.Properties.Name @('GivenName','SurName')).InputObject | should benullorempty
			})
		}

		it 'when Properties is not passed, it returns expected properties: <TestName>' -TestCases $testCases.AllProperties {
			param($All,$Properties)
		
			$result = & $commandName @PSBoundParameters
			@($result).foreach({
				(diff $_.PSObject.Properties.Name @('GivenName','SurName','SamAccountName','Title','OtherProperty','DisplayName','Name')).InputObject | should benullorempty
			})
		}
	}

	describe 'CompareCompanyUser' {
	
		$commandName = 'CompareCompanyUser'
		$command = Get-Command -Name $commandName
	
		#region Mocks
			$script:csvUsers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
				}
				[pscustomobject]@{
					AD_LOGON = 'foo2'
				}
				[pscustomobject]@{
					AD_LOGON = 'foo3'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
				}
			)

			$script:empIdAdUsers = @(
				[pscustomobject]@{
					Name = 'foo'
					SamAccountName = 'samname'
					GivenName = 'givenamehere'
					Surname = 'surnamehere'
					DisplayName = 'displaynamehere'
					Title = 'titlehere'
					OtherProperty = 'other'
					EmployeeId = 123
				}
				[pscustomobject]@{
					Name = 'foo2'
					SamAccountName = 'samname2'
					GivenName = 'givenamehere2'
					Surname = 'surnamehere2'
					DisplayName = 'displaynamehere2'
					Title = 'titlehere2'
					OtherProperty = 'other2'
					EmployeeId = 1234
				}
				[pscustomobject]@{
					Name = 'foo3'
					SamAccountName = 'samname3'
					GivenName = 'givenamehere3'
					Surname = 'surnamehere3'
					DisplayName = 'displaynamehere3'
					Title = 'titlehere3'
					OtherProperty = 'other3'
					EmployeeId = 12345
				}
			)

			$script:allAdUsers = @(
				[pscustomobject]@{
					Name = 'foo'
					SamAccountName = 'samname'
					GivenName = 'givenamehere'
					Surname = 'surnamehere'
					DisplayName = 'displaynamehere'
					Title = 'titlehere'
					OtherProperty = 'other'
				}
				[pscustomobject]@{
					Name = 'foo2'
					SamAccountName = 'samname2'
					GivenName = 'givenamehere2'
					Surname = 'surnamehere2'
					DisplayName = 'displaynamehere2'
					Title = 'titlehere2'
					OtherProperty = 'other2'
				}
				[pscustomobject]@{
					Name = 'foo3'
					SamAccountName = 'samname2'
					GivenName = 'givenamehere3'
					Surname = 'surnamehere3'
					DisplayName = 'displaynamehere3'
					Title = 'titlehere3'
					OtherProperty = 'other3'
				}
			)

			mock 'FindUserMatch' {
				@(
					[pscustomobject]@{
						EmployeeId = 'foo'
					}
				)
			} -ParameterFilter { $CsvUser.AD_LOGON -eq 'foo' }

			mock 'FindUserMatch' {
				@(
					[pscustomobject]@{
						EmployeeId = 'foo2'
					}
				)
			} -ParameterFilter { $CsvUser.AD_LOGON -eq 'foo2' }

			mock 'FindUserMatch' {
				@(
					[pscustomobject]@{
						EmployeeId = 'foo3'
					}
				)
			} -ParameterFilter { $CsvUser.AD_LOGON -eq 'foo3' }

			mock 'FindUserMatch' {

			} -ParameterFilter { $CsvUser.AD_LOGON -eq 'NotInAD' }
		#endregion
		
		$parameterSets = @(
			@{
				AdUsers = $script:allAdUsers
				CsvUsers = $script:csvUsers
				TestName = 'Default'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}

		it 'should return the expected number of objects: <TestName>' -TestCases $testCases.All {
			param($AdUsers,$CsvUsers)
		
			$result = & $commandName @PSBoundParameters
			@($result).Count | should be 4
		}

		it 'should return the expected object properties: <TestName>' -TestCases $testCases.All {
			param($AdUsers,$CsvUsers)
		
			$result = & $commandName @PSBoundParameters
			@($result).foreach({
				$_.PSObject.Properties.Name -contains 'CsvUser' | should be $true
				$_.PSObject.Properties.Name -contains 'AdUser' | should be $true
				$_.PSObject.Properties.Name -contains 'Match' | should be $true
			})
		}

		it 'should return the expected object type: <TestName>' -TestCases $testCases.All {
			param($AdUsers,$CsvUsers)
		
			$result = & $commandName @PSBoundParameters
			$result | should beoftype 'pscustomobject'
		}

		it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.All {
			param($AdUsers,$CsvUsers)
		
			$result = & $commandName @PSBoundParameters

			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'foo'})).AdUser.EmployeeId | should be 'foo'
			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'foo'})).Match | should be $true
			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'foo2'})).AdUser.EmployeeId | should be 'foo2'
			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'foo2'})).Match | should be $true
			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'foo3'})).AdUser.EmployeeId | should be 'foo3'
			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'foo3'})).Match | should be $true
			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'NotInAD'})).AdUser | should benullorempty
			(@($result).where({ $_.CsvUser.AD_LOGON -eq 'NotInAD'})).Match | should be $false

		}

		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Verbose' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.All {
				param($AdUsers,$CsvUsers)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 'error!'
			}
		}
	}

	describe 'FindUserMatch' {
	
		$commandName = 'FindUserMatch'
		$command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'Write-Warning'

			$script:csvUserMatch = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
				}
			)

			$script:blankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = $null
				}
			)

			$script:csvUserNoMatch = @(
				[pscustomobject]@{
					AD_LOGON = 'NotInAd'
				}
			)

			$script:AdUsers = @(
				[pscustomobject]@{
					samAccountName = 'foo'
					EmployeeId = 123
				}
				[pscustomobject]@{
					samAccountName = 'foo2'
					EmployeeId = 1234
				}
				[pscustomobject]@{
					samAccountName = 'NotinCSV'
					EmployeeId = 12345
				}
			)

			mock 'Write-Debug'
		#endregion
		
		$parameterSets = @(
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatch
				TestName = 'Match'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserNoMatch
				TestName = 'No Match'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:blankCsvUserIdentifier
				TestName = 'Blank ID'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			Match = $parameterSets.where({$_.TestName -eq 'Match'})
			NoMatch = $parameterSets.where({$_.TestName -eq 'No Match'})
			BlankId = $parameterSets.where({ -not $_.CsvUser.AD_LOGON })
			ValidId = $parameterSets.where({ $_.CsvUser.AD_LOGON })
		}

		context 'When no matches could be found' {
			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.NoMatch {
				param($AdUsers,$CsvUser)
			
				& $commandName @PSBoundParameters | should benullorempty
			}
		}

		context 'When matches can be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.Match {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}
		}

		it 'should return the expected object properties: <TestName>' -TestCases $testCases.All {
			param($AdUsers,$CsvUser)
		
			$result = & $commandName @PSBoundParameters
			@($result).foreach({
				$_.PSObject.Properties.Name -contains 'EmployeeId' | should be $true
			})
		}

		it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.Match {
			param($AdUsers,$CsvUser)
		
			$result = & $commandName @PSBoundParameters

			@($result).where({ $_.EmployeeId -eq 123}) | should not benullorempty

		}

		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Debug' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.ValidId {
				param($AdUsers,$CsvUser)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 'error!'
			}
		}

		context 'when the identifer is blank' {

			it 'should do nothing: <TestName>' -TestCases $testCases.BlankId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Write-Debug'
					Times = 0
					Exactly = $true
					Scope = 'It'
				}
				Assert-MockCalled @assMParams
			}

		}
	}

	describe 'FindAttributeMismatch' {
	
		$commandName = 'FindAttributeMismatch'
		$command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'Write-Debug'

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

			$script:AdUserMisMatch = New-MockObject -Type 'Microsoft.ActiveDirectory.Management.ADUser'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value $null -PassThru

			$script:AdUserNoMisMatch = New-MockObject -Type 'Microsoft.ActiveDirectory.Management.ADUser'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value 1111 -PassThru
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

			mock 'Write-Debug' {
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

		mock 'Set-AdUser'

		$script:AdUser = New-MockObject -Type 'Microsoft.ActiveDirectory.Management.ADUser'
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
				TestName = 'Standard'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'should change only those attributes in the Attributes parameter: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser,$Attributes,$Credential,$DomainController)
		
			$result = & $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'Set-AdUser'
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

		it 'should change attributes on the expected user account: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser,$Attributes,$Credential,$DomainController)
		
			$result = & $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'Set-AdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { [string]$Identity -eq 'foo' }
			}
			Assert-MockCalled @assMParams
		}

		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Debug' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.All {
				param($AdUser,$CsvUser,$Attributes,$Credential,$DomainController)
			
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
				Identifier = 'username'
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
			param($FilePath,$Identifier,$Attributes)
		
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
			param($FilePath,$Identifier,$Attributes)
		
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
			param($FilePath,$Identifier,$Attributes)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$InputObject.Time -eq 'time' -and
					$InputObject.Identifier -eq $Identifier -and
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
			$script:csvUsers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 123
					OtherAtrrib = 'x'
				}
				[pscustomobject]@{
					AD_LOGON = 'foo2'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
				}
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = 12345
					OtherAtrrib = 'x'
				}
			)

			$script:AdUsers = @(
				[pscustomobject]@{
					Name = 'foo'
					SamAccountName = 'samname'
					GivenName = 'givenamehere'
					Surname = 'surnamehere'
					DisplayName = 'displaynamehere'
					Title = 'titlehere'
					OtherProperty = 'other'
					EmployeeId = 'x'
				}
				[pscustomobject]@{
					Name = 'foo2'
					SamAccountName = 'samname2'
					GivenName = 'givenamehere2'
					Surname = 'surnamehere2'
					DisplayName = 'displaynamehere2'
					Title = 'titlehere2'
					OtherProperty = 'other2'
					EmployeeId = 'y'
				}
				[pscustomobject]@{
					Name = 'foo3'
					SamAccountName = 'samname2'
					GivenName = 'givenamehere3'
					Surname = 'surnamehere3'
					DisplayName = 'displaynamehere3'
					Title = 'titlehere3'
					OtherProperty = 'other3'
					EmployeeId = 'z'
				}
			)

			mock 'Get-CompanyAdUser' {
				$script:AdUsers
			}

			mock 'Get-CompanyCsvUser' {
				$script:csvUsers
			}

			mock 'CompareCompanyUser' {
				[pscustomobject]@{
					CSVUser = [pscustomobject]@{
						AD_LOGON = 'foo'
						PERSON_NUM = 'x'
					}
					ADUser = [pscustomobject]@{
						samAccountName = 'foo'
						EmployeeId = 'x'
					}
					Match = $true
				}
				[pscustomobject]@{
					CSVUser = [pscustomobject]@{
						AD_LOGON = 'foo'
						PERSON_NUM = 'x'
					}
					ADUser = [pscustomobject]@{
						samAccountName = 'nomatch'
						EmployeeId = 'x'
					}
					Match = $false
				}
			}

			mock 'FindAttributeMismatch' {
				[pscustomobject]@{
					CSVAttributeName = 'PERSON_NUM'
					CSVAttributeValue = 123
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = ''
				}
			}

			mock 'WriteLog'
			
			mock 'Test-Path' {
				$true
			}

			mock 'SyncCompanyUser'

			mock 'Write-Warning'
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
		)
	
		$testCases = @{
			All = $parameterSets
			ReportOnly = $parameterSets.where({$_.ContainsKey('ReportOnly')})
			Sync = $parameterSets.where({-not $_.ContainsKey('ReportOnly')})
		}
	
		it 'should compare the expected users: <TestName>' -TestCases $testCases.All {
			param($CsvFilePath,$ReportOnly)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Get-CompanyCsvUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = {
					$idFields = $CsvUsers.'AD_LOGON' | foreach { if (-not $_) { 'null' } else { $_ } }
					(-not (diff $idFields @('foo','foo2','NotInAD','null'))) -and
					(-not (diff $AdUsers.Name @('foo','foo2','foo3')))
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'should return nothing: <TestName>' -TestCases $testCases.All {
			param($CsvFilePath,$ReportOnly)
		
			& $commandName @PSBoundParameters | should benullorempty
		}

		it 'should attempt to sync the user: <TestName>' -TestCases $testCases.Sync {
			param($CsvFilePath,$ReportOnly)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'SyncCompanyUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$AdUser.samAccountName -eq 'foo' -and
					$CsvUser.'AD_LOGON' -eq 'foo' -and
					$Attributes.CSVAttributeName -eq 'PERSON_NUM' -and
					$Attributes.CSVAttributeValue -eq 123 -and
					$Attributes.ADAttributeName -eq 'EmployeeId' -and
					$Attributes.ADAttributeValue -eq ''
				}
			}
			Assert-MockCalled @assMParams
		}

		context 'when a null ID field is encountered in the CSV' {
		
			mock 'CompareCompanyUser' {
				[pscustomobject]@{
					CSVUser = [pscustomobject]@{
						AD_LOGON = 'foo'
						PERSON_NUM = 'x'
					}
					ADUser = [pscustomobject]@{
						samAccountName = 'foo'
						EmployeeId = 'x'
					}
					Match = $true
				}
				[pscustomobject]@{
					CSVUser = [pscustomobject]@{
						AD_LOGON = $null
						PERSON_NUM = 'x'
					}
					ADUser = [pscustomobject]@{
						samAccountName = 'nomatch'
						EmployeeId = 'x'
					}
					Match = $false
				}
			}

			it 'should write a warning: <TestName>' -TestCases $testCases.All {
				param($CsvFilePath,$ReportOnly)
			
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
			
			mock 'CompareCompanyUser' {
				[pscustomobject]@{
					CSVUser = [pscustomobject]@{
						AD_LOGON = 'foo'
						PERSON_NUM = 'x'
					}
					ADUser = [pscustomobject]@{
						samAccountName = 'foo'
						EmployeeId = 'x'
					}
					Match = $false
				}
			}

			it 'should write the expected contents to the log file: <TestName>' -TestCases $testCases.All {
			param($CsvFilePath,$ReportOnly)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'WriteLog'
					Times = 1
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { 
						$Identifier -eq 'foo' -and
						$Attributes.CSVAttributeName -eq 'NoMatch' -and
						$Attributes.CSVAttributeValue -eq 'NoMatch' -and
						$Attributes.ADAttributeName -eq 'NoMatch' -and
						$Attributes.ADAttributeValue -eq 'NoMatch'
					}
				}
				Assert-MockCalled @assMParams
			}

		}

		context 'when AD is already in sync' {

			mock 'FindAttributeMismatch'

			it 'should write the expected contents to the log file: <TestName>' -TestCases $testCases.All {
			param($CsvFilePath,$ReportOnly)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'WriteLog'
					Times = 1
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { 
						$Identifier -eq 'foo' -and
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
				param($CsvFilePath,$ReportOnly)
			
				$result = & $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'SyncCompanyUser'
					Times = 0
				}
				Assert-MockCalled @assMParams
			}

		}

		context 'when an exception is thrown' {

			mock 'Get-CompanyCsvUser' {
				throw 'error!'
			}

			it 'should return a non-terminating error: <TestName>' -TestCases $testCases.All {
				param($CsvFilePath,$ReportOnly)
			
				try { $result = & $commandName @PSBoundParameters -ErrorAction SilentlyContinue -ErrorVariable err } catch {}
				$err | should match 'error!'
			}
		}
	}
}