param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot "..\runtime\from_model")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$validator = Join-Path $PSScriptRoot "validate_model_output.ps1"
$converter = Join-Path $PSScriptRoot "convert_model_output_to_crm.ps1"
$modelDir = Join-Path $PSScriptRoot "..\runtime\llm_outputs"
$sampleDir = Join-Path $PSScriptRoot "..\assets\samples"

$modelFiles = @(Get-ChildItem -LiteralPath $modelDir -Filter "model_output.json" -Recurse | Sort-Object FullName)
if ($modelFiles.Count -eq 0) {
    throw "No model_output.json files found under $modelDir"
}

foreach ($modelFile in $modelFiles) {
    $sampleName = Split-Path -Leaf (Split-Path -Parent $modelFile.FullName)
    $contextPath = Join-Path $sampleDir ("{0}_context.json" -f $sampleName)
    $outDir = Join-Path $OutputRoot $sampleName

    & $validator -ModelOutputPath $modelFile.FullName | Out-Null

    if (Test-Path -LiteralPath $contextPath) {
        & $converter -ModelOutputPath $modelFile.FullName -ContextPath $contextPath -OutputDir $outDir | Out-Null
    }
    else {
        & $converter -ModelOutputPath $modelFile.FullName -OutputDir $outDir | Out-Null
    }

    $packet = Read-JsonFile -Path (Join-Path $outDir "crm_packet.json")
    if ($null -eq $packet.feishu_bitable_payload.customer_table) {
        throw "customer_table missing in $sampleName"
    }
    if ($null -eq $packet.feishu_bitable_payload.opportunity_snapshot_table) {
        throw "opportunity_snapshot_table missing in $sampleName"
    }

    Write-Host "[PASS] $sampleName"
}

Write-Host "All model output tests passed. Output root: $OutputRoot"
