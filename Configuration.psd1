@{
	Defaults = @{
		FieldMatchIds = @(
			@{ AD = 'EmployeeId'; CSV = 'PERSON_NUM' }
			@{ AD = 'samAccountName'; CSV = 'AD_LOGON' }
		)
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
