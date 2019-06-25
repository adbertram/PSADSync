function ReadEmailTemplate {
	[OutputType('string')]
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Name	
	)
	
	$parentFolder = $PSScriptRoot | Split-Path -Parent
	if ($template = Get-ChildItem -Path (Join-Path -Path $parentFolder -ChildPath 'EmailTemplates') -Filter "$Name.txt") {
		Get-Content -Path $template.FullName -Raw
	}
}