function SetAdUser {
	[OutputType([void])]
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Identity,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[hashtable]$ActiveDirectoryAttributes
	)	

	$replaceHt = @{ }
	foreach ($attrib in $ActiveDirectoryAttributes.GetEnumerator()) {
		$attribName = $attrib.Key
		$convertParams = @{
			AttributeName  = $attrib.Key
			AttributeValue = $attrib.Value
			Action         = 'Set'
		}
		$replaceHt.$attribName = (ConvertToSchemaAttributeType @convertParams)
	}

	$setParams = @{
		Identity = $Identity
		Replace  = $replaceHt
		Confirm  = $false
	}
		
	if ($PSCmdlet.ShouldProcess("User: [$($Identity)] AD attribs: [$($replaceHt.Keys -join ',')] to [$($ActiveDirectoryAttributes.Values -join ',')]", 'Set AD attributes')) {
		Write-Verbose -Message "Replacing AD attribs: [$($setParams.Replace | Out-String)]"
		Set-AdUser @setParams
	} 
}