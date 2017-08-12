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
	UserTerminationTest = @{
		Enabled = $true
		CsvField = 'Status'
		CsvValue = 'Withdrawn'
	}
}