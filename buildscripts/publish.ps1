$ErrorActionPreference = 'Stop'

try
{
    ## Don't upload the build scripts and appveyor.yml to PowerShell Gallery
    $moduleFolderPath = "$env:APPVEYOR_BUILD_FOLDER\PSADSync"
    $null = mkdir $moduleFolderPath
    $excludeFromPublish = @(
        'PSADSync\\buildscripts'
        'PSADSync\\appveyor\.yml'
        'PSADSync\\\.git'
        'PSADSync\\README\.md'
    )
    $exclude = $excludeFromPublish -join '|'
    $packageContents = Get-ChildItem -Path $env:APPVEYOR_BUILD_FOLDER -Recurse | where { $_.FullName -notmatch $exclude } 
	$packageContents | Copy-Item -Destination {Join-Path -Path $moduleFolderPath -ChildPath $_.FullName.Substring($env:APPVEYOR_BUILD_FOLDER.length)}

    ## Publish module to PowerShell Gallery
    $publishParams = @{
        Path        = $moduleFolderPath
        NuGetApiKey = $env:nuget_apikey
        Repository  = 'PSGallery'
        Force       = $true
        Confirm     = $false
    }
    Publish-Module @publishParams

} catch
{
    Write-Error -Message $_.Exception.Message
    $host.SetShouldExit($LastExitCode)
}