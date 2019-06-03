Import-Module -Name 'ImportExcel' -ErrorAction 'Stop'

$ProgressPreference = 'SilentlyContinue'
$moduleName = 'AWSPowerShell'

Write-Host ('Processing {0}:' -f $moduleName) -ForegroundColor Green
$modules = (Find-Module -Name $moduleName -AllVersions -Repository 'PSGallery') | Sort-Object -Property Version
$cmdletStatistics = foreach ($module in $modules)
{
    Write-Host ('  - {0}' -f $module.Version.ToString()) -ForegroundColor Green
    Save-Module -Name $module.Name -RequiredVersion $module.Version -Path ([IO.Path]::GetTempPath()) -Repository 'PSGallery'
    $tempDirectory = [IO.Path]::Combine([IO.Path]::GetTempPath(), $moduleName, $module.Version.ToString())
    $moduleManifest = (Get-ChildItem -Path $tempDirectory -Recurse -File | Where-Object {$_.Name -eq ('{0}.psd1' -f $module.Name)}).FullName
    $cmdletCount = & powershell.exe -NoProfile -NoLogo -NonInteractive -Command "Import-Module '$moduleManifest'; (Get-Command -Module $moduleName).Count"

    [PSCustomObject]@{
        Name = $moduleName
        Version = $module.Version.ToString()
        PublishedDate = $module.PublishedDate
        CmdletCount = $cmdletCount
    }
}

$outputFile = "$env:HOME\AWSPowerShellStatistics.xlsx"
$cmdletStatistics | Select-Object -Property PublishedDate,CmdletCount | Sort-Object -Property PublishedDate | Export-Excel $outputFile -Show -AutoNameRange -LineChart -NoLegend
