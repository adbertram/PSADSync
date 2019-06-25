# .ExternalHelp PSADSync-Help.xml
function Get-AvailableAdUserAttribute {
	param()

	$schema =[DirectoryServices.ActiveDirectory.ActiveDirectorySchema]::GetCurrentSchema()
	$userClass = $schema.FindClass('user')
	
	foreach ($name in $userClass.GetAllProperties().Name | Sort-Object) {
		
		$output = [ordered]@{
			ValidName  = $name
			CommonName = $null
		}
		switch ($name) {
			'sn' {
				$output.CommonName = 'SurName'
			}
		}
		
		[pscustomobject]$output
	}
}