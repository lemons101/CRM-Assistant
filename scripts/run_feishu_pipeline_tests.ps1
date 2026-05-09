param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot "..\\runtime\\feishu_pipeline")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$rawDir = Join-Path $PSScriptRoot "..\\assets\\feishu_raw"
$expectedDir = Join-Path $PSScriptRoot "..\\assets\\expected"
$builder = Join-Path $PSScriptRoot "build_context_from_feishu.ps1"
$processor = Join-Path $PSScriptRoot "process_transcript.ps1"

$rawFiles = Get-ChildItem -LiteralPath $rawDir -Filter "*.json" | Sort-Object Name
if ($rawFiles.Count -eq 0) {
    throw "No Feishu raw sample files found in $rawDir"
}

$failures = 0

foreach ($rawFile in $rawFiles) {
    $sampleName = $rawFile.BaseName
    $expectedPath = Join-Path $expectedDir ("{0}.json" -f $sampleName)
    if (-not (Test-Path -LiteralPath $expectedPath)) {
        throw "Missing expected assertion file for Feishu sample $sampleName"
    }

    $sampleOutput = Join-Path $OutputRoot $sampleName
    $buildOutput = Join-Path $sampleOutput "build"
    $processOutput = Join-Path $sampleOutput "process"

    & $builder -RawInputPath $rawFile.FullName -OutputDir $buildOutput | Out-Null
    & $processor `
        -TranscriptPath (Join-Path $buildOutput "transcript.txt") `
        -ContextPath (Join-Path $buildOutput "context.json") `
        -OutputDir $processOutput | Out-Null

    $packet = Read-JsonFile -Path (Join-Path $processOutput "crm_packet.json")
    $expected = Read-JsonFile -Path $expectedPath
    $errors = New-Object System.Collections.Generic.List[string]

    if ($packet.opportunity_update.intent_level -ne $expected.intent_level) {
        $errors.Add("intent_level expected [$($expected.intent_level)] actual [$($packet.opportunity_update.intent_level)]")
    }
    if ([int]$packet.opportunity_update.lead_score -lt [int]$expected.min_lead_score) {
        $errors.Add("lead_score expected >= $($expected.min_lead_score) actual [$($packet.opportunity_update.lead_score)]")
    }
    if ($packet.opportunity_update.opportunity_stage -ne $expected.opportunity_stage) {
        $errors.Add("opportunity_stage expected [$($expected.opportunity_stage)] actual [$($packet.opportunity_update.opportunity_stage)]")
    }

    if ($errors.Count -eq 0) {
        Write-Host "[PASS] $sampleName"
    }
    else {
        $failures += 1
        Write-Host "[FAIL] $sampleName"
        foreach ($err in $errors) {
            Write-Host "  - $err"
        }
    }
}

if ($failures -gt 0) {
    throw "$failures Feishu pipeline test(s) failed."
}

Write-Host "All Feishu pipeline tests passed. Output root: $OutputRoot"

