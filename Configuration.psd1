@{
	Defaults = @{
		FieldMatchIds = @(
			@{ AD = 'samAccountName'; CSV = 'AD_LOGON' }
			@{ AD = 'EmployeeId'; CSV = 'PERSON_NUM' }
		)
		InputCsvFilePath = 'C:\Dropbox\GitRepos\CaviumScripts\WorkdayADSync\copy.csv'
		Credential = $null
		DomainController = $null
	}
	FieldMap = @{
		# GivenName = 'FIRST_NAME'
		# Surname = 'LAST_NAME'
		# DisplayName = 'FULL_NAME'
		# Title = 'TITLE'
		# Department = 'DEPARTMENT'
		# EmailAddress = 'EMAIL_ADDRESS'
		# OfficePhone = 'OFFICE_NUMBER'
		# MobilePhone = 'MOBILE_PHONE'
		EmployeeId = 'PERSON_NUM'
	}
}
