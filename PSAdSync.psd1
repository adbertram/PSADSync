@{
	RootModule        = 'PSADSync.psm1'
	ModuleVersion     = '*'
	GUID              = 'ea8b8286-a4ae-4c52-822e-3a6dc264859e'
	Author            = 'Adam Bertram'
	CompanyName       = 'Adam the Automator, LLC'
	Copyright         = '(c) 2017 Adam Bertram. All rights reserved.'
	Description       = 'This module expedites the process of syncing a CSV file full of employees with Active Directory.'
	PowerShellVersion = '5.0'
	FunctionsToExport = '*'
	ScriptsToProcess  = 'ActiveDirectory\InstallActiveDirectoryModule.ps1'
	CmdletsToExport   = '*'
	VariablesToExport = '*'
	AliasesToExport   = '*'
	PrivateData       = @{
		PSData = @{
			Tags       = @('PSModule', 'ActiveDirectory')
			ProjectUri = 'https://github.com/adbertram/PSADSync'
		}
	}
}
