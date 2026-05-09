param(
    [Parameter(Mandatory = $true)]
    [string]$ModelOutputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string]$ContextPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Join-Values {
    param(
        [object[]]$Values,
        [string]$Fallback = "暂无"
    )

    if ($null -eq $Values) {
        return $Fallback
    }

    $items = @($Values | Where-Object { $_ -and $_.ToString().Trim() -ne "" } | Select-Object -Unique)
    if ($items.Count -eq 0) {
        return $Fallback
    }

    return ($items -join "；")
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

$validator = Join-Path $PSScriptRoot "validate_model_output.ps1"
& $validator -ModelOutputPath $ModelOutputPath | Out-Null

$model = Read-JsonFile -Path $ModelOutputPath
$context = if ($ContextPath -and (Test-Path -LiteralPath $ContextPath)) { Read-JsonFile -Path $ContextPath } else { $null }
$sourceChannel = Get-ObjectValue -Object $context -PropertyName "channel" -Default "LLM 结构化输出"
$owner = Get-ObjectValue -Object $context -PropertyName "owner" -Default $model.follow_up_task.owner

$customerTableRow = [ordered]@{
    "客户ID"       = $model.customer_profile_update.customer_id
    "客户名称"     = $model.meeting.customer_name
    "客户公司"     = $model.customer_profile_update.company_name
    "行业"         = $model.customer_profile_update.industry
    "客户负责人"   = $owner
    "家庭标签"     = Join-Values -Values $model.customer_profile_update.family_status
    "家庭备注"     = Join-Values -Values $model.customer_profile_update.family_notes
    "商业偏好"     = Join-Values -Values $model.customer_profile_update.business_preferences
    "风险顾虑"     = Join-Values -Values $model.customer_profile_update.risk_concerns
    "沟通风格"     = Join-Values -Values $model.customer_profile_update.communication_style
    "决策信号"     = Join-Values -Values $model.customer_profile_update.decision_signals
    "最近关注点"   = Join-Values -Values $model.customer_profile_update.recent_interest_points
    "客户画像摘要" = $model.customer_profile_update.profile_summary
    "最后更新时间" = $model.meeting.meeting_time
    "数据来源"     = $sourceChannel
}

$opportunitySnapshotRow = [ordered]@{
    "商机ID"       = $model.opportunity_update.opportunity_id
    "客户ID"       = $model.meeting.customer_id
    "客户名称"     = $model.meeting.customer_name
    "客户公司"     = $model.meeting.company_name
    "机会名称"     = $model.opportunity_update.opportunity_name
    "商机描述"     = $model.opportunity_update.opportunity_description
    "当前阶段"     = $model.opportunity_update.opportunity_stage
    "Lead Score"   = $model.opportunity_update.lead_score
    "意向等级"     = $model.opportunity_update.intent_level
    "高净值优先"   = $model.opportunity_update.high_value_flag
    "销售区域"     = $model.opportunity_update.sales_region
    "业务价值"     = $model.opportunity_update.business_value
    "推荐动作"     = $model.opportunity_update.recommended_action
    "最新进展"     = $model.opportunity_update.latest_progress
    "下次跟进时间" = $model.opportunity_update.next_follow_up_at
    "最近会议时间" = $model.meeting.meeting_time
    "商机负责人"   = $owner
    "数据来源"     = $sourceChannel
}

$crmPacket = [ordered]@{
    input = [ordered]@{
        model_output_path = (Resolve-Path -LiteralPath $ModelOutputPath).Path
        context_path      = if ($ContextPath -and (Test-Path -LiteralPath $ContextPath)) { (Resolve-Path -LiteralPath $ContextPath).Path } else { $null }
    }
    meeting                  = $model.meeting
    customer_profile_update  = $model.customer_profile_update
    opportunity_update       = $model.opportunity_update
    follow_up_task           = $model.follow_up_task
    pre_meeting_brief        = $model.pre_meeting_brief
    customer_table_row       = $customerTableRow
    opportunity_snapshot_row = $opportunitySnapshotRow
    feishu_bitable_payload   = [ordered]@{
        customer_table = [ordered]@{
            mode          = "upsert"
            key_field     = "客户ID"
            key           = $model.customer_profile_update.customer_id
            update_fields = $customerTableRow
        }
        opportunity_snapshot_table = [ordered]@{
            mode       = "append"
            append_row = $opportunitySnapshotRow
        }
    }
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

Write-JsonFile -Path (Join-Path $OutputDir "meeting_record.json") -Value $model.meeting
Write-JsonFile -Path (Join-Path $OutputDir "customer_profile_update.json") -Value $model.customer_profile_update
Write-JsonFile -Path (Join-Path $OutputDir "opportunity_update.json") -Value $model.opportunity_update
Write-JsonFile -Path (Join-Path $OutputDir "follow_up_task.json") -Value $model.follow_up_task
Write-JsonFile -Path (Join-Path $OutputDir "pre_meeting_brief.json") -Value $model.pre_meeting_brief
Write-JsonFile -Path (Join-Path $OutputDir "customer_table_row.json") -Value $customerTableRow
Write-JsonFile -Path (Join-Path $OutputDir "opportunity_snapshot_row.json") -Value $opportunitySnapshotRow
Write-JsonFile -Path (Join-Path $OutputDir "crm_packet.json") -Value $crmPacket

Write-Host "Converted model output to CRM artifacts at: $OutputDir"
