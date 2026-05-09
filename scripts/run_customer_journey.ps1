param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$manifest = Read-JsonFile -Path $ManifestPath
$skillRoot = Split-Path -Parent $PSScriptRoot
$processor = Join-Path $PSScriptRoot "process_transcript.ps1"

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$rounds = @()

foreach ($item in $manifest.rounds) {
    $roundName = $item.round_id
    $contextPath = Join-Path $skillRoot $item.context_path
    $transcriptPath = Join-Path $skillRoot $item.transcript_path
    $roundOutput = Join-Path $OutputDir $roundName

    & $processor -TranscriptPath $transcriptPath -ContextPath $contextPath -OutputDir $roundOutput | Out-Null

    $packet = Read-JsonFile -Path (Join-Path $roundOutput "crm_packet.json")

    $rounds += [pscustomobject]@{
        round_id            = $roundName
        label               = $item.label
        meeting_time        = $packet.meeting.meeting_time
        lead_score          = $packet.opportunity_update.lead_score
        intent_level        = $packet.opportunity_update.intent_level
        opportunity_stage   = $packet.opportunity_update.opportunity_stage
        high_value_flag     = $packet.opportunity_update.high_value_flag
        recommended_action  = $packet.opportunity_update.recommended_action
        summary             = $packet.meeting.summary
        next_follow_up_at   = $packet.opportunity_update.next_follow_up_at
    }
}

$sortedRounds = @($rounds | Sort-Object { [datetimeoffset]$_.meeting_time })
$stagePath = @($sortedRounds | ForEach-Object { $_.opportunity_stage })

$progressionNotes = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $sortedRounds.Count; $i++) {
    $current = $sortedRounds[$i]
    if ($i -eq 0) {
        $progressionNotes.Add(("第1轮为{0}，阶段：{1}，Lead Score {2}" -f $current.label, $current.opportunity_stage, $current.lead_score))
        continue
    }

    $previous = $sortedRounds[$i - 1]
    $delta = [int]$current.lead_score - [int]$previous.lead_score
    $direction = if ($delta -gt 0) { "提升" } elseif ($delta -lt 0) { "下降" } else { "持平" }
    $deltaText = if ($delta -ne 0) { " $delta" } else { "" }

    $progressionNotes.Add((
        "{0} 从 {1} -> {2}，Lead Score {3}（{4}{5}）" -f
        $current.label,
        $previous.opportunity_stage,
        $current.opportunity_stage,
        $current.lead_score,
        $direction,
        $deltaText
    ))
}

$journey = [ordered]@{
    customer_id        = $manifest.customer_id
    customer_name      = $manifest.customer_name
    opportunity_id     = $manifest.opportunity_id
    total_rounds       = $sortedRounds.Count
    journey_theme      = $manifest.journey_theme
    stage_path         = $stagePath
    latest_stage       = $sortedRounds[-1].opportunity_stage
    latest_lead_score  = $sortedRounds[-1].lead_score
    latest_intent      = $sortedRounds[-1].intent_level
    progression_notes  = @($progressionNotes)
    rounds             = @($sortedRounds)
}

$journey | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDir "journey_summary.json") -Encoding UTF8

Write-Host "Customer journey generated at: $OutputDir"


