param(
    [Parameter(Mandatory = $true)]
    [string]$TranscriptPath,

    [Parameter(Mandatory = $true)]
    [string]$ContextPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-Lines {
    param([string]$Text)
    return @(
        $Text -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }
    )
}

function Get-MatchedLines {
    param(
        [string[]]$Lines,
        [string[]]$Patterns
    )

    $results = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        foreach ($pattern in $Patterns) {
            if ($line -match $pattern) {
                if (-not $results.Contains($line)) {
                    $results.Add($line)
                }
                break
            }
        }
    }
    return @($results)
}

function Get-Labels {
    param(
        [string]$Text,
        [hashtable]$Map
    )

    $labels = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Map.GetEnumerator()) {
        if ($Text -match $item.Value) {
            $labels.Add($item.Key)
        }
    }
    return @($labels | Select-Object -Unique)
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

function Parse-BudgetMax {
    param([string]$Text)

    $max = 0
    foreach ($match in [regex]::Matches($Text, '(\d+)\s*到\s*(\d+)\s*万')) {
        $candidate = [int]$match.Groups[2].Value
        if ($candidate -gt $max) { $max = $candidate }
    }

    foreach ($match in [regex]::Matches($Text, '(预算|金额超过)\D{0,8}(\d+)\s*万')) {
        $candidate = [int]$match.Groups[2].Value
        if ($candidate -gt $max) { $max = $candidate }
    }

    return $max
}

function Clamp-Score {
    param([int]$Value)
    if ($Value -lt 0) { return 0 }
    if ($Value -gt 100) { return 100 }
    return $Value
}

