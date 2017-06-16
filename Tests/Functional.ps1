#region import modules
$ThisModule = "$($MyInvocation.MyCommand.Path | Split-Path -Parent | Split-Path -Parent)\PSADSync.psd1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psd1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force

Import-Module -Name $ThisModule -Force -ErrorAction Stop
#endregion

$script:csvLogFilePath = '.\PSAdSync.csv'
$script:csvInputFilePath = "$PSScriptRoot\TestUsers.csv"

$script:csvRows = @(
    [pscustomobject]@{
        csvEmployeeIdField = '1'
        csvsamAccountNameIdField = 'psadsyncuser1'
        csvAccountExpiresSyncField = '1/1/20'
        csvManagerIdSyncField = '6'
        csvFirstNameSyncField = 'firstnamechangeme1'
        csvLastNameSyncField = 'lastnamechangeme1'
        csvNickNameSyncField = 'nicknamechangeme1'
        csvManagerSyncField = 'managerchangeme1'
    }
    [pscustomobject]@{
        csvEmployeeIdField = $null
        csvsamAccountNameIdField = 'psadsyncuser2'
        csvAccountExpiresSyncField = $null
        csvManagerIdSyncField = '7'
       	csvFirstNameSyncField = 'firstnamechangeme2'
        csvLastNameSyncField = 'lastnamechangeme2'
        csvNickNameSyncField = 'nicknamechangeme2'
        csvManagerSyncField = 'managerchangeme2'
    }
    [pscustomobject]@{
		csvEmployeeIdField = '3'
        csvsamAccountNameIdField = $null
        csvAccountExpiresSyncField = '1/1/20'
        csvManagerIdSyncField = '8'
       	csvFirstNameSyncField = 'firstnamechangeme3'
        csvLastNameSyncField = 'lastnamechangeme3'
        csvNickNameSyncField = 'nicknamechangeme3'
        csvManagerSyncField = 'managerchangeme3'
    }
    [pscustomobject]@{
		csvEmployeeIdField = $null
         csvsamAccountNameIdField = 'psadsyncuser4'
        csvAccountExpiresSyncField = '1/1/20'
        csvManagerIdSyncField = '6'
       	csvFirstNameSyncField = 'firstnamechangeme4'
        csvLastNameSyncField = 'lastnamechangeme4'
        csvNickNameSyncField = 'nicknamechangeme4'
        csvManagerSyncField = 'managerchangeme4'
    }
    ## This is the big boss with managers reporting to this person. He has no manager
    [pscustomobject]@{
		csvEmployeeIdField = '5'
         csvsamAccountNameIdField = 'psadsyncuser5'
        csvAccountExpiresSyncField = $null
        csvManagerIdSyncField = $null
        csvFirstNameSyncField = 'firstnamechangeme5'
        csvLastNameSyncField = 'lastnamechangeme5'
        csvNickNameSyncField = $null
        csvManagerSyncField = $null
    }
    ## This is also a manager
    [pscustomobject]@{
		csvEmployeeIdField = '6'
        csvsamAccountNameIdField = 'psadsyncuser6'
        csvAccountExpiresSyncField = $null
        csvManagerIdSyncField = '5'
       	csvFirstNameSyncField = 'firstnamechangeme6'
        csvLastNameSyncField = 'lastnamechangeme6'
        csvNickNameSyncField = 'nicknamechangeme6'
        csvManagerSyncField = 'managerchangeme6'
    }
    ## This is also a manager
    [pscustomobject]@{
		csvEmployeeIdField = '7'
        csvsamAccountNameIdField = 'psadsyncuser7'
        csvAccountExpiresSyncField = $null
        csvManagerIdSyncField = '5'
        csvFirstNameSyncField = $null
        csvLastNameSyncField = $null
        csvNickNameSyncField = 'nicknamechangeme7'
        csvManagerSyncField = 'managerchangeme7'
    }
)
$script:csvRows | Export-Csv -Path $script:csvInputFilePath

$i = 1
$script:csvRows.foreach({
	$params = @{
		Name = $_.csvsamAccountNameIdField
		EmployeeId = $_.csvEmployeeIdField
		GivenName = "adgivenNameChangeMe$i"
		SurName = "adsurNameChangeMe$i"
		Manager = 'CN=Administrator,DC=mylab,DC=local'
	}
	if (-not $_.csvAccountExpiresSyncField) {
		$params.AccountExpirationDate = [datetime]'1/1/20'
	}
	New-AdUser @params
	$i++
})

