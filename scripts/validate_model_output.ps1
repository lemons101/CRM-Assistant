param(
    [Parameter(Mandatory = $true)]
    [string]$ModelOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-HasProperty {
    param(
        [object]$Object,
        [string]$PropertyName,
        [string]$Scope
    )

    if ($null -eq $Object) {
        throw "Missing object [$Scope] in model output."
    }

    if ($null -eq $Object.PSObject.Properties[$PropertyName]) {
        throw "Missing property [$Scope.$PropertyName] in model output."
    }
}

function Test-DateValue {
    param(
        [string]$Value,
        [string]$FieldName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    try {
        [datetimeoffset]::Parse($Value) | Out-Null
    }
    catch {
        throw "Invalid datetime in [$FieldName]: $Value"
    }
}

$model = Read-JsonFile -Path $ModelOutputPath

foreach ($topLevel in @("meeting", "customer_profile_update", "opportunity_update", "follow_up_task", "pre_meeting_brief")) {
    Assert-HasProperty -Object $model -PropertyName $topLevel -Scope "root"
}

foreach ($field in @("customer_id", "customer_name", "company_name", "meeting_time", "summary")) {
    Assert-HasProperty -Object $model.meeting -PropertyName $field -Scope "meeting"
}

foreach ($field in @("customer_id", "company_name", "industry", "profile_summary")) {
    Assert-HasProperty -Object $model.customer_profile_update -PropertyName $field -Scope "customer_profile_update"
}

foreach ($field in @("opportunity_id", "opportunity_name", "opportunity_description", "sales_region", "business_value", "lead_score", "intent_level", "opportunity_stage", "high_value_flag", "recommended_action", "latest_progress")) {
    Assert-HasProperty -Object $model.opportunity_update -PropertyName $field -Scope "opportunity_update"
}

foreach ($field in @("task_title", "owner", "channel", "draft_message", "checklist")) {
    Assert-HasProperty -Object $model.follow_up_task -PropertyName $field -Scope "follow_up_task"
}

foreach ($field in @("headline", "opening_script", "key_points", "watchouts", "materials_to_prepare")) {
    Assert-HasProperty -Object $model.pre_meeting_brief -PropertyName $field -Scope "pre_meeting_brief"
}

$validIntentLevels = @("low", "medium", "high")
if ($validIntentLevels -notcontains $model.opportunity_update.intent_level) {
    throw "Invalid opportunity_update.intent_level: $($model.opportunity_update.intent_level)"
}

$validStages = @("初次接触", "需求确认", "方案沟通", "推进中", "待成交")
if ($validStages -notcontains $model.opportunity_update.opportunity_stage) {
    throw "Invalid opportunity_update.opportunity_stage: $($model.opportunity_update.opportunity_stage)"
}

$validChannels = @("微信", "邮件", "飞书消息")
if (-not [string]::IsNullOrWhiteSpace($model.follow_up_task.channel) -and $validChannels -notcontains $model.follow_up_task.channel) {
    throw "Invalid follow_up_task.channel: $($model.follow_up_task.channel)"
}

if ([int]$model.opportunity_update.lead_score -lt 0 -or [int]$model.opportunity_update.lead_score -gt 100) {
    throw "lead_score must be between 0 and 100."
}

Test-DateValue -Value $model.meeting.meeting_time -FieldName "meeting.meeting_time"
Test-DateValue -Value $model.opportunity_update.next_follow_up_at -FieldName "opportunity_update.next_follow_up_at"
Test-DateValue -Value $model.follow_up_task.due_at -FieldName "follow_up_task.due_at"
Test-DateValue -Value $model.pre_meeting_brief.next_meeting_at -FieldName "pre_meeting_brief.next_meeting_at"
Test-DateValue -Value $model.pre_meeting_brief.trigger_at -FieldName "pre_meeting_brief.trigger_at"

Write-Host "Model output is valid: $ModelOutputPath"
