$ProjectRoot = $ENV:APPVEYOR_BUILD_FOLDER

$testResultsFilePath = "$ProjectRoot\TestResults.xml"

Invoke-Pester -Path "$ProjectRoot\New-PSADSync.Tests.ps1" -OutputFormat NUnitXml -OutputFile $testResultsFilePath -EnableExit

$Address = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
(New-Object 'System.Net.WebClient').UploadFile( $Address, $testResultsFilePath )