function CleanEnvironment
{
    param()

    $empIdsUsed = 1..10
    $empIdsUsed.foreach({
            Get-Aduser -Filter "EmployeeId -eq '$_'" | Remove-AdUser -Confirm:$false
        })

    $namesUsed = 'psadsynctestuser','psadsynctumanager'
    $namesUsed.foreach({
            Get-Aduser -Identity $_ | Remove-AdUser -Confirm:$false
        })

    Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore

}

describe 'Invoke-AdSync' {
		
	$commandName = 'Invoke-AdSync'

	$testCases = @(
		@{
			Label = 'Syncing a single string attribute'
			Parameters = @{
				CsvFilePath = $script:csvInputFilePath
				FieldSyncMap = @{ 'csvFirstNameSyncField' = 'givenName'}
				FieldMatchMap = @{'csvEmployeeIdField' = 'employeeId'}
			}
			Expected = @{
				MatchedActiveDirectoryUser = (Get-Aduser -Filter "EmployeeId -eq '1'")	
			}
		}
		@{
			Label = 'Syncing a multiple string attributes'
			Parameters = @{
				CsvFilePath = $script:csvInputFilePath
				FieldSyncMap = @{ 
					'csvFirstNameSyncField' = 'givenName'
					'csvLastNameSyncField' = 'sn'
				}
				FieldMatchMap = @{'csvEmployeeIdField' = 'employeeId'}
			}
			Expected = @{
				MatchedActiveDirectoryUser = (Get-Aduser -Filter "EmployeeId -eq '2'")	
			}
		}
		@{
			Label = 'Syncing a multiple string attributes and a scriptblock condition'
			Parameters = @{
				CsvFilePath = $script:csvInputFilePath
				FieldSyncMap = @{
					{ if ($_.'csvNickNameSyncField') { 'csvNickNameSyncField' } else { 'csvFirstNameSyncField' }} = 'givenName'
					'csvAccountExpiresSyncField' = 'accountexpires'
					'csvLastNameSyncField' = 'sn'
				}
				FieldMatchMap = @{'csvEmployeeIdField' = 'employeeId'}
			}
			Expected = @{
				MatchedActiveDirectoryUser = (Get-Aduser -Filter "EmployeeId -eq '1'")	
			}
		}
		@{
			Label = 'Syncing a multiple string attributes and a scriptblock condition with FieldValueMap'
			Parameters = @{
				CsvFilePath = $script:csvInputFilePath
				FieldSyncMap = @{
					{ if ($_.'csvNickNameSyncField') { 'csvNickNameSyncField' } else { 'csvFirstNameSyncField' }} = 'givenName'
					'csvAccountExpiresSyncField' = 'accountexpires'
					'csvLastNameSyncField' = 'sn'
					'csvManagerSyncField' = 'manager'
				}
				FieldMatchMap = @{'csvEmployeeIdField' = 'employeeId'}
				FieldValueMap = @{ 'csvManagerSyncField' = { $null = $_.SuperVisor -match '(?<LastName>\w+)\s(?<FirstName>\w+)\s\((?<NickName>\w+)'; "$($matches['LastName']) $($matches['FirstName'])"  }}
			}
			Expected = @{
				MatchedActiveDirectoryUser = (Get-Aduser -Filter "EmployeeId -eq '1'")	
			}
		}
	)

	foreach ($testCase in $testCases) {	

		$parameters = $testCase.Parameters
		$expected = $testCase.Expected

		## Clean up the environment ahead of time
		CleanEnvironment

		context $testCase.Label {

			if ('manager' -in $parameters.FieldSyncMap.Values) {
			
				context 'when a manager field is being synced' {

					context 'when the manager account exists' {



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


# $testCases = @(
#     @{
#         Label = 'Simple sync'
#         Parameters = @{
#             CsvFilePath = $script:csvInputFilePath
#             FieldMatchMap = @{ 'csvIdField1' = 'employeeId' }
#             FieldSyncMap = @{ 'csvFirstNameField' = 'givenName' }
#             Confirm = $false
#         }
#     }
#     @{
#         Label = 'Syncing a single string attribute that needs converting'
#         Parameters = @{
#             CsvFilePath = $script:csvInputFilePath
#             FieldSyncMap = @{ 'csvManagerIdSyncField' = 'manager'}
#             FieldMatchMap = @{ 'csvIdField1' = 'employeeId'}
#         }
#     }
#     @{
#         Label = 'Syncing a multiple string attributes'
#         Parameters = @{
#             CsvFilePath = $script:csvInputFilePath
#             FieldSyncMap = @{ 
#                 'csvFirstNameField' = 'givenName'
#                 'csvSyncDeptField' = 'department'
#             }
#             FieldMatchMap = @{'csvIdField1' = 'employeeId'}
#         }
#     }
#     @{
#         Label = 'Syncing a multiple string attributes and a scriptblock condition'
#         Parameters = @{
#             CsvFilePath = $script:csvInputFilePath
#             FieldSyncMap = @{
#                 { if ($_.'csvNickNameField') { 'csvNickNameField' } else { 'csvFirstNameField' }} = 'givenName'
#                 'csvDateTimeSyncField' = 'accountexpires'
#             }
#             FieldMatchMap = @{'csvIdField1' = 'employeeId'}
#         }
#     }
#     @{
#         Label = 'FieldValueMap scriptblock sync'
#         Parameters = @{
#             CsvFilePath = $script:csvInputFilePath
#             FieldSyncMap = @{
#                 'csvManagerIdSyncField' = 'manager'
#             }
#             FieldMatchMap = @{ 'csvIdField1' = 'employeeId' }
#             FieldValueMap = @{ 'csvManagerIdSyncField' = { $supId = $_.'csvManagerIdSyncField'; (Get-AdUser -Filter "EmployeeId -eq '$supId'").DistinguishedName }}
#         }
#     }
# )

# describe 'Invoke-AdSync' {
		
#     $commandName = 'Invoke-AdSync'

#     $testUserName = 'psadsynctestuser'
#     $testUserEmpId = 1
#     $testUserManagerName = 'psadsynctumanager'
#     $testUserManagerEmpId = 10

#     mock 'Write-Output'

#     $testCases = @(
#         @{
#             Label = 'Syncing a single string attribute'
#             Parameters = @{
#                 CsvFilePath = $script:csvInputFilePath
#                 FieldSyncMap = @{ 'csvSyncField1' = 'givenName'}
#                 FieldMatchMap = @{'csvIdField1' = 'employeeId'}
#             }
#             Expected = @{
#                 ActiveDirectoryUser = @{
#                     Identifier = @{ 'employeeId' = $testUserEmpId }
#                     Attributes = @{
#                         givenName = 'changedfirstname'
#                     }
#                 }	
#             }
#         }
#         @{
#             Label = 'Syncing a single string attribute that needs converting'
#             Parameters = @{
#                 CsvFilePath = $script:csvInputFilePath
#                 FieldValueMap = @{ 'csvSyncField3' = { $supId = $_.'csvManagerIdSyncField'; (Get-AdUser -Filter "EmployeeId -eq '$supId'").DistinguishedName }}
#                 FieldMatchMap = @{'csvIdField1' = 'employeeId'}
#             }
#             Expected = @{
#                 ActiveDirectoryUser = @{
#                     Identifier = @{ 'employeeId' = $testUserEmpId }
#                     Attributes = @{
#                         manager = "CN=$testUserManagerName,DC=mylab,DC=local"
#                     }
#                 }
#             }
#         }
#         @{
#             Label = 'Syncing a multiple string attributes'
#             Parameters = @{
#                 CsvFilePath = $script:csvInputFilePath
#                 FieldSyncMap = @{ 
#                     'csvSyncField1' = 'givenName'
#                     'csvSyncField2' = 'sn'
#                 }
#                 FieldMatchMap = @{'csvIdField1' = 'employeeId'}
#             }
#             Expected = @{
#                 ActiveDirectoryUser = @{
#                     Identifier = @{ 'employeeId' = $testUserEmpId }
#                     Attributes = @{
#                         givenName = 'changedfirstname'
#                         surName = 'changedlastname'
#                     }
#                 }	
#             }
#         }
#         @{
#             Label = 'Syncing a multiple string attributes and a scriptblock condition'
#             Parameters = @{
#                 CsvFilePath = $script:csvInputFilePath
#                 FieldSyncMap = @{
#                     { if ($_.'csvNickNameSyncField') { 'csvNickNameSyncField' } else { 'csvSyncField1' }} = 'givenName'
#                     'csvAccountExpiresSyncField' = 'accountexpires'
#                     'csvSyncField2' = 'sn'
#                 }
#                 FieldMatchMap = @{'csvIdField1' = 'employeeId'}
#             }
#             Expected = @{
#                 ActiveDirectoryUser = @{
#                     Identifier = @{ 'employeeId' = $testUserEmpId }
#                     Attributes = @{
#                         givenName = 'changednickname123'
#                         surName = 'changedlastname'
#                         AccountExpirationDate = '12/30/2018 19:00:00'
#                     }
#                 }	
#             }
#         }
#         @{
#             Label = 'Syncing a multiple string attributes and a scriptblock condition with FieldValueMap'
#             Parameters = @{
#                 CsvFilePath = $script:csvInputFilePath
#                 FieldSyncMap = @{
#                     { if ($_.'csvNickNameSyncField') { 'csvNickNameSyncField' } else { 'csvSyncField1' }} = 'givenName'
#                     'csvAccountExpiresSyncField' = 'accountexpires'
#                     'csvSyncField2' = 'sn'
#                     'csvManagerSyncField' = 'manager'
#                 }
#                 FieldMatchMap = @{'csvIdField1' = 'employeeId'}
#                 FieldValueMap = @{ 'csvManagerSyncField' = { $null = $_.SuperVisor -match '(?<LastName>\w+)\s(?<FirstName>\w+)\s\((?<NickName>\w+)'; "$($matches['LastName']) $($matches['FirstName'])"  }}
#             }
#             Expected = @{
#                 ActiveDirectoryUser = @{
#                     Identifier = @{ 'employeeId' = $testUserEmpId }
#                     Attributes = @{
#                         givenName = 'changednickname123'
#                         surName = 'changedlastname'
#                         AccountExpirationDate = '12/30/2018 19:00:00'
#                         manager = "CN=$testUserManagerName,DC=mylab,DC=local"
#                     }
#                 }
#             }
#         }
#     )

	

#     foreach ($testCase in $testCases)
#     {	

#         $parameters = $testCase.Parameters
#         $expected = $testCase.Expected

#         ## Clean up the environment ahead of time
#         CleanEnvironment
#         New-ADUser -GivenName 'ChangeMe' -Surname 'ChangeMe' -EmployeeID $testUserEmpId -Name $testUserName

#         context $testCase.Label {

#             if ('manager' -in $parameters.FieldSyncMap.Values)
#             {
			
#                 context 'when a manager field is being synced' {

#                     context 'when the manager account exists' {
					
#                         New-ADUser -GivenName 'TestUser' -Surname 'Manager' -EmployeeID $testUserManagerEmpId -Name $testUserManagerName

#                         if (-not $parameters.ContainsKey('FieldValueMap'))
#                         {
#                             context 'when the manager account cannot be found' {

#                                 mock 'Write-Warning'
							
#                                 & $commandName @parameters -Confirm:$false

#                                 it 'should pass the expected parameters to Write-Warning' {
								
#                                     $assMParams = @{
#                                         CommandName = 'Write-Warning'
#                                         Times = 1
#                                         Exactly = $true
#                                         ExclusiveFilter = {
#                                             $PSBoundParameters.Message -match 'Unable to convert'
#                                         }
#                                     }
#                                     Assert-MockCalled @assMParams
#                                 }
#                             }
#                         }
#                         else
#                         {

#                             & $commandName @parameters -Confirm:$false

#                             $getParams = @{
#                                 Filter = "$($expected.ActiveDirectoryUser.Identifier.Keys) -eq $($expected.ActiveDirectoryUser.Identifier.Values)"
#                                 Properties = '*'
#                             }
#                             $testAdUser = Get-Aduser @getParams
							
#                         }

#                         it 'should write the expected values to the log file' -Skip {
				
#                         }

#                         it 'should change the expected AD user attributes' {
#                             @($expected.ActiveDirectoryUser.Attributes).foreach({
#                                     $testAdUser.Keys | should be $testAdUser.Values
#                                 })	
#                         }
#                     }

#                     # context 'when the manager account does not exist' {

#                     # 	Get-AdUser -Filter "samAccountName -eq '$testUserManagerName'" | Remove-AdUser -Confirm:$false
					
#                     # 	it 'should throw an exception' {
						
#                     # 		{ & $commandName @parameters } | should throw 'Unable to find manager user account'
#                     # 	}
					
#                     # }
#                 }
#             }
#             else
#             {
#                 & $commandName @parameters -Confirm:$false

#                 $getParams = @{
#                     Filter = "$($expected.ActiveDirectoryUser.Identifier.Keys) -eq $($expected.ActiveDirectoryUser.Identifier.Values)"
#                     Properties = '*'
#                 }
#                 $testAdUser = Get-Aduser @getParams

#                 it 'should change the expected AD user attributes' {
#                     $expected.ActiveDirectoryUser.Attributes.GetEnumerator().foreach({
#                             Write-Host "$($testAdUser.($_.Key)) should be [$($_.Value)]"
#                             $testAdUser.($_.Key) | should be $_.Value
#                         })	
#                 }

#                 it 'should write the expected values to the log file' -Skip {
				
#                 }
#             }
#         }
#     }
# }
	
# # describe 'when a user cannot be matched' {

# # 	mock 'Write-Output'

# # 	AfterAll {
# # 		Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
# # 		Remove-Item -Path $script:csvInputFilePath -ErrorAction Ignore
# # 	}

# # 	foreach ($testCase in $testCases) {

# # 		$parameters = $testCase.Parameters

# # 		Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
# # 		Remove-Item -Path $script:csvInputFilePath -ErrorAction Ignore

# # 		## Ensure the AD environment is prepped
# # 		Get-AdUser -Filter "EmployeeId -eq '1'" | Remove-Aduser -Confirm:$false
# # 		Get-AdUser -Filter "samAccountName -eq 'psadsyncuser1 | Remove-Aduser -Confirm:$false

# # 		context $testCase.Label {

# # 			context 'when a CSV user has no identifier fields populated' {

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore

# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = $null
# # 						csvIdField2 = $null
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be 'N/A'
# # 					$row.CSVAttributeValue | should be 'N/A'
# # 					$row.ADAttributeName | should be 'NoMatch'
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'N/A'
# # 					$row.CsvIdentifierField | should be 'csvIdField1'

# # 				}
			
# # 			}

# # 			context 'when a CSV user has no matchable identifiers' {

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
			
# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = 'nomatch'
# # 						csvIdField2 = 'nomatch'
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be 'N/A'
# # 					$row.CSVAttributeValue | should be 'N/A'
# # 					$row.ADAttributeName | should be 'NoMatch'
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'N/A'
# # 					$row.CsvIdentifierField | should be 'csvIdField1'

# # 				}
			
# # 			}
# # 		}
# # 	}
# # }

# # describe 'when a user match can be found' {

# # 	mock 'Write-Output'

# # 	AfterAll {
# # 		Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
# # 		Remove-Item -Path $script:csvInputFilePath -ErrorAction Ignore
# # 	}

# # 	foreach ($testCase in $testCases) {

# # 		$parameters = $testCase.Parameters

# # 		Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
# # 		Remove-Item -Path $script:csvInputFilePath -ErrorAction Ignore

# # 		## Ensure the AD environment is prepped
# # 		Get-AdUser -Filter "EmployeeId -eq '1'" | Remove-Aduser -Confirm:$false
# # 		Get-AdUser -Filter "samAccountName -eq 'psadsyncuser1 | Remove-Aduser -Confirm:$false

# # 		context $testCase.Label {

# # 			context 'match can be found on only one identifer' {

# # 				AfterAll {
# # 					Get-AdUser -Filter "EmployeeId -eq '1'" | Remove-Aduser -Confirm:$false
# # 				}

# # 				New-AdUser -Name 'PSADSyncUser1' -EmployeeId 1

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore

# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = 1
# # 						csvIdField2 = $null
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be $parameters.FieldSyncMap.Keys
# # 					$row.CSVAttributeValue | should be $parameters.FieldSyncMap.Values
# # 					$row.ADAttributeName | should be $parameters.FieldSyncMap.Keys
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'NoMatch'
# # 					$row.CsvIdentifierField | should be 'NoMatch'

# # 				}
			
# # 			}

# # 			context 'match could potentially be matched on two identifiers' {

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
			
# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = 'nomatch'
# # 						csvIdField2 = 'nomatch'
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be 'NoMatch'
# # 					$row.CSVAttributeValue | should be 'NoMatch'
# # 					$row.ADAttributeName | should be 'NoMatch'
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'NoMatch'
# # 					$row.CsvIdentifierField | should be 'NoMatch'

# # 				}
			
# # 			}

# # 			context 'when matching on a manager ID in the CSV' {

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
			
# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = 'nomatch'
# # 						csvIdField2 = 'nomatch'
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be 'NoMatch'
# # 					$row.CSVAttributeValue | should be 'NoMatch'
# # 					$row.ADAttributeName | should be 'NoMatch'
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'NoMatch'
# # 					$row.CsvIdentifierField | should be 'NoMatch'

# # 				}
			
# # 			}

# # 			context 'the manager ID in the CSV does not exist in AD' {

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
			
# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = 'nomatch'
# # 						csvIdField2 = 'nomatch'
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be 'NoMatch'
# # 					$row.CSVAttributeValue | should be 'NoMatch'
# # 					$row.ADAttributeName | should be 'NoMatch'
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'NoMatch'
# # 					$row.CsvIdentifierField | should be 'NoMatch'

# # 				}
			
# # 			}

# # 			context 'when manager ID exists and is out of sync' {

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
			
# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = 'nomatch'
# # 						csvIdField2 = 'nomatch'
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be 'NoMatch'
# # 					$row.CSVAttributeValue | should be 'NoMatch'
# # 					$row.ADAttributeName | should be 'NoMatch'
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'NoMatch'
# # 					$row.CsvIdentifierField | should be 'NoMatch'

# # 				}
			
# # 			}

# # 			context 'when manager ID exists and is in sync' {

# # 				Remove-Item -Path $script:csvLogFilePath -ErrorAction Ignore
			
# # 				$csvUsers = @(
# # 					[pscustomobject]@{
# # 						csvIdField1 = 'nomatch'
# # 						csvIdField2 = 'nomatch'
# # 						csvDateTimeSyncField = '1/1/20'
# # 						csvManagerIdSyncField = '6'
# # 						csvSyncDeptField = 'csvSyncDeptField1Val'
# # 						csvFirstNameField = 'csvFirstNameFieldVal'
# # 					}
# # 				)

# # 				$csvUsers | Export-Csv -Path $script:csvInputFilePath -NoTypeInformation
				
# # 				$result = & Invoke-AdSync @parameters

# # 				it 'should write the expected row to the log file' {

# # 					$row = Import-Csv -Path $script:csvLogFilePath
# # 					$row.CSVAttributeName | should be 'NoMatch'
# # 					$row.CSVAttributeValue | should be 'NoMatch'
# # 					$row.ADAttributeName | should be 'NoMatch'
# # 					$row.ADAttributeValue | should be 'NoMatch'
# # 					$row.CsvIdentifierValue | should be 'NoMatch'
# # 					$row.CsvIdentifierField | should be 'NoMatch'

# # 				}
			
# # 			}


# # 		}
# # 	}
# # }

	

# # 		context 'when matching on the accountExpires field' {

# # 			context 'when the accountExpires CSV field cannot be converted to a datetime field' {

# # 			}
			
# # 			context 'when comparison is complete but found to be out of sync' {
				
# # 				$result = & Invoke-AdSync @parameters
				
# # 			}

# # 			context 'when comparison is complete and found to be in sync' {
				
# # 				$result = & Invoke-AdSync @parameters
				
# # 			}

# # 		}

# # 		context 'when matching on a standard string attribute' {
				
# # 			$result = & Invoke-AdSync @parameters

# # 			context 'when the CSV sync field to match is null' {
				
# # 				$result = & Invoke-AdSync @parameters
				
# # 			}

# # 			context 'when the CSV sync field to match is valid' {
				
# # 				$result = & Invoke-AdSync @parameters
				
# # 			}
			
# # 		}
# # 	}

		
# # 	)