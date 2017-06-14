,#region import modules
$ThisModule = "$($MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$', '').psd1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psd1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force

Import-Module -Name $ThisModule -Force -ErrorAction Stop
#endregion

describe 'Module-level tests' -Tag Unit {
	
	it 'should validate the module manifest' {
	
		{ Test-ModuleManifest -Path $ThisModule -ErrorAction Stop } | should not throw
	}

	it 'should pass all analyzer rules' {

		$excludedRules = @(
			'PSUseShouldProcessForStateChangingFunctions',
			'PSUseToExportFieldsInManifest',
			'PSAvoidInvokingEmptyMembers',
			'PSUsePSCredentialType',
			'PSAvoidUsingPlainTextForPassword'
			'PSAvoidUsingConvertToSecureStringWithPlainText'
		)

		Invoke-ScriptAnalyzer -Path $PSScriptRoot -ExcludeRule $excludedRules -Severity Error | Select-Object -ExpandProperty RuleName | should benullorempty
	}
}

InModuleScope $ThisModuleName {

	$script:AllAdUsers = 0..9 | ForEach-Object {
		$i = $_
		$adUser = @{}
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
					$adUser.($_.Key) = $false
				} else {
					$adUser.($_.Key) = $true
				}
			} else {
				$adUser.($_.Key) = "$($_.Value)$i"
			}
		}
		if ($i -eq 5) {
			$adUser.samAccountName = $null
		}
		if ($i -eq 6) { 
			$adUser.EmployeeId = $null
		}
		[pscustomobject]$adUser
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

	describe 'Get-CompanyCsvUser' -Tag Unit {
	
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

	describe 'GetCsvColumnHeaders' -Tag Unit {
		
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

	describe 'TestCsvHeaderExists' -Tag Unit {
		
		$commandName = 'TestCsvHeaderExists'
		$script:command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'GetCsvColumnHeaders' {
				'nothinghere','nope'
			} -ParameterFilter { $CsvFilePath -eq 'C:\foofail.csv' }

			mock 'GetCsvColumnHeaders' {
				'Header','a','b','c','d','e'
			} -ParameterFilter { $CsvFilePath -eq 'C:\foopass.csv' }

			mock 'ParseScriptBlockHeaders' {
				'Header','a','b','c','d','e'
			}

		$testCases = @(
			@{
				Label = 'Single header / no scriptblocks'
				Parameters = @{
					CsvFilePath = 'C:\foofail.csv'
					Header = 'fail'
				}
				Expected = @{
					Execution = @{
						ParseScriptBlockHeaders = @{
							RunTimes = 0
						}
					}
					Output = @{
						ReturnValue = $false
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Single header / 1 scriptblock'
				Parameters = @{
					CsvFilePath = 'C:\foofail.csv'
					Header = { if (-not $_.Header) { '2' } else { '3' } }
				}
				Expected = @{
					Execution = @{
						ParseScriptBlockHeaders = @{
							RunTimes = 1
						}
					}
					Output = @{
						ReturnValue = $false
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Multiple headers / string/scriptblock'
				Parameters = @{
					CsvFilePath = 'C:\foopass.csv'
					Header = 
						'a',
						{ if (-not $_.Header) { 'b' } else { 'c' } },
						{ if (-not $_.Header) { 'd' } else { 'e' } }
				}
				Expected = @{
					Execution = @{
						ParseScriptBlockHeaders = @{
							RunTimes = 2
						}
					}
					Output = @{
						ReturnValue = $true
						ObjectCount = 1
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {
	
				$result = & $commandName @parameters

				it "should call ParseScriptBlockHeaders [$($expected.Execution.ParseScriptBlockHeaders.RunTimes)] times" {
					
					$assMParams = @{
						CommandName = 'ParseScriptBlockHeaders'
						Times = $expected.Execution.ParseScriptBlockHeaders.RunTimes
						Exactly = $true
					}
					Assert-MockCalled @assMParams
				}

				it "should return [$($expected.Output.ReturnValue)]" {
					$result | should be $expected.Output.ReturnValue
				}

				it "should return [$($expected.Output.ObjectCount)] object(s)" {
					@($result).Count | should be $expected.Output.ObjectCount
				}

				it 'should return the same object type in OutputType()' {
					$result | should beoftype $script:command.OutputType.Name
				}
			}
		}
	}

	describe 'Get-CompanyAdUser' -Tag Unit {
		
		$commandName = 'Get-CompanyAdUser'
	
		#region Mocks
			mock 'Get-AdUser' {
				$script:allAdUsers
			}
		#endregion
	
		$testCases = @(
			@{
				Label = 'Single field match and field sync'
				Parameters = @{
					FieldMatchMap = @{ 'PERSON_NUM' = 'employeeId' }
					FieldSyncMap = @{ 'csvTitle' = 'title' }
				}
				Expected = @{
					Output = @{
						ObjectCount = 9
					}
				}
			}
			@{
				Label = 'Multiple field match and field sync'
				Parameters = @{
					FieldMatchMap = @{ 
						'PERSON_NUM' = 'employeeId'
						'csvId' = 'samAccountName' 
					}
					FieldSyncMap = @{ 
						'csvTitle' = 'title'
						'csvotherprop' = 'OtherProperty'
					}
				}
				Expected = @{
					Output = @{
						ObjectCount = 10
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$result = & $commandName @parameters

				it "should return [$($expected.Output.ObjectCount)] objects" {
					$result.Count | should be $expected.Output.ObjectCount	
				}
	
			}
		}
	}

	describe 'New-CompanyAdUser' -Tag Unit {
		
		$commandName = 'New-CompanyAdUser'
		$script:command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'New-AdUser'

			mock 'Set-AdUser'

			mock 'NewRandomPassword' {
				ConvertTo-SecureString -Strin 'pwhere' -AsPlainText -Force
			}
		#endregion
	
		$testCases = @(
			@{
				Label = 'Set-AdUser not needed'
				Parameters = @{
					Identity = 'foo'
					Attributes = @{ City = 'cityhere'; Office = 'officehere'}
					Confirm = $false
				}
				Expected = @{
					Execution = @{
						'New-AdUser' = @{
							Parameters = @{
								Name = 'foo'
								City = 'cityhere'
								Office = 'officehere'
							}
							RunTimes = 1
						}
					}
					Output = @{
						ObjectCount = 0
					}
				}
			}
			@{
				Label = 'Set-AdUser needed'
				Parameters = @{
					Identity = 'foo'
					Attributes = @{ City = 'cityhere'; Office = 'officehere'; 'otherattrib' = 'otherattribhere' }
					Confirm = $false
				}
				Expected = @{
					Execution = @{
						'New-AdUser' = @{
							Parameters = @{
								Name = 'foo'
								City = 'cityhere'
								Office = 'officehere'
							}
							RunTimes = 1
						}
						'Set-AdUser' = @{
							Parameters = @{
								Identity = 'foo'
								Add = @{ OtherAttrib = 'otherattribhere' }
							}
							RunTimes = 1
						}
					}
					Output = @{
						ObjectCount = 0
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				if ('Set-AdUser' -in $expected.Execution.Keys) {
					context 'when all attributes cannot be defined with New-AdUser alone' {
					
						$null = & $commandName @parameters

						it 'should pass the expected parameters to Set-AdUser' {

							$thisFunc = $expected.Execution.'Set-AdUser'
						
							$assMParams = @{
								CommandName = 'Set-AdUser'
								Times = $thisfunc.RunTimes
								Exactly = $true
								ExclusiveFilter = {
									[string]($PSBoundParameters.Identity) -eq [string]($thisFunc.Parameters.Identity) -and
									$PSBoundParameters.Add.OtherAttrib -eq $thisFunc.Parameters.Add.OtherAttrib
								}
							}
							Assert-MockCalled @assMParams
						}

						it 'should pass the expected parameters to New-AdUser' {

							$thisFunc = $expected.Execution.'New-AdUser'
						
							$assMParams = @{
								CommandName = 'New-AdUser'
								Times = $thisfunc.RunTImes
								Exactly = $true
								ExclusiveFilter = { 
									$PSBoundParameters.Name -eq $thisFunc.Parameters.Name -and
									$PSBoundParameters.City -eq $thisFunc.Parameters.City -and
									$PSBoundParameters.Office -eq $thisFunc.Parameters.Office
								}
							}
							Assert-MockCalled @assMParams
						}
					}
				} else {
					context 'when all attributes can be defined with New-AdUser alone' {
					
						$null = & $commandName @parameters

						it 'should pass the expected parameters to New-AdUser' {

							$thisFunc = $expected.Execution.'New-AdUser'
						
							$assMParams = @{
								CommandName = 'New-AdUser'
								Times = $thisfunc.RunTImes
								Exactly = $true
								ExclusiveFilter = {
									$PSBoundParameters.Name -eq $thisFunc.Parameters.Name -and
									$PSBoundParameters.City -eq $thisFunc.Parameters.City -and
									$PSBoundParameters.Office -eq $thisFunc.Parameters.Office
								}
							}
							Assert-MockCalled @assMParams
						}

						it 'should not call Set-AdUser' {
							$assMParams = @{
								CommandName = 'Set-AdUser'
								Times = 0
								Exactly = $true
							}
							Assert-MockCalled @assMParams
						}
					}
				}
			}
		}
	}

	describe 'ConvertToAdAttribute' {
		
		$commandName = 'ConvertToAdAttribute'
		$script:command = Get-Command -Name $commandName
	
		$testCases = @(
			@{
				Label = 'Multiple fields'
				Parameters = @{
					CsvUser = ([pscustomobject]@{ 
						'csvcity' = 'x'
						'csvtitle' = 'y'
					})
					FieldMap = @{
						'csvcity' = 'adcity'
						'csvtitle' = 'adtitle'
					}
				}
				Expected = @{
					Output = @{
						Returns = @{ 
							'adcity' = 'x'
							'adtitle' = 'y'
						}
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Multiple fields / one match'
				Parameters = @{
					CsvUser = ([pscustomobject]@{ 
						'csvcity' = 'x'
						'csvtitle' = 'y'
					})
					FieldMap = @{
						'csvcity' = 'adcity'
						'csvtitletypo' = 'adtitle'
					}
				}
				Expected = @{
					Output = @{
						Returns = @{ 
							'adcity' = 'x'
						}
						ObjectCount = 1
					}

				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$result = & $commandName @parameters
	
				it "should return [$($expected.Output.ObjectCount)] object(s)" {
					@($result).Count | should be $expected.Output.ObjectCount
				}

				it 'should return the same object type in OutputType()' {
					$result | should beoftype $script:command.OutputType.Name
				}

				it 'should return the expected hashtable' {
					-not (Compare-Object ([array]$result.Keys) $expected.Output.Returns.Keys) -and
					-not (Compare-Object ([array]$result.Values) $expected.Output.Returns.Values)
				}
			}
		}
	}

	describe 'FindUserMatch' -Tag Unit {
	
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

		context 'when multiple matches on a single attribute are found' {
			

			it 'should throw an exception: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)

				{ & $commandName @parameters } | should throw 
			}
		
		}

		context 'When multiple matches on different attributes are be found' {

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

	describe 'FindAttributeMismatch' -Tag Unit {
	
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
		
		$testCases = @(
			@{
				Label = 'Mismatch'
				Parameters = @{
					AdUser = $script:AdUserMisMatch
					CsvUser = $script:csvUserMisMatch
					FieldSyncMap = @{ 'OtherAttrib' = 'otherattribmap' }
				}
			}
			@{
				Label = 'No mismatch'
				Parameters = @{
					AdUser = $script:AdUserNoMisMatch
					CsvUser = $script:csvUserNoMisMatch
					FieldSyncMap = @{ 'OtherAttrib' = 'otherattribmap' }
				}
			}
		)

		foreach ($testCase in $testCases) {

			$parameters = $testCase.Parameters

			context $testCase.Label {

				if ($testCase.Label -eq 'No mismatch') {
					context 'when no attribute mismatch is found' {

						$result = & $commandName @parameters

						it 'should return nothing' {
							$result | should benullorempty
						}

					}
				}

				if ($testCase.Label -eq 'Mismatch') {
					context 'when an attribute mismatch is found' {

						$result = & $commandName @parameters
						
						it 'should return the expected objects' {
							@($result).Count | should be 1
							$result | should beoftype 'hashtable'
							$result.ActiveDirectoryAttribute.otherattribmap | should benullorempty
							$result.CSVField.OtherAttrib | should be 'x'
							$result.ADShouldBe.otherattribmap | should be 'x'
						}
					}
				}
			}
		}
	}

	describe 'ConvertToAdUser' {
		
		$commandName = 'ConvertToAdUser'

		mock 'Get-AdUser'
	
		$testCases = @(
			@{
				Label = 'username'
				Parameters = @{
					String = 'jdoe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(samAccountName=jdoe)'
				}
			}
			@{
				Label = 'FirstName LastName'
				Parameters = @{
					String = 'John Doe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'FirstName      LastName'
				Parameters = @{
					String = 'John      Doe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'FirstName LastName'
				Parameters = @{
					String = 'John Doe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'LastName, FirstName'
				Parameters = @{
					String = 'Doe, John'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'LastName,FirstName'
				Parameters = @{
					String = 'Doe,John'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'DistinguishedName'
				Parameters = @{
					String = 'CN=jdoe,DC=domain,DC=local'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(distinguishedName=CN=jdoe,DC=domain,DC=local)'
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$null = & $commandName @parameters

				it 'should query for the expected user' {
					$assMParams = @{
						CommandName = 'Get-AdUser'
						Times = 1
						Exactly = $true
						ExclusiveFilter = { 
							$PSBoundParameters.LdapFilter -eq $expected.LdapFilter
						}
					}
					Assert-MockCalled @assMParams
				}
	
			}
		}
	}

	describe 'ConvertToSchemaValue' {
		
		$commandName = 'ConvertToSchemaValue'
	
		#region Mocks
			mock 'ConvertToAdUser' {
				[pscustomobject]@{
					DistinguishedName = 'dnhere'
				}
			}
		#endregion
	
		$testCases = @(
			@{
				Label = 'Conversion needed'
				Parameters = @{
					AttributeName = 'manager'
					AttributeValue = 'Test User'
				}
				Expected = @{
					Output = 'dnhere'
				}
			}
			@{
				Label = 'No conversion needed'
				Parameters = @{
					AttributeName = 'foo'
					AttributeValue = 'Test User'
				}
				Expected = @{
					Output = 'Test User'
				}
			}
		)

		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$result = & $commandName @parameters

				it 'should return the expected string' {
					$result | should be $expected.Output
				}

			}
		}
	}

	describe 'NewDirectorySearcherUserFilter' {
		
		$commandName = 'NewDirectorySearcherUserFilter'
	
		$testCases = @(
			@{
				Label = 'samAccountName'
				Parameters = @{
					Elements = @{ samAccountName = 'foo'}
				}
				Expected = @{
					Output = @{
						ReturnString = '(&(objectCategory=person)(objectClass=User)(&(samAccountName=foo)))'
					}
				}
			}
			@{
				Label = 'givenName/surName'
				Parameters = @{
					Elements = @{ givenName = 'Adam'; sn = 'Bertram'}
				}
				Expected = @{
					Output = @{
						ReturnString = '(&(objectCategory=person)(objectClass=User)(&(givenName=Adam)(sn=Bertram)))'
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$result = & $commandName @parameters

				it "should return [$($expected.Output.ReturnString)]" {
					$result | should be $expected.Output.ReturnString
				}
	
			}
		}
	}

	describe 'TestIsValidAdAttribute' -Tag Unit {
		
		$commandName = 'TestIsValidAdAttribute'
	
		$testCases = @(
			@{
				Label = 'Mandatory'
				Parameters = @{
					Name = 'attribname'
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
	
			context $testCase.Label {
	
				context 'when the attribute exists' {

					mock 'Get-AvailableAdUserAttribute' {
						[pscustomobject]@{
							'ValidName' = 'attribName'
						}
					}
	
					$result = & $commandName @parameters
	
					it 'should return $true' {
						$result | should be $true
					}
				}
	
				context 'when the attribute does not exist' {

					mock 'Get-AvailableAdUserAttribute' {
						@('notinhere')
					}
	
					$result = & $commandName @parameters
	
					it 'should return $false' {
						$result | should be $false
					}
				}
			}
		}
	}

	describe 'SetAduser' -Tag Unit {
	
		$commandName = 'SetAduser'
		
		mock 'Set-AdUser'

		mock 'ConvertToSchemaAttributeType' {
			'1/1/01'
		} -ParameterFilter { $AttributeName -eq 'accountExpires' }

		mock 'ConvertToSchemaAttributeType' {
			'empidhere'
		} -ParameterFilter { $AttributeName -eq 'empidhere' }

		mock 'ConvertToSchemaAttributeType' {
			'displaynamehere'
		} -ParameterFilter { $AttributeName -eq 'displaynamehere' }

		mock 'ConvertToSchemaAttributeType' {
			'1/1/01'
		} -ParameterFilter { $AttributeName -eq '1/1/01' }
	
		$parameterSets = @(
			@{
				Identity = @{ samAccountName = 'samnamehere'}
				ActiveDirectoryAttributes = @{ employeeId = 'empidhere' }
			}
			@{
				Identity = @{ employeeId = 'empidhere'}
				ActiveDirectoryAttributes = @{ displayName = 'displaynamehere' }
			}
			@{
				Identity = @{ employeeId = 'empidhere'}
				ActiveDirectoryAttributes = @{ accountExpires = '1/1/01' }
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'returns nothing' -TestCases $testCases.All {
			param($Identity,$ActiveDirectoryAttributes)

			& $commandName @PSBoundParameters -Confirm:$false | should benullorempty
		}

		it 'should set the expected attribute' -TestCases $testCases.All {
			param($Identity,$ActiveDirectoryAttributes)

			## Need to account for the addition of ConvertToSchemaValue
		
			& $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'Set-AdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Replace.Keys -match 'displayName|employeeId|accountexpires' -and
					$PSBoundParameters.Replace.Values -match 'displayNameHere|empIdHere|1/1/01'
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'should set the expected identity' -TestCases $testCases.All {
			param($Identity,$ActiveDirectoryAttributes)

			& $commandName @PSBoundParameters -Confirm:$false
		
			$assMParams = @{
				CommandName = 'Set-AdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Identity -eq $Identity
				}
			}
			Assert-MockCalled @assMParams
		}
	
	}

	describe 'SyncCompanyUser' -Tag Unit {
	
		$commandName = 'SyncCompanyUser'

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
				Label = 'SamAccountName Identifier'
				Parameters = @{
					Identity = 'foo'
					CsvUser = $script:csvUser
					ActiveDirectoryAttributes = @{ 
						'atttribtosync1' = 'attribtosyncval1'
					}
				}
				Expect = @(
					@{
						Type = 'Function parameters'
						Name = 'SetAdUser'
						Parameters = @(
							@{
								Identity = 'foo'
								ActiveDirectoryAttributes = @{ 'atttribtosync1' = 'attribtosyncval1' }
							}
						)
					}
				)
			}
			@{
				Label = 'EmployeeId Identifier, 2 Attributes hashtables'
				Parameters = @{
					Identity = 'bar'
					CsvUser = $script:csvUser
					ActiveDirectoryAttributes = @{ 
						'atttribtosync1' = 'attribtosyncval1'
						'atttribtosync2' = 'attribtosyncval2'
					}
				}
				Expect = @(
					@{
						Type = 'Function parameters'
						Name = 'SetAdUser'
						Parameters = @(
							@{
								Identity = 'bar'
								ActiveDirectoryAttributes = @(@{ 'atttribtosync1' = 'attribtosyncval1' },@{ 'atttribtosync2' = 'attribtosyncval2' })
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
						Times = @($funcParams.ActiveDirectoryAttributes).Count
						Exactly = $true
						ParameterFilter = {
							$expectedkeys = $expectedParams.Parameters.ActiveDirectoryAttributes | ForEach-Object { $_.Keys }
							$expectedVals = $expectedParams.Parameters.ActiveDirectoryAttributes | ForEach-Object { $_.Values }
							
							$actualKeys = $PSBoundParameters.ActiveDirectoryAttributes  | ForEach-Object { $_.Keys }
							$actualValues = $PSBoundParameters.ActiveDirectoryAttributes  | ForEach-Object { $_.Values }
							-not (Compare-Object $expectedkeys $actualKeys) -and -not (Compare-Object $expectedVals $actualValues)
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
								$PSBoundParameters.Identity -in $i.Identity
							}
						}
					}
					Assert-MockCalled @assMParams
				}
			}
		}
	}
		
	describe 'WriteLog' -Tag Unit {
	
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

	describe 'Invoke-AdSync' -Tag Unit {
	
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
					'ADDisplayName' = 'displaynameval'
					'OtherProperty' = 'otherval'
					'EmployeeId' = 1
					'ADTitle' = 'titleval'
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
				$script:testAdUser
			}

			mock 'Get-CompanyCsvUser' {
				[pscustomobject]@{ 
					AD_LOGON = "nameval"
					PERSON_NUM = "1"
					CsvTitle = 'sync1'
					CsvDisplayName = 'sync2'
				}
			}

			mock 'FindUserMatch'

			mock 'GetCsvIdField' {
				[pscustomobject]@{
					Field = 'PERSON_NUM'
					Value = '1'
				}
			}

			mock 'Write-Output'

			mock 'TestIsValidAdAttribute' {
				$true
			}
		#endregion

		$parameterSets = @(
			@{
				Label = 'ReportOnly'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
					ReportOnly = $true
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
			@{
				Label = 'Single sync /single match field'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
			@{
				Label = 'Multi sync/Multi match field'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 
						'CsvTitle' = 'ADTitle'
						'CSVDisplayName' = 'ADDisplayName'
						({ if (-not $_.CsvNullField) { 'CsvNonNullField' }}) = 'ADDisplayName3'
					}
					FieldMatchMap = @{ 
						PERSON_NUM = 'EmployeeId'
						AD_LOGON = 'samAcountName'
					}
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 3
						}
					}
				}
			}
			@{
				Label = 'Exclude'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
					Exclude = @{ ExcludeCol = 'excludeme' }
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
		)

		$testCases = $parameterSets

		foreach ($testCase in $testCases) {

			$parameters = $testCase.Parameters
			$expect = $testCase.Expect

			context $testCase.Label {

				if ($parameters.ContainsKey('Exclude')) {

					context 'when excluding a CSV column' {

						$null = & $commandName @parameters

						context 'when a header does not exist' {
						
							mock 'TestCsvHeaderExists' {
								$false
							} -ParameterFilter { 'excludecol' -in $Header }

							it 'should throw an exception' {
								$params = @{} + $parameters
								{ & $commandName @params } | should throw 'One or more CSV headers excluded with -Exclude do not exist in the CSV file'
							}
						
						}

						context 'when all headers exist' {
						
							mock 'TestCsvHeaderExists' {
								$true
							}

							$null = & $commandName @parameters

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

				context 'Shared tests' {
				
					$null = & $commandName @parameters

					it 'should only test string AD attributes in FieldSyncMap' {

						$thisFunc = $expect.Execution.TestIsValidAdAttribute
						
						$assMParams = @{
							CommandName = 'TestIsValidAdAttribute'
							Times = $thisFunc.RunTimes
							Exactly = $true
							ExclusiveFilter = { $PSBoundParameters.Name -is 'string' }
						}
						Assert-MockCalled @assMParams
					}
				
				}

				context 'when at least one AD attribute in FieldSyncMap is not available' {

					mock 'TestIsValidAdAttribute' {
						$false
					}
				
					it 'should throw an exception' {
					
						$params = @{} + $parameters
						{ & $commandName @params } | should throw 'One or more AD attributes in FieldSyncMap do not exist'
					}
				
				}

				context 'when at least one CSV field in FieldMatchMap is not available' {

					mock 'TestCsvHeaderExists' {
						$false
					} -ParameterFilter { 'excludecol' -notin $Header }
				
					it 'should throw an exception' {
					
						$params = @{} + $parameters
						{ & $commandName @params } | should throw 'One or more CSV headers in FieldMatchMap do not exist in the CSV file'
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

								$null = & $commandName @parameters
								
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

								$null = & $commandName @parameters

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
									CSVField = @{'x' = 'y'}
									ActiveDirectoryAttribute = @{ 'z' = 'i' }
									ADShouldBe = @{ 'z' = 'y' }
								}
							}

							if ($parameters.ContainsKey('ReportOnly')) {
								context 'when only reporting' {

									$null = & $commandName @parameters

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

									$null = & $commandName @parameters

									it 'should sync the expected user' {

										$assMParams = @{
											CommandName = 'SyncCompanyUser'
											Times = 1
											Exactly = $true
											ParameterFilter = { 
												$PSBoundParameters.Identity -eq 'samval' -and
												$PSBoundParameters.CsvUser.'AD_LOGON' -eq 'nameval' -and
												$PSBoundParameters.CsvUser.'PERSON_NUM' -eq "1" -and
												$PSBoundParameters.ActiveDirectoryAttributes.z -eq 'y'
											}
										}
										Assert-MockCalled @assMParams
									}
								}
							}
						}

						context 'when all attributes are in sync' {

							mock 'FindAttributeMismatch'

							$null = & $commandName @parameters
						
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

	describe 'Invoke-AdSync - Functional' -Tag Functional {
		
		$commandName = 'Invoke-AdSync'

		$testUserName = 'psadsynctestuser'
		$testUserEmpId = 999999
		$testUserManagerName = 'psadsynctumanager'
		$testUserManagerEmpId = 111111


		mock 'Write-Output'
	
		$testCases = @(
			@{
				Label = 'Syncing a single string attribute'
				Parameters = @{
					CsvFilePath = "$PSScriptRoot\TestUsers.csv"
					FieldSyncMap = @{ 'FIRST_NAME' = 'givenName'}
					FieldMatchMap = @{'PERSON_NUM' = 'employeeId'}
				}
				Expected = @{
					ActiveDirectoryUser = @{
						Identifier = @{ 'employeeId' = $testUserEmpId }
						Attributes = @{
							givenName = 'changedfirstname'
						}
					}	
				}
			}
			@{
				Label = 'Syncing a single string attribute that needs converting'
				Parameters = @{
					CsvFilePath = "$PSScriptRoot\TestUsers.csv"
					FieldSyncMap = @{ 'SUPERVISOR' = 'manager'}
					FieldMatchMap = @{'PERSON_NUM' = 'employeeId'}
				}
				Expected = @{
					ActiveDirectoryUser = @{
						Identifier = @{ 'employeeId' = $testUserEmpId }
						Attributes = @{
							manager = "CN=$testUserManagerName,DC=mylab,DC=local"
						}
					}
				}
			}
			@{
				Label = 'Syncing a multiple string attributes'
				Parameters = @{
					CsvFilePath = "$PSScriptRoot\TestUsers.csv"
					FieldSyncMap = @{ 
						'FIRST_NAME' = 'givenName'
						'LAST_NAME' = 'sn'
					}
					FieldMatchMap = @{'PERSON_NUM' = 'employeeId'}
				}
				Expected = @{
					ActiveDirectoryUser = @{
						Identifier = @{ 'employeeId' = $testUserEmpId }
						Attributes = @{
							givenName = 'changedfirstname'
							surName = 'changedlastname'
						}
					}	
				}
			}
			@{
				Label = 'Syncing a multiple string attributes and a scriptblock condition'
				Parameters = @{
					CsvFilePath = "$PSScriptRoot\TestUsers.csv"
					FieldSyncMap = @{
						{ if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME' }} = 'givenName'
						'CONTRACT_END_DATE' = 'accountexpires'
						'LAST_NAME' = 'sn'
					}
					FieldMatchMap = @{'PERSON_NUM' = 'employeeId'}
				}
				Expected = @{
					ActiveDirectoryUser = @{
						Identifier = @{ 'employeeId' = $testUserEmpId }
						Attributes = @{
							givenName = 'changednickname123'
							surName = 'changedlastname'
							AccountExpirationDate = '12/30/2018 19:00:00'
						}
					}	
				}
			}
			@{
				Label = 'Syncing a multiple string attributes and a scriptblock condition with FieldValueMap'
				Parameters = @{
					CsvFilePath = "$PSScriptRoot\TestUsers.csv"
					FieldSyncMap = @{
						{ if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME' }} = 'givenName'
						'CONTRACT_END_DATE' = 'accountexpires'
						'LAST_NAME' = 'sn'
						'SUPERVISOR' = 'manager'
					}
					FieldMatchMap = @{'PERSON_NUM' = 'employeeId'}
					FieldValueMap = @{ 'SUPERVISOR' = { $null = $_.SuperVisor -match '(?<LastName>\w+)\s(?<FirstName>\w+)\s\((?<NickName>\w+)'; "$($matches['LastName']) $($matches['FirstName'])"  }}
				}
				Expected = @{
					ActiveDirectoryUser = @{
						Identifier = @{ 'employeeId' = $testUserEmpId }
						Attributes = @{
							givenName = 'changednickname123'
							surName = 'changedlastname'
							AccountExpirationDate = '12/30/2018 19:00:00'
							manager = "CN=$testUserManagerName,DC=mylab,DC=local"
						}
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {	
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected

			## Clean up the environment ahead of time
			Get-AdUser -Filter "samAccountName -eq '$testUserName'" | Remove-AdUser -Confirm:$false
			Get-AdUser -Filter "samAccountName -eq '$testUserManagerName'" | Remove-AdUser -Confirm:$false
			New-ADUser -GivenName 'ChangeMe' -Surname 'ChangeMe' -EmployeeID $testUserEmpId -Name $testUserName

			context $testCase.Label {

				if ('manager' -in $parameters.FieldSyncMap.Values) {
				
					context 'when a manager field is being synced' {

						context 'when the manager account exists' {
						
							New-ADUser -GivenName 'TestUser' -Surname 'Manager' -EmployeeID $testUserManagerEmpId -Name $testUserManagerName

							if (-not $parameters.ContainsKey('FieldValueMap')) {
								context 'when the manager account cannot be found' {

									mock 'Write-Warning'
								
									& $commandName @parameters -Confirm:$false

									it 'should pass the expected parameters to Write-Warning' {
									
										$assMParams = @{
											CommandName = 'Write-Warning'
											Times = 1
											Exactly = $true
											ExclusiveFilter = {
												$PSBoundParameters.Message -match 'Unable to convert'
											}
										}
										Assert-MockCalled @assMParams
									}
								}
							} else {

								& $commandName @parameters -Confirm:$false

								$getParams = @{
									Filter = "$($expected.ActiveDirectoryUser.Identifier.Keys) -eq $($expected.ActiveDirectoryUser.Identifier.Values)"
									Properties = '*'
								}
								$testAdUser = Get-Aduser @getParams
								
							}

							it 'should write the expected values to the log file' -Skip {
					
							}

							it 'should change the expected AD user attributes' {
								@($expected.ActiveDirectoryUser.Attributes).foreach({
									$testAdUser.Keys | should be $testAdUser.Values
								})	
							}
						}

						# context 'when the manager account does not exist' {

						# 	Get-AdUser -Filter "samAccountName -eq '$testUserManagerName'" | Remove-AdUser -Confirm:$false
						
						# 	it 'should throw an exception' {
							
						# 		{ & $commandName @parameters } | should throw 'Unable to find manager user account'
						# 	}
						
						# }
					}
				} else {
					& $commandName @parameters -Confirm:$false

					$getParams = @{
						Filter = "$($expected.ActiveDirectoryUser.Identifier.Keys) -eq $($expected.ActiveDirectoryUser.Identifier.Values)"
						Properties = '*'
					}
					$testAdUser = Get-Aduser @getParams

					it 'should change the expected AD user attributes' {
						$expected.ActiveDirectoryUser.Attributes.GetEnumerator().foreach({
							Write-Host "$($testAdUser.($_.Key)) should be [$($_.Value)]"
							$testAdUser.($_.Key) | should be $_.Value
						})	
					}

					it 'should write the expected values to the log file' -Skip {
					
					}
				}
			}
		}
	}

	Remove-Variable -Name allAdUsers -Scope Script
	Remove-Variable -Name allCsvUsers -Scope Script
}
