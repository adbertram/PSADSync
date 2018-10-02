@{
	CompanyName     = 'YourCompany'
	Email           = @{
		SMTPServer = 'yoursmtpserver.company.local'
		Templates  = @{
			UnusedAccount = @{
				Subject          = 'unusedaccountsubject'
				FromEmailAddress = 'unusedaccountfromemail@company.local'
				FromEmailName    = 'unusedaccountfromname'
			}
		}
	}
	## Use this if, in the CSV, there is a certain column like Status that defines if a user has
	## been terminated or not. This allows you to then either disable the account or move to another OU
	## for archival purposes.
	UserTermination = @{
		Enabled            = $false
		Criteria           = 'FieldValue' ## This can be FieldValue which looks for a specific set of values in a field to designate a "termed" employee
		FieldValueSettings = @{
			CsvField = 'Status'
			CsvValue = '0', '2'
		}
		## This will leave the account where it is and just disable it. This can be Disable or Custom. If Custom, user MUST
		## provide a UserTeminationAction scriptblock to Invoke-AdSync representing the code to execute when a user
		## needs to be terminated.
		Action             = 'Disable'
	}
	NewUserCreation = @{
		Enabled = $true
		## Available options are FirstInitialLastName,FirstNameLastName,FirstNameDotLastName,LastNameFirstTwoFirstNameChars
		AccountNamePattern = 'FirstInitialLastName' 
		Path               = ''
		## PSADSync will automatically exclude creating new users that match any user 
		## termination values. If the user would like to exclude any other employees for some reason
		## add the field name and value(s) here.
		Exclude            = @{ 
			FieldValueSettings = @{
				CsvField = $null
				CsvValue = $null
			}
		}
	}
}
