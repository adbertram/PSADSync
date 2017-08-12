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
}