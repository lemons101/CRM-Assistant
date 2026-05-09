param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot "..\\runtime")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$sampleDir = Join-Path $PSScriptRoot "..\\assets\\samples"
$expectedDir = Join-Path $PSScriptRoot "..\\assets\\expected"
$processor = Join-Path $PSScriptRoot "process_transcript.ps1"

$contextFiles = Get-ChildItem -LiteralPath $sampleDir -Filter "*_context.json" | Sort-Object Name
if ($contextFiles.Count -eq 0) {
    throw "No sample contexts found in $sampleDir"
}

$failures = 0

foreach ($contextFile in $contextFiles) {
    $sampleName = $contextFile.BaseName -replace "_context$", ""
    $transcriptPath = Join-Path $sampleDir ("{0}_transcript.txt" -f $sampleName)
    $expectedPath = Join-Path $expectedDir ("{0}.json" -f $sampleName)
    $outDir = Join-Path $OutputRoot $sampleName

    if (-not (Test-Path -LiteralPath $transcriptPath)) {
        throw "Missing transcript for sample $sampleName"
    }
    if (-not (Test-Path -LiteralPath $expectedPath)) {
        throw "Missing expected assertion file for sample $sampleName"
    }

    & $processor -TranscriptPath $transcriptPath -ContextPath $contextFile.FullName -OutputDir $outDir | Out-Null

    $packet = Read-JsonFile -Path (Join-Path $outDir "crm_packet.json")
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

    if ([bool]$packet.opportunity_update.high_value_flag -ne [bool]$expected.high_value_flag) {
        $errors.Add("high_value_flag expected [$($expected.high_value_flag)] actual [$($packet.opportunity_update.high_value_flag)]")
    }

    $allTags = @(
        $packet.customer_profile_update.family_status +
        $packet.customer_profile_update.business_preferences +
        $packet.customer_profile_update.risk_concerns +
        $packet.customer_profile_update.communication_style +
        $packet.customer_profile_update.decision_signals +
        $packet.customer_profile_update.recent_interest_points
    ) | Select-Object -Unique

    foreach ($tag in $expected.required_tags) {
        if (-not ($allTags -contains $tag)) {
            $errors.Add("missing required tag [$tag]")
        }
    }

    if ($expected.required_channel -and $packet.follow_up_task.channel -ne $expected.required_channel) {
        $errors.Add("required_channel expected [$($expected.required_channel)] actual [$($packet.follow_up_task.channel)]")
    }

    foreach ($snippet in $expected.summary_must_include) {
        if ($packet.meeting.summary -notlike "*$snippet*") {
            $errors.Add("summary missing snippet [$snippet]")
        }
    }

    $hasBrief = $null -ne $packet.pre_meeting_brief.next_meeting_at -and $packet.pre_meeting_brief.next_meeting_at -ne ""
    if ([bool]$expected.pre_meeting_should_exist -ne [bool]$hasBrief) {
        $errors.Add("pre_meeting existence expected [$($expected.pre_meeting_should_exist)] actual [$hasBrief]")
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
    throw "$failures sample test(s) failed."
}

Write-Host "All sample tests passed. Output root: $OutputRoot"

