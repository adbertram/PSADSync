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
	
		context 'Help' {
			
			$nativeParamNames = @(
				'Verbose'
				'Debug'
				'ErrorAction'
				'WarningAction'
				'InformationAction'
				'ErrorVariable'
				'WarningVariable'
				'InformationVariable'
				'OutVariable'
				'OutBuffer'
				'PipelineVariable'
				'Confirm'
				'WhatIf'
			)
			
			$command = Get-Command -Name $commandName
			$commandParamNames = [array]($command.Parameters.Keys | where {$_ -notin $nativeParamNames})
			$help = Get-Help -Name $commandName
			$helpParamNames = $help.parameters.parameter.name
			
			it 'has a SYNOPSIS defined' {
				$help.synopsis | should not match $commandName
			}
			
			it 'has at least one example' {
				$help.examples | should not benullorempty
			}
			
			it 'all help parameters have a description' {
				$help.Parameters | where { ('Description' -in $_.Parameter.PSObject.Properties.Name) -and (-not $_.Parameter.Description) } | should be $null
			}
			
			it 'there are no help parameters that refer to non-existent command paramaters' {
				if ($commandParamNames) {
				@(Compare-Object -ReferenceObject $helpParamNames -DifferenceObject $commandParamNames).where({
					$_.SideIndicator -eq '<='
				}) | should benullorempty
				}
			}
			
			it 'all command parameters have a help parameter defined' {
				if ($commandParamNames) {
				@(Compare-Object -ReferenceObject $helpParamNames -DifferenceObject $commandParamNames).where({
					$_.SideIndicator -eq '=>'
				}) | should benullorempty
				}
			}
		}
	}
}