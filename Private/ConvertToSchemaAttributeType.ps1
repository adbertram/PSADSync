function ConvertToSchemaAttributeType {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$AttributeName,

		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[AllowNull()]
		$AttributeValue,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[ValidateSet('Read', 'Set')]
		[string]$Action
	)

	if ($AttributeValue) {
		switch ($AttributeName) {
			'accountExpires' {
				if ((-not $AttributeValue) -or ($AttributeValue -eq '9223372036854775807')) {
					0
				} else {
					if ([string]$AttributeValue -as [DateTime]) {
						$date = ([datetime]$AttributeValue).Date
					} else {
						$date = ([datetime]::FromFileTime($AttributeValue)).Date
					}
					switch ($Action) {
						'Read' {
							$date.AddDays(-1)
						}
						'Set' {
							$date.AddDays(2)
						}
						default {
							throw "Unrecognized input: [$_]"
						}
					}
				}
			}
			'countryCode' {
				## Load once only
				if (-not (Get-Variable -Name 'countryCodes' -Scope Script -ErrorAction Ignore)) {
					$script:countryCodes = Get-AvailableCountryCodes
				}
				## ie. match on United States or just US
				if (-not ($code = @($script:countryCodes).where({ $_.activeDirectoryName -eq $AttributeValue -or $_.alpha2 -eq $AttributeValue }))) {
					throw "Country code for name [$($AttributeValue)] could not be found."
				}
				$code.Numeric
			}
			'manager' {
				if ($AttributeValue -notmatch '^(?:(?<cn>CN=(?<name>[^,]*)),)?(?:(?<path>(?:(?:CN|OU)=[^,]+,?)+),)?(?<domain>(?:DC=[^,]+,?)+)$') {
					## Assume the Manager field is "<First Name> <Last Name>"
					$managerFirstName = $AttributeValue.Split(' ')[0]
					$managerLastName = $AttributeValue.Split(' ')[1]
					## Find the DN
					if (-not ($managerUser = $script:adUsers | where { $_.GivenName -eq $managerFirstName -and $_.sn -eq $managerLastName })) {
						throw 'Could not find manager distinguished name.'
					} else {
						$managerUser.DistinguishedName
					}
				} else {
					$AttributeValue
				}
			}
			default {
				$AttributeValue
			}
		}
	} else {
		## If $AttributeValue is null, return an emptry string to prevent any references to the value from failing
		''
	}
}