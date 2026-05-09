param(
    [Parameter(Mandatory = $true)]
    [string]$RawInputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string]$ContextFileName = "context.json",

    [string]$TranscriptFileName = "transcript.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ObjectValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-TranscriptText {
    param([object]$Raw)

    if ($null -ne $Raw.transcript.full_text -and $Raw.transcript.full_text.ToString().Trim() -ne "") {
        return $Raw.transcript.full_text.ToString().Trim()
    }

    if ($null -ne $Raw.transcript.segments) {
        $lines = @()
        foreach ($segment in $Raw.transcript.segments) {
            $speaker = if ($null -ne $segment.speaker -and $segment.speaker.ToString().Trim() -ne "") {
                $segment.speaker.ToString().Trim()
            }
            else {
                "发言人"
            }

            $text = if ($null -ne $segment.text) { $segment.text.ToString().Trim() } else { "" }
            if ($text -ne "") {
                $lines += ("{0}：{1}" -f $speaker, $text)
            }
        }

        if ($lines.Count -gt 0) {
            return ($lines -join [Environment]::NewLine)
        }
    }

    throw "No transcript.full_text or transcript.segments found in raw input."
}

function Get-FirstParticipantByRole {
    param(
        [object[]]$Participants,
        [string[]]$Roles
    )

    foreach ($participant in $Participants) {
        foreach ($role in $Roles) {
            if ($participant.role -eq $role) {
                return $participant
            }
        }
    }
    return $null
}

$raw = Read-JsonFile -Path $RawInputPath

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$participants = @($raw.participants)
$crmBinding = $raw.crm_binding
$externalParticipant = Get-FirstParticipantByRole -Participants $participants -Roles @("external", "guest", "customer")
$internalParticipant = Get-FirstParticipantByRole -Participants $participants -Roles @("internal", "host", "owner")

$transcriptText = Get-TranscriptText -Raw $raw

$context = [ordered]@{
    customer_id        = Get-ObjectValue -Object $crmBinding -PropertyName "customer_id"
    customer_name      = if ($null -ne (Get-ObjectValue -Object $crmBinding -PropertyName "customer_name")) {
        Get-ObjectValue -Object $crmBinding -PropertyName "customer_name"
    }
    elseif ($null -ne $externalParticipant) {
        $externalParticipant.name
    }
    else {
        $null
    }
    company_name       = if ($null -ne (Get-ObjectValue -Object $crmBinding -PropertyName "company_name")) {
        Get-ObjectValue -Object $crmBinding -PropertyName "company_name"
    }
    elseif ($null -ne $externalParticipant.company) {
        $externalParticipant.company
    }
    else {
        $null
    }
    owner              = if ($null -ne (Get-ObjectValue -Object $crmBinding -PropertyName "owner")) {
        Get-ObjectValue -Object $crmBinding -PropertyName "owner"
    }
    elseif ($null -ne $internalParticipant) {
        $internalParticipant.name
    }
    else {
        $null
    }
    industry           = if ($null -ne (Get-ObjectValue -Object $crmBinding -PropertyName "industry")) {
        Get-ObjectValue -Object $crmBinding -PropertyName "industry"
    }
    elseif ($null -ne $externalParticipant.industry) {
        $externalParticipant.industry
    }
    else {
        $null
    }
    opportunity_id     = Get-ObjectValue -Object $crmBinding -PropertyName "opportunity_id"
    current_stage      = Get-ObjectValue -Object $crmBinding -PropertyName "current_stage" -Default "未知"
    sales_region       = Get-ObjectValue -Object $crmBinding -PropertyName "sales_region"
    meeting_time       = if ($null -ne $raw.meeting.start_time) { $raw.meeting.start_time } else { $null }
    next_meeting_time  = if ($null -ne $raw.calendar.next_meeting_time) { $raw.calendar.next_meeting_time } else { $null }
    channel            = "飞书会议纪要导入"
    source_meeting_id  = if ($null -ne $raw.meeting.meeting_id) { $raw.meeting.meeting_id } else { $null }
    source_event_id    = if ($null -ne $raw.meeting.calendar_event_id) { $raw.meeting.calendar_event_id } else { $null }
    source_title       = if ($null -ne $raw.meeting.title) { $raw.meeting.title } else { $null }
}

$contextPath = Join-Path $OutputDir $ContextFileName
$transcriptPath = Join-Path $OutputDir $TranscriptFileName

Write-JsonFile -Path $contextPath -Value $context
Set-Content -LiteralPath $transcriptPath -Value $transcriptText -Encoding UTF8

$result = [ordered]@{
    raw_input_path    = (Resolve-Path -LiteralPath $RawInputPath).Path
    generated_context = (Resolve-Path -LiteralPath $contextPath).Path
    generated_transcript = (Resolve-Path -LiteralPath $transcriptPath).Path
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDir "build_result.json") -Encoding UTF8

Write-Host "Feishu raw input converted at: $OutputDir"



