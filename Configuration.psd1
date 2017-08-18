@{
	CompanyName = 'YourCompany'
	Email = @{
		SMTPServer = 'yoursmtpserver.company.local'
		Templates = @{
			UnusedAccount = @{
				Subject = 'unusedaccountsubject'
				FromEmailAddress = 'unusedaccountfromemail@company.local'
				FromEmailName = 'unusedaccountfromname'
			}
		}
	}
	## Use this if, in the CSV, there is a certain column like Status that defines if a user has
	## been terminated or not. This allows you to then either disable the account or move to another OU
	## for archival purposes.
	UserTermination = @{
		Enabled = $true
		Criteria = 'FieldValue' ## This can be FieldValue or UserDoesNotExist
		FieldValueSettings = @{
			CsvField = 'Status'
			CsvValue = 'Withdrawn'
		}
		Action = 'Disable' ## This will leave the account where it is and just disable it
	}
	NewUserCreation = @{
		AccountNamePattern = 'FirstInitialLastName' ## Available options are FirstInitialLastName,FirstNameLastName,FirstNameDotLastName,LastNameFirstTwoFirstNameChars
	}
}