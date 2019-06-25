function ReadEmailTemplate {
	[OutputType('string')]
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Name	
	)
	
	if ($template = Get-ChildItem -Path "$PSScriptRoot\EmailTemplates" -Filter "$Name.txt") {
		Get-Content -Path $template.FullName -Raw
	}
}