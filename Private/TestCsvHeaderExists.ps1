function TestCsvHeaderExists {
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$CsvFilePath,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[object[]]$Header,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$ParseScriptBlockHeaders
	)

	$csvHeaders = GetCsvColumnHeaders -CsvFilePath $CsvFilePath

	## Parse out the CSV headers used if the field is a scriptblock
	$commonHeaders = @($Header).foreach({
			$_ | ForEach-Object {
				if ($_ -is 'scriptblock') {
					## It's extremely hard to figure out what values inside of the scriptblock are actual CSV headers
					## Give the option here.
					if ($ParseScriptBlockHeaders.IsPresent) {
						ParseScriptBlockHeaders -FieldScriptBlock $_
					}
				} else {
					$_
				}
			}
		})

	## Assuming that ParseScriptBlockHeaders was not used and all of the headers
	## are scriptblocks. We check nothing but still return true.
	if (-not ($commonHeaders = $commonHeaders | Select-Object -Unique)) {
		$true
	} else {
		$matchedHeaders = $csvHeaders | Where-Object { $_ -in $commonHeaders }
		if (@($matchedHeaders).Count -ne @($commonHeaders).Count) {
			$false
		} else {
			$true
		}
	}
}