function ParseScriptBlockHeaders {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[scriptblock[]]$FieldScriptBlock
	)
	
	$headers = @($FieldScriptBlock).foreach({
			$ast = [System.Management.Automation.Language.Parser]::ParseInput($_.ToString(), [ref]$null, [ref]$null)
			$ast.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value
		})
	$headers | Select-Object -Unique
	
}