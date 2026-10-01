param (
    [string] $SopmPath  = (Join-Path $PSScriptRoot 'DynamicFieldFreetextList.sopm'),
    [string] $OutputDir = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SopmPath)) {
    Write-Error "SOPM file not found: $SopmPath"
    exit 1
}

[xml] $Sopm = Get-Content -Path $SopmPath -Encoding UTF8 -Raw

# Use XPath to avoid PowerShell confusing the version="" attribute on <otrs_package>
# with the <Version> child element
$PackageName    = $Sopm.SelectSingleNode('/otrs_package/Name').InnerText.Trim()
$PackageVersion = $Sopm.SelectSingleNode('/otrs_package/Version').InnerText.Trim()

Write-Host ("Building package: " + $PackageName + " v" + $PackageVersion) -ForegroundColor Cyan

$BaseDir = Split-Path $SopmPath -Parent
$OpmXml  = $Sopm.Clone()

foreach ($FileNode in $OpmXml.otrs_package.Filelist.File) {
    $RelativePath = $FileNode.Location
    $FullPath     = Join-Path $BaseDir $RelativePath

    if (-not (Test-Path $FullPath)) {
        Write-Warning ("  [MISSING] " + $RelativePath)
        continue
    }

    $Bytes = [System.IO.File]::ReadAllBytes($FullPath)

    # Normalise to Unix line endings (LF) for text files so that Perl can
    # parse heredoc terminators correctly on Linux OTOBO servers.
    $Ext = [System.IO.Path]::GetExtension($RelativePath).ToLower()
    if ($Ext -in @('.pm', '.pl', '.t', '.xml', '.tt', '.js', '.css')) {
        $Text  = [System.Text.Encoding]::UTF8.GetString($Bytes)
        $Text  = $Text -replace "`r`n", "`n"
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    }

    $Base64 = [System.Convert]::ToBase64String($Bytes)

    # Encode="Base64" is mandatory — without it OTOBO writes the raw base64
    # string to disk instead of decoding it.
    $FileNode.SetAttribute("Encode", "Base64")
    $FileNode.InnerText = $Base64

    $SizeKB = [Math]::Round($Bytes.Length / 1024, 1)
    Write-Host ("  [OK] " + $RelativePath + " (" + $SizeKB + " KB)") -ForegroundColor Green
}

if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

$OpmFileName = $PackageName + '-' + $PackageVersion + '.opm'
$OpmFilePath = Join-Path $OutputDir $OpmFileName

# Remove old opm if it exists
if (Test-Path $OpmFilePath) { Remove-Item $OpmFilePath }

$Settings = New-Object System.Xml.XmlWriterSettings
$Settings.Indent             = $true
$Settings.IndentChars        = '    '
$Settings.Encoding           = New-Object System.Text.UTF8Encoding($false)
$Settings.OmitXmlDeclaration = $false

$Writer = [System.Xml.XmlWriter]::Create($OpmFilePath, $Settings)
try {
    $OpmXml.WriteTo($Writer)
} finally {
    $Writer.Flush()
    $Writer.Close()
}

$FinalSize = [Math]::Round((Get-Item $OpmFilePath).Length / 1024, 1)
Write-Host ''
Write-Host ("Package written: " + $OpmFilePath + " (" + $FinalSize + " KB)") -ForegroundColor Yellow
Write-Host ''
Write-Host 'Installation in OTOBO:' -ForegroundColor Cyan
Write-Host ('  Admin > Package Manager > Install Package > Browse... > ' + $OpmFileName)