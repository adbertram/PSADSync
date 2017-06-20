$parameters = @{
    CsvFilePath = 'C:\Scripts\Sync-WorkDayUser\prod\workerauditedit5.csv'
    Exclude = @{ 'AD_DOMAIN' = 'mvista.com' }
}
 
$parameters.FieldMatchMap = @{
    'PERSON_NUM' = 'employeeId'
}

$parameters.fieldSyncMap = @{
    { if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME' }} = 'givenName'
    'LAST_NAME' = 'sn'
    'MIDDLE_NAME' = 'middleName'
    'EMAIL_ADDRESS' = 'mail'
    'TITLE' = 'title'
    'DEPARTMENT' = 'department'
    'OFFICE_NUMBER' = 'telephonenumber'
    'MOBILE_NUMBER' = 'mobile'
    'PERSON_TYPE' = 'employeetype'
    'LOCATION' = 'physicalDeliveryOfficeName'
    'SUPERVISOR' = 'manager'
    'CONTRACT_END_DATE' = 'accountexpires'
}
 
$parameters.FieldValueMap = @{ 'SUPERVISOR' = { $supId = $_.'SUPERVISOR_ID'; (Get-AdUser -Filter "EmployeeId -eq '$supId'").DistinguishedName }}
 
Invoke-AdSync @parameters


$adUsers = Get-AdUser -Filter * -Properties *
import-csv -path "C:\Scripts\Sync-WorkDayUser\prod\WorkerAudit_20170614070212.csv" | where { $_.'AD_DOMAIN' -ne 'mvista.com' } | foreach { 
	$csvUser = $_; 
	if ($adUser = $adUsers | where { $_.EmployeeId -eq $csvUser.'PERSON_NUM'}) {
		$parameters.fieldSyncMap.getenumerator() | foreach { 
			if ($_.Value -eq 'givenName') { 
				if ($csvUser.'NICK_NAME') { 
					$csvField = 'NICK_NAME' 
				} else { 
					$csvField = 'FIRST_NAME' 
				}
			} else {
				$csvField = $_.Key
			}
			if ($csvUser.$csvField) {
				if ($csvField -eq 'SUPERVISOR') {
					$csvVal = (Get-AdUser -Filter "EmployeeId -eq '$($csvUser.'SUPERVISOR_ID')'").DistinguishedName
				} else {
					$csvVal = $csvUser.$csvField
				}
				$adVal = $aduser.($_.value)

				if ($csvField -eq 'CONTRACT_END_DATE' -and $csvVal -and $adVal) {
					$csvVal = [datetime]$csvVal
					$adVal = [datetime]$adval
				}

				if ($csvVal) {
					$output = [pscustomobject]@{
						'CSVField' = $csvField; 
						'ADField' = $adVal
						'CSVValue' = $csvVal
						'ADValue' = $adVal
					} 
					if ($output.ADValue -ne $output.CSVValue) { 
						write-host "ID: $($csvUser.'PERSON_NUM') | CSVfield: [$csvField] | CSV val: [$($output.CSVValue)] <> ADfield: [$($_.Value)] | AD val: [$($output.ADValue)]" -ForegroundColor Red 
					} else {
						#write-host "ID: $($csvUser.'PERSON_NUM') | CSV val: [$($output.CSVValue)] <> AD val: [$($output.ADValue)]" -ForegroundColor Green
					}
				}
			}
		}
	} else {
		Write-Host "No ID match found [$($csvUser.'PERSON_NUM')]" -ForegroundColor Magenta
	}
}