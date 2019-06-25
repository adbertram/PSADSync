function Get-CompanyCsvUser {
	[OutputType([pscustomobject])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
		[string]$CsvFilePath,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[hashtable]$Exclude,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateSet('Comma', 'Tab')]
		[string]$Delimiter = 'Comma'
	)
	begin {
		$ErrorActionPreference = 'Stop'
		Write-Verbose -Message "Enumerating all users in CSV file [$($CsvFilePath)]"
	}
	process {
		try {
			$whereFilter = { '*' }
			if ($PSBoundParameters.ContainsKey('Exclude')) {
				$conditions = $Exclude.GetEnumerator() | ForEach-Object { "(`$_.'$($_.Key)' -ne '$($_.Value)')" }
				$whereFilter = [scriptblock]::Create($conditions -join ' -and ')
			}

			$importCsvParams = @{
				Path = $CsvFilePath
			}
			if ($Delimiter -eq 'Comma') {
				$importCsvParams.Delimiter = ','
			} elseif ($Delimiter -eq 'Tab') {
				$importCsvParams.Delimiter = "`t"
			}

			Import-Csv @importCsvParams | Where-Object -FilterScript $whereFilter
		} catch {
			Write-Error -Message "Function: $($MyInvocation.MyCommand.Name) Error: $($_.Exception.Message)"
		}
	}
}