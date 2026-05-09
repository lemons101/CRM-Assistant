param(
    [Parameter(Mandatory = $true)]
    [string]$TranscriptPath,

    [Parameter(Mandatory = $true)]
    [string]$ContextPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string[]]$ExampleNames = @("chen_familyoffice", "liu_enterprise_it", "sun_observer")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Build-ExampleBlock {
    param([object]$Example)

    $inputContext = $Example.input.context | ConvertTo-Json -Depth 12
    $inputTranscript = $Example.input.transcript
    $outputJson = $Example.output | ConvertTo-Json -Depth 12

    $lines = @(
        "### 示例：$($Example.name)",
        "任务提示：$($Example.task_hint)",
        "",
        "输入 context:",
        '```json',
        $inputContext,
        '```',
        "",
        "输入 transcript:",
        '```text',
        $inputTranscript,
        '```',
        "",
        "参考输出:",
        '```json',
        $outputJson,
        '```'
    )
    return ($lines -join "`r`n")
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $skillRoot "references\\llm_prompt_template.md"
$schemaPath = Join-Path $skillRoot "references\\llm_output_schema.md"
$fewShotDir = Join-Path $skillRoot "assets\\few_shot"

$template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
$contextJson = Get-Content -LiteralPath $ContextPath -Raw -Encoding UTF8
$transcriptText = Get-Content -LiteralPath $TranscriptPath -Raw -Encoding UTF8

$exampleBlocks = New-Object System.Collections.Generic.List[string]
foreach ($name in $ExampleNames) {
    $path = Join-Path $fewShotDir ("{0}.json" -f $name)
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Few-shot example not found: $path"
    }
    $example = Read-JsonFile -Path $path
    $exampleBlocks.Add((Build-ExampleBlock -Example $example))
}

$systemPrompt = (
    @(
        $template,
        "",
        "以下是输出 schema，请严格遵守：",
        "",
        $schema
    ) -join "`r`n"
).Trim()

$userPrompt = (
    @(
        "以下是 few-shot 示例，请学习其抽取方式、阶段判断标准和输出风格：",
        "",
        ($exampleBlocks -join "`r`n`r`n"),
        "",
        "现在请处理新的输入。",
        "",
        "输入 context:",
        '```json',
        $contextJson,
        '```',
        "",
        "输入 transcript:",
        '```text',
        $transcriptText,
        '```',
        "",
        "请只输出 JSON，不要输出解释。"
    ) -join "`r`n"
).Trim()

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$promptPackage = [ordered]@{
    system_prompt = $systemPrompt
    user_prompt   = $userPrompt
    examples      = $ExampleNames
    transcript_path = (Resolve-Path -LiteralPath $TranscriptPath).Path
    context_path  = (Resolve-Path -LiteralPath $ContextPath).Path
}

$promptPackage | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDir "prompt_package.json") -Encoding UTF8
$systemPrompt | Set-Content -LiteralPath (Join-Path $OutputDir "system_prompt.txt") -Encoding UTF8
$userPrompt | Set-Content -LiteralPath (Join-Path $OutputDir "user_prompt.txt") -Encoding UTF8

Write-Host "LLM prompt package generated at: $OutputDir"