function Get-DateOrNull {
    param([object]$Value)
    if ($null -eq $Value -or $Value.ToString().Trim() -eq "") {
        return $null
    }
    return [datetimeoffset]::Parse($Value.ToString())
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
    if ($null -eq $property) {
        return $Default
    }

    if ($null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}

function Get-BusinessValue {
    param([string]$Text)

    foreach ($match in [regex]::Matches($Text, '预算大概在\s*(\d+)\s*到\s*(\d+)\s*万')) {
        return ("{0}-{1}万" -f $match.Groups[1].Value, $match.Groups[2].Value)
    }
    foreach ($match in [regex]::Matches($Text, '(\d+)\s*到\s*(\d+)\s*万')) {
        return ("{0}-{1}万" -f $match.Groups[1].Value, $match.Groups[2].Value)
    }
    foreach ($match in [regex]::Matches($Text, '金额在\s*(\d+)\s*万以内')) {
        return ("{0}万以内" -f $match.Groups[1].Value)
    }
    foreach ($match in [regex]::Matches($Text, '预算[^。；\n]{0,10}(\d+)\s*万')) {
        return ("约 {0} 万" -f $match.Groups[1].Value)
    }

    return $null
}

function Get-SalesRegion {
    param(
        [object]$Context,
        [string]$Text
    )

    $contextRegion = Get-ObjectValue -Object $Context -PropertyName "sales_region"
    if ($null -ne $contextRegion -and $contextRegion.ToString().Trim() -ne "") {
        return $contextRegion.ToString().Trim()
    }

    if ($Text -match "华北") { return "华北地区" }
    if ($Text -match "华东") { return "华东地区" }
    if ($Text -match "华南") { return "华南地区" }
    if ($Text -match "西南") { return "西南地区" }
    if ($Text -match "西北") { return "西北地区" }
    if ($Text -match "全国") { return "全国" }

    return $null
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

    $json = $Value | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

$context = Read-JsonFile -Path $ContextPath
$transcript = Get-Content -LiteralPath $TranscriptPath -Raw -Encoding UTF8
$lines = Get-Lines -Text $transcript
$companyName = Get-ObjectValue -Object $context -PropertyName "company_name"
$industryName = Get-ObjectValue -Object $context -PropertyName "industry"
$sourceChannel = Get-ObjectValue -Object $context -PropertyName "channel" -Default "手动导入"

$customerLines = @($lines | Where-Object { $_ -match '^(客户|张总|陈女士|刘总|孙总|客户A|客户B|客户C|客户D)[:：]' })
if ($customerLines.Count -eq 0) {
    $customerLines = $lines
}

$allText = $lines -join " "
$customerText = $customerLines -join " "

$needLines = @(Get-MatchedLines -Lines $customerLines -Patterns @("希望", "想", "需要", "重点", "最好", "计划", "目标", "关注", "更在意", "最大的痛点", "先了解", "有意思"))
$concernLines = @(Get-MatchedLines -Lines $customerLines -Patterns @("担心", "顾虑", "怕", "不太喜欢", "不喜欢", "不希望", "合规", "隐私", "安全", "风险", "别太复杂", "不要太长", "别搞太重", "培训周期不要太长"))
$nextActionLines = @(Get-MatchedLines -Lines $lines -Patterns @("下周", "下次", "再约", "安排", "发我", "发邮件", "邮箱", "邮件", "报价", "方案", "演示", "见面", "周一", "周二", "周三", "周四", "周五", "今晚", "明天", "试点"))

$businessPreferenceMap = [ordered]@{
    "稳健回报优先"     = "稳健|保守|本金安全|保值|流动性"
    "效率优先"         = "效率|提效|自动化|减少人工|统一起来|打通"
    "品牌与可靠性交付" = "稳定|成熟|可靠|案例|长期服务|别上线后频繁折腾"
    "小步试点"         = "试点|先跑一个|先覆盖|POC|先做一期"
    "偏好多维表格/飞书协同" = "飞书|多维表格"
    "私密高触达跟进"   = "微信|私聊|及时沟通"
}

$riskConcernMap = [ordered]@{
    "价格敏感"       = "预算|价格|成本|报价"
    "交付风险"       = "实施|交付|上线|周期拖长|培训周期"
    "合规与数据安全" = "合规|数据安全|权限|隐私|资金进出"
    "效果不确定"     = "效果|ROI|值不值|产出"
    "时间窗口紧张"   = "本周|下周|本月|月底|季度内|尽快|周五之前|明天"
}

$communicationStyleMap = [ordered]@{
    "偏好微信触达" = "微信"
    "偏好简洁表达" = "简洁|不要太长|别太长|三点结论|直接"
    "偏好先看材料" = "先发|先看|发我|材料|方案发我|清单"
    "偏好多方共同沟通" = "一起看|一起聊|都参与|拉上"
    "偏好邮件接收" = "发邮件|发我邮箱|邮箱给我|邮件给我|今晚发我邮箱"
}

$decisionSignalMap = [ordered]@{
    "本人为关键决策人" = "我本人会盯|我来拍板|我定|我决定|先跟我沟通"
    "家庭共同决策"     = "我先生|我太太|先生会一起看|太太也会看"
    "企业多角色决策"   = "CFO|CTO|采购|法务|财务总监|运营负责人|董事会|合伙人"
    "明确预算"         = "预算|金额超过"
    "明确时间表"       = "下周|本周|本月|月底|季度内|明天|周五之前|六月底前|下周一|下周三|下周四"
}

$familyStatus = New-Object System.Collections.Generic.List[string]
if ($customerText -match "太太|妻子|先生|丈夫|已婚") { $familyStatus.Add("已婚/伴侣参与") }
if ($customerText -match "孩子|女儿|儿子") { $familyStatus.Add("有子女") }
if ($customerText -match "留学|英国读书|新加坡读书|国际学校|学费") { $familyStatus.Add("子女教育/留学规划") }

$familyNotes = Get-MatchedLines -Lines $customerLines -Patterns @("太太", "先生", "孩子", "女儿", "儿子", "留学", "英国读书", "新加坡读书", "学费")
$businessPreferences = @(Get-Labels -Text $customerText -Map $businessPreferenceMap)
$riskConcerns = @(Get-Labels -Text $customerText -Map $riskConcernMap)
$communicationStyle = @(Get-Labels -Text $customerText -Map $communicationStyleMap)
$decisionSignals = @(Get-Labels -Text $customerText -Map $decisionSignalMap)

$recentInterestPoints = New-Object System.Collections.Generic.List[string]
if ($allText -match "资产配置|美元") { $recentInterestPoints.Add("关注资产配置") }
if ($allText -match "制造业案例|案例") { $recentInterestPoints.Add("关注行业案例") }
if ($allText -match "报价") { $recentInterestPoints.Add("进入报价讨论") }
if ($allText -match "演示|demo|Demo") { $recentInterestPoints.Add("期待产品演示") }
if ($allText -match "试点") { $recentInterestPoints.Add("倾向先试点再扩展") }
if ($allText -match "飞书|多维表格") { $recentInterestPoints.Add("关注飞书协同落地") }

$budgetMax = Parse-BudgetMax -Text $customerText
if ($budgetMax -gt 0 -and -not ($recentInterestPoints -contains "预算上限约${budgetMax}万")) {
    $recentInterestPoints.Add("预算上限约${budgetMax}万")
}

$meetingTime = Get-DateOrNull -Value $context.meeting_time
$nextMeetingTime = Get-DateOrNull -Value $context.next_meeting_time
$salesRegion = Get-SalesRegion -Context $context -Text $allText
$businessValue = Get-BusinessValue -Text $allText

$leadScore = 50
if ($budgetMax -gt 0) { $leadScore += 12 }
if ($customerText -match "下周|本周|本月|月底|季度内|尽快|明天|周五之前|六月底前") { $leadScore += 10 }
if ($null -ne $nextMeetingTime) { $leadScore += 8 }
if ($decisionSignals.Count -gt 0) { $leadScore += 8 }
if ($customerText -match "报价|方案|演示|试点|实施清单|字段清单") { $leadScore += 8 }
if ($customerText -match "两家工厂|集团|家族办公室|资产配置|华北团队") { $leadScore += 6 }
if ($allText -match "家族办公室|资产配置|美元") { $leadScore += 6 }
if ($riskConcerns.Count -gt 0) { $leadScore += 3 }
if ($customerText -match "不着急|先了解|明年再说|明年再定|先看看|观察一下") { $leadScore -= 15 }
if ($customerText -match "暂无预算|预算要等明年|预算还没批") { $leadScore -= 12 }
if ($customerText -match "采购|法务") { $leadScore += 6 }
$leadScore = Clamp-Score -Value $leadScore

$intentLevel = if ($leadScore -ge 75) { "high" } elseif ($leadScore -ge 60) { "medium" } else { "low" }

$opportunityStage = "初次接触"
if ($customerText -match "合同|签约|付款|定稿") {
    $opportunityStage = "待成交"
}
elseif ($customerText -match "采购|法务|上线一期") {
    $opportunityStage = "推进中"
}
elseif ($customerText -match "报价|演示|实施清单|字段清单|保守版|平衡版") {
    $opportunityStage = "方案沟通"
}
elseif ($needLines.Count -gt 0) {
    $opportunityStage = "需求确认"
}

if ($intentLevel -eq "low") {
    $opportunityStage = "初次接触"
}

$highValueFlag = ($leadScore -ge 75) -or ($budgetMax -ge 80) -or ($allText -match "家族办公室|资产配置|两家工厂|集团|高净值") -or ($context.industry -match "家族办公室")

$followUpTime = $null
if ($null -ne $nextMeetingTime) {
    $followUpTime = $nextMeetingTime
}
elseif ($null -ne $meetingTime) {
    $followUpTime = $meetingTime.AddDays(2)
}

$recommendedAction = switch ($opportunityStage) {
    "待成交" { "推动最终确认并准备签约/付款材料" }
    "推进中" { "整理推进清单，锁定关键角色并跟进采购/法务节点" }
    "方案沟通" { "24小时内发送定制方案/报价并确认下一次沟通" }
    "需求确认" { "补齐关键需求信息并推动进入方案讨论" }
    default { "发送简洁会后摘要并继续培育客户意向" }
}

$channel = "飞书消息"
if ($communicationStyle -contains "偏好邮件接收") {
    $channel = "邮件"
}
elseif ($communicationStyle -contains "偏好微信触达") {
    $channel = "微信"
}

$summary = "{0}本次重点关注{1}；主要顾虑为{2}；建议下一步{3}。" -f `
    $context.customer_name, `
    (Join-Values -Values $needLines -Fallback "当前需求待补充"), `
    (Join-Values -Values $concernLines -Fallback "当前未明确提出强顾虑"), `
    (Join-Values -Values $nextActionLines -Fallback $recommendedAction)

$profileSummary = "{0}当前表现出{1}特征，偏好{2}，沟通上{3}。" -f `
    $context.customer_name, `
    (Join-Values -Values $familyStatus -Fallback "暂无明显家庭标签"), `
    (Join-Values -Values $businessPreferences -Fallback "需求导向"), `
    (Join-Values -Values $communicationStyle -Fallback "可常规跟进")

$latestProgress = "本次会议后，客户处于{0}阶段，Lead Score {1}，推荐动作：{2}" -f $opportunityStage, $leadScore, $recommendedAction

$opportunityTheme = if ($allText -match "资产配置|美元") {
    "资产配置"
}
elseif ($allText -match "巡检|售后|工厂") {
    "售后巡检试点"
}
elseif ($allText -match "CRM|客户信息|会议纪要") {
    "CRM 一期试点"
}
else {
    "商机推进"
}

$opportunityName = "{0} - {1}" -f $context.customer_name, $opportunityTheme
$opportunityDescription = switch ($opportunityStage) {
    "待成交" { "客户已进入合同/定稿推进阶段，重点是锁定签约前材料与排期。" }
    "推进中" { "客户已进入多角色内部推进阶段，需同步采购、法务或实施边界。" }
    "方案沟通" { "客户已进入方案、报价或演示讨论阶段，正在细化可落地方案。" }
    "需求确认" { "客户已明确核心需求与约束条件，下一步应推动进入方案沟通。" }
    default { "客户当前仍处于接触或观察阶段，适合继续培育与补充需求理解。" }
}

$draftMessage = @"
$($context.customer_name) 您好，今天沟通的重点我帮您收了一版：
1. 您当前最关注的是：$(Join-Values -Values $needLines -Fallback "核心需求已记录")。
2. 我们会重点处理：$(Join-Values -Values $concernLines -Fallback "本次暂无突出顾虑")。
3. 下一步我会：$recommendedAction。
如果方便，我先通过${channel}发您精简版材料，您看完后我们再按约定时间推进。
"@.Trim()

$briefTrigger = $null
if ($null -ne $nextMeetingTime) {
    $briefTrigger = $nextMeetingTime.AddHours(-1)
}

$openingScript = "先从客户最在意的{0}切入，再回应{1}，最后确认{2}。" -f `
    (Join-Values -Values $businessPreferences -Fallback "当前需求"), `
    (Join-Values -Values $riskConcerns -Fallback "执行细节"), `
    (Join-Values -Values $nextActionLines -Fallback $recommendedAction)

$meetingRecord = [ordered]@{
    meeting_id         = "MTG-{0}-{1}" -f $context.customer_id, ($meetingTime.ToString("yyyyMMddHHmm"))
    customer_id        = $context.customer_id
    customer_name      = $context.customer_name
    company_name       = $companyName
    meeting_time       = if ($null -ne $meetingTime) { $meetingTime.ToString("o") } else { $null }
    summary            = $summary
    discussion_points  = @($needLines + $concernLines | Select-Object -Unique)
    customer_needs     = @($needLines)
    customer_concerns  = @($concernLines)
    next_actions       = @($nextActionLines)
    commitments        = @($nextActionLines | Select-Object -First 3)
}

$customerProfileUpdate = [ordered]@{
    customer_id            = $context.customer_id
    company_name           = $companyName
    industry               = $industryName
    family_status          = @($familyStatus | Select-Object -Unique)
    family_notes           = @($familyNotes)
    business_preferences   = @($businessPreferences)
    risk_concerns          = @($riskConcerns)
    communication_style    = @($communicationStyle)
    decision_signals       = @($decisionSignals)
    recent_interest_points = @($recentInterestPoints | Select-Object -Unique)
    profile_summary        = $profileSummary
}

$opportunityUpdate = [ordered]@{
    opportunity_id     = $context.opportunity_id
    opportunity_name   = $opportunityName
    opportunity_description = $opportunityDescription
    sales_region       = $salesRegion
    business_value     = $businessValue
    lead_score         = $leadScore
    intent_level       = $intentLevel
    opportunity_stage  = $opportunityStage
    high_value_flag    = [bool]$highValueFlag
    recommended_action = $recommendedAction
    next_follow_up_at  = if ($null -ne $followUpTime) { $followUpTime.ToString("o") } else { $null }
    latest_progress    = $latestProgress
}

$followUpTask = [ordered]@{
    task_title    = "跟进 {0} - {1}" -f $context.customer_name, $opportunityStage
    owner         = $context.owner
    due_at        = if ($null -ne $followUpTime) { $followUpTime.ToString("o") } else { $null }
    channel       = $channel
    draft_message = $draftMessage
    checklist     = @(
        "确认客户核心需求是否完整记录",
        "按推荐动作发送材料或推进下一次沟通",
        "更新飞书多维表格中的商机状态"
    )
}

$preMeetingBrief = [ordered]@{
    next_meeting_at       = if ($null -ne $nextMeetingTime) { $nextMeetingTime.ToString("o") } else { $null }
    trigger_at            = if ($null -ne $briefTrigger) { $briefTrigger.ToString("o") } else { $null }
    headline              = "{0} 会前行动简报" -f $context.customer_name
    opening_script        = $openingScript
    key_points            = @($needLines + $nextActionLines | Select-Object -Unique)
    watchouts             = @($concernLines | Select-Object -Unique)
    materials_to_prepare  = @(
        "客户画像摘要",
        "上次会议结论",
        "与本次需求对应的方案/案例/报价材料"
    )
}

$customerTableRow = [ordered]@{
    "客户ID"       = $context.customer_id
    "客户名称"     = $context.customer_name
    "客户公司"     = $companyName
    "行业"         = $industryName
    "客户负责人"   = $context.owner
    "家庭标签"     = Join-Values -Values $customerProfileUpdate.family_status
    "家庭备注"     = Join-Values -Values $customerProfileUpdate.family_notes
    "商业偏好"     = Join-Values -Values $customerProfileUpdate.business_preferences
    "风险顾虑"     = Join-Values -Values $customerProfileUpdate.risk_concerns
    "沟通风格"     = Join-Values -Values $customerProfileUpdate.communication_style
    "决策信号"     = Join-Values -Values $customerProfileUpdate.decision_signals
    "最近关注点"   = Join-Values -Values $customerProfileUpdate.recent_interest_points
    "客户画像摘要" = $customerProfileUpdate.profile_summary
    "最后更新时间" = if ($null -ne $meetingTime) { $meetingTime.ToString("o") } else { $null }
    "数据来源"     = $sourceChannel
}

$opportunitySnapshotRow = [ordered]@{
    "商机ID"       = $context.opportunity_id
    "客户ID"       = $context.customer_id
    "客户名称"     = $context.customer_name
    "客户公司"     = $companyName
    "机会名称"     = $opportunityUpdate.opportunity_name
    "商机描述"     = $opportunityUpdate.opportunity_description
    "当前阶段"     = $opportunityUpdate.opportunity_stage
    "Lead Score"   = $opportunityUpdate.lead_score
    "意向等级"     = $opportunityUpdate.intent_level
    "高净值优先"   = $opportunityUpdate.high_value_flag
    "销售区域"     = $opportunityUpdate.sales_region
    "业务价值"     = $opportunityUpdate.business_value
    "推荐动作"     = $opportunityUpdate.recommended_action
    "最新进展"     = $opportunityUpdate.latest_progress
    "下次跟进时间" = $opportunityUpdate.next_follow_up_at
    "最近会议时间" = $meetingRecord.meeting_time
    "商机负责人"   = $context.owner
    "数据来源"     = $sourceChannel
}

$feishuPayload = [ordered]@{
    customer_table = [ordered]@{
        mode        = "upsert"
        key_field   = "客户ID"
        key         = $context.customer_id
        update_fields = $customerTableRow
    }
    opportunity_snapshot_table = [ordered]@{
        mode       = "append"
        append_row = $opportunitySnapshotRow
    }
}

$crmPacket = [ordered]@{
    input = [ordered]@{
        transcript_path = (Resolve-Path -LiteralPath $TranscriptPath).Path
        context_path    = (Resolve-Path -LiteralPath $ContextPath).Path
        customer_id     = $context.customer_id
        opportunity_id  = $context.opportunity_id
    }
    meeting                = $meetingRecord
    customer_profile_update = $customerProfileUpdate
    opportunity_update     = $opportunityUpdate
    follow_up_task         = $followUpTask
    pre_meeting_brief      = $preMeetingBrief
    customer_table_row     = $customerTableRow
    opportunity_snapshot_row = $opportunitySnapshotRow
    feishu_bitable_payload = $feishuPayload
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

Write-JsonFile -Path (Join-Path $OutputDir "meeting_record.json") -Value $meetingRecord
Write-JsonFile -Path (Join-Path $OutputDir "customer_profile_update.json") -Value $customerProfileUpdate
Write-JsonFile -Path (Join-Path $OutputDir "opportunity_update.json") -Value $opportunityUpdate
Write-JsonFile -Path (Join-Path $OutputDir "follow_up_task.json") -Value $followUpTask
Write-JsonFile -Path (Join-Path $OutputDir "pre_meeting_brief.json") -Value $preMeetingBrief
Write-JsonFile -Path (Join-Path $OutputDir "customer_table_row.json") -Value $customerTableRow
Write-JsonFile -Path (Join-Path $OutputDir "opportunity_snapshot_row.json") -Value $opportunitySnapshotRow
Write-JsonFile -Path (Join-Path $OutputDir "crm_packet.json") -Value $crmPacket

Write-Host "CRM packet generated at: $OutputDir"






