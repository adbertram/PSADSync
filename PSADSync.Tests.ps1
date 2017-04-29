$ThisModule = "$($MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$', '').psm1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psm1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force

Import-Module -Name $ThisModule,'ActiveDirectory' -Force -ErrorAction Stop

InModuleScope $ThisModuleName {

	describe 'GetCompanyAdUser' {
	
		$commandName = 'GetCompanyAdUser'
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
					PERSON_NUM = 'foo'
				}
				[pscustomobject]@{
					PERSON_NUM = 'foo2'
				}
				[pscustomobject]@{
					PERSON_NUM = 'foo3'
				}
				[pscustomobject]@{
					PERSON_NUM = 'notinAD'
				}
			)

			$script:empIdAdUsers = @(
				[pscustomobject]@{
					EmployeeId = 'foo'
				}
				[pscustomobject]@{
					EmployeeId = 'foo2'
				}
				[pscustomobject]@{
					EmployeeId = 'foo3'
				}
				[pscustomobject]@{
					EmployeeId = 'NotinCSV'
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

			mock 'GetCompanyAdUser' {
				$script:allAdUsers
			} -ParameterFilter { (diff $Properties @('EmployeeId')) -ne $null }

			mock 'GetCompanyAdUser' {
				$script:empIdAdUsers
			} -ParameterFilter { -not (diff $Properties @('EmployeeId')) }

			mock 'GetCompanyCsvUser' {
				$script:csvUsers
			}

			mock 'FindUserMatch' {
				@(
					[pscustomobject]@{
						EmployeeId = 'foo'
					}
				)
			} -ParameterFilter { $CsvUser.PERSON_NUM -eq 'foo' }

			mock 'FindUserMatch' {
				@(
					[pscustomobject]@{
						EmployeeId = 'foo2'
					}
				)
			} -ParameterFilter { $CsvUser.PERSON_NUM -eq 'foo2' }

			mock 'FindUserMatch' {
				@(
					[pscustomobject]@{
						EmployeeId = 'foo3'
					}
				)
			} -ParameterFilter { $CsvUser.PERSON_NUM -eq 'foo3' }
		#endregion
		
		$parameterSets = @(
			@{
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
	
		Context 'When a match is found' {

			it 'should return the expected property values: <TestName>' -TestCases $testCases.All {
				param($AdUsers,$CsvUsers)
			
				$result = & $commandName @PSBoundParameterse

				(diff $result.CsvUser.PERSON_NUM @('foo','foo2','foo3','notinAD')).InputObject | should benullorempty
				(diff $result.AdUser.EmployeeId @('foo','foo2','foo3','notinCSV')).InputObject | should benullorempty
				(diff $result.Match @($true,$true,$true,$false)).InputObject | should benullorempty
			}

			
		}

		# context 'When a match is not found' {

		# 	mock 'FindUserMatch'

		# 	it 'should return the expected property values: <TestName>' -TestCases $testCases.All {
		# 		param($AdUsers,$CsvUsers)
			
		# 		$result = & $commandName @PSBoundParameters
		# 	}

		# }
	}

	describe 'CompareCompanyUser' {
	
		$commandName = 'CompareCompanyUser'
		$command = Get-Command -Name $commandName
	
		#region Mocks
			
		#endregion
		
		$parameterSets = @(
			@{
				TestName = ''
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		
	}
}