function EvaluateFieldCondition {
	[OutputType('string')]
	[CmdletBinding(DefaultParameterSetName = 'CSVUser')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[scriptblock]$Condition,

		[Parameter(Mandatory, ParameterSetName = 'CSVUser')]
		[ValidateNotNullOrEmpty()]
		[pscustomobject]$CsvUser,

		[Parameter(Mandatory, ParameterSetName = 'ADUser')]
		[ValidateNotNullOrEmpty()]
		[object]$AdUser
	)

	if ($PSBoundParameters.ContainsKey('CsvUser')) {
		$replace = '$CsvUser'
	} elseif ($PSBoundParameters.ContainsKey('AdUser')) {
		$replace = 'ADUser'
	}
	
	$fieldScript = $Condition.ToString() -replace '\$_', $replace
	& ([scriptblock]::Create($fieldScript))
	
}