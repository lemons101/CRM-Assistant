# CRM Assistant

一个面向**私域销售 / 高净值线索跟进**场景的会议理解 Skill。  
它的目标是：把会议转录文本或飞书会议原始数据，转换成可落到 CRM / 飞书多维表格中的结构化结果。

> 当前项目已补齐 **Python 版本 CLI**，适合没有 `pwsh / powershell` 的 Linux / 云服务器环境。  
> 原有 `.ps1` 脚本仍保留，但现在推荐优先使用 `scripts/crm_assistant.py`。

---

## 1. 项目定位

这个项目解决的是会议结束后的这段工作流：

```text
会议原始数据 / 转录文本
  -> 提取客户上下文与发言内容
  -> 判断客户需求、顾虑、阶段、意向、价值
  -> 生成客户画像增量
  -> 生成商机推进快照
  -> 输出飞书多维表格可写入结果
```

适用场景包括：

- 销售会议纪要整理
- 高净值客户跟进
- 私域 CRM 更新
- 飞书多维表格商机推进记录
- 同一客户多轮会议阶段变化追踪

---

## 2. 当前已实现能力

本项目当前已完成并验证了以下能力：

### 2.1 规则链路

输入：
- `transcript.txt`
- `context.json`

输出：
- `meeting_record.json`
- `customer_profile_update.json`
- `opportunity_update.json`
- `follow_up_task.json`
- `pre_meeting_brief.json`
- `customer_table_row.json`
- `opportunity_snapshot_row.json`
- `crm_packet.json`

### 2.2 飞书原始数据链路

输入：
- `feishu_raw/*.json`

中间过程：
- 提取 `context.json`
- 提取 `transcript.txt`

再进入主处理流程，输出 CRM 结果与飞书两表 payload。

### 2.3 LLM 提示词链路

支持从样本生成标准提示词包：
- `system_prompt.txt`
- `user_prompt.txt`
- `prompt_package.json`

并支持：
- 校验大模型结构化输出
- 将模型输出转成 CRM / 飞书表结果

### 2.4 多轮客户推进链路

支持同一客户跨多轮会议的推进分析，可输出：
- 各轮独立结果
- `journey_summary.json`

### 2.5 用户侧 Prompt 模式

支持直接把**飞书会议原始 JSON** 喂给 OpenClaw：

```text
飞书原始 JSON
  -> 提取 context + transcript
  -> 生成两张飞书表记录
  -> 能写飞书就写，不能写就输出待写入内容
```

---

## 3. 当前链路状态

当前版本已经实际跑通以下检查：

- 规则样本测试
- 飞书原始数据链路测试
- LLM 输出校验与转换测试
- 多轮客户推进测试
- Prompt 生成测试

也就是说，从“原始输入”到“结构化结果”的核心业务链路是完整的。

> 当前**没有**实现“官方 API 直写飞书”的自动化脚本。  
> 当前更适合：
> - 用户侧 Prompt 实战
> - 演示
> - 半自动落表
> - 让 OpenClaw / 龙虾理解并执行 Skill

---

## 4. 飞书数据设计

本项目当前固定采用**两表方案**：

### 表 1：客户信息表

用途：
- 沉淀长期客户画像
- 按 `客户ID` 做 upsert

核心字段：
- 客户ID
- 客户名称
- 客户公司
- 行业
- 客户负责人
- 家庭标签
- 家庭备注
- 商业偏好
- 风险顾虑
- 沟通风格
- 决策信号
- 最近关注点
- 客户画像摘要
- 最后更新时间
- 数据来源

### 表 2：商机推进快照表

用途：
- 每次会议结束后追加一条快照
- 不覆盖历史，保留完整推进轨迹

核心字段：
- 商机ID
- 客户ID
- 客户名称
- 客户公司
- 机会名称
- 商机描述
- 当前阶段
- Lead Score
- 意向等级
- 高净值优先
- 销售区域
- 业务价值
- 推荐动作
- 最新进展
- 下次跟进时间
- 最近会议时间
- 商机负责人
- 数据来源

---

## 5. 项目结构

```text
crm-assistant/
├─ agents/
│  └─ openai.yaml
├─ assets/
│  ├─ expected/          # 测试断言
│  ├─ feishu_raw/        # 飞书原始会议样本
│  ├─ few_shot/          # few-shot 示例
│  └─ samples/           # transcript/context 样本
├─ references/
│  ├─ input_schemas.md
│  ├─ output_schemas.md
│  ├─ feishu-bitable-mapping.md
│  ├─ llm_prompt_template.md
│  ├─ llm_output_schema.md
│  └─ user_side_feishu_prompt.md
├─ runtime/              # 运行产物 / 测试输出
├─ scripts/
│  ├─ process_transcript.ps1
│  ├─ build_context_from_feishu.ps1
│  ├─ build_llm_prompt.ps1
│  ├─ validate_model_output.ps1
│  ├─ convert_model_output_to_crm.ps1
│  ├─ run_sample_tests.ps1
│  ├─ run_feishu_pipeline_tests.ps1
│  ├─ run_model_output_tests.ps1
│  └─ run_customer_journey.ps1
├─ README.md
└─ SKILL.md
```

---

## 6. 快速开始

## 6.0 环境要求

- Python 3.10+
- 无第三方依赖

如果你本地使用 conda，也可以直接用你之前的环境：

```bash
conda run -n env1 python ./scripts/crm_assistant.py --help
```

## 6.1 方式一：直接处理 transcript + context

```bash
python ./scripts/crm_assistant.py process-transcript \
  --transcript-path ./assets/samples/zhang_manufacturing_transcript.txt \
  --context-path ./assets/samples/zhang_manufacturing_context.json \
  --output-dir ./runtime/zhang_manufacturing
```

---

## 6.2 方式二：从飞书原始数据开始

先提取标准化输入：

```bash
python ./scripts/crm_assistant.py build-context-from-feishu \
  --raw-input-path ./assets/feishu_raw/liu_enterprise_it.json \
  --output-dir ./runtime/from_feishu/liu_enterprise_it
```

再进入主处理：

```bash
python ./scripts/crm_assistant.py process-transcript \
  --transcript-path ./runtime/from_feishu/liu_enterprise_it/transcript.txt \
  --context-path ./runtime/from_feishu/liu_enterprise_it/context.json \
  --output-dir ./runtime/from_feishu/liu_enterprise_it/process
```

---

## 6.3 方式三：生成标准 LLM Prompt 包

```bash
python ./scripts/crm_assistant.py build-llm-prompt \
  --transcript-path ./assets/samples/chen_familyoffice_transcript.txt \
  --context-path ./assets/samples/chen_familyoffice_context.json \
  --output-dir ./runtime/llm_prompt/chen_familyoffice
```

---

## 6.4 方式四：校验并转换 LLM 输出

```bash
python ./scripts/crm_assistant.py validate-model-output \
  --model-output-path ./runtime/llm_outputs/liu_enterprise_it/model_output.json

python ./scripts/crm_assistant.py convert-model-output \
  --model-output-path ./runtime/llm_outputs/liu_enterprise_it/model_output.json \
  --context-path ./assets/samples/liu_enterprise_it_context.json \
  --output-dir ./runtime/from_model/liu_enterprise_it
```

---

## 6.5 方式五：用户侧 Prompt 直接使用

如果你希望直接喂给 OpenClaw / 龙虾，可优先使用：

- `references/user_side_feishu_prompt.md`

这版 Prompt 的输入是：
- 飞书会议原始 JSON

这版 Prompt 的目标是：
- 先提取 `context + transcript`
- 再生成两张飞书表记录
- 如果具备能力，再直接写飞书

---

## 7. 输出说明

推荐重点关注：

### `crm_packet.json`
总包结果，包含：
- 会议结果
- 客户画像增量
- 商机判断
- 跟进任务
- 会前简报
- 飞书两张表记录
- 两表写入 payload

### `customer_table_row.json`
客户信息表单行结果。

### `opportunity_snapshot_row.json`
商机推进快照表单行结果。

---

## 8. 测试命令

### 全部规则样本

```bash
python ./scripts/crm_assistant.py run-sample-tests
```

### 全部飞书原始链路样本

```bash
python ./scripts/crm_assistant.py run-feishu-pipeline-tests
```

### 全部 LLM 输出链路样本

```bash
python ./scripts/crm_assistant.py run-model-output-tests
```

### 多轮客户推进样本

```bash
python ./scripts/crm_assistant.py run-customer-journey \
  --manifest-path ./assets/samples/liu_enterprise_it_journey_manifest.json \
  --output-dir ./runtime/liu_enterprise_it_journey
```

---

## 9. 推荐上传 GitHub 的内容

建议保留：

- `agents/`
- `assets/`
- `references/`
- `scripts/`
- `scripts/crm_assistant.py`
- `SKILL.md`
- `README.md`

`runtime/` 属于运行产物目录。  
如果你希望仓库更干净，建议不把大部分 `runtime` 结果提交到 GitHub。

---

## 10. 给龙虾 / OpenClaw 部署建议

如果你准备让龙虾部署这个 Skill，建议优先走这两条方式之一：

### 方式 A：项目化调用
- 先用脚本处理 `feishu_raw`
- 再输出标准结果
- 适合结构化演示

### 方式 B：用户侧 Prompt 调用
- 直接使用 `references/user_side_feishu_prompt.md`
- 输入飞书会议原始 JSON
- 让模型先提取 `context + transcript`
- 再生成两张飞书表结果

如果是教学 / 演示 / 快速落地，优先建议 **方式 B**。

---

## 11. 当前边界

当前版本未包含：

- 飞书开放平台 API 自动写入脚本
- 真正的线上 ASR / 会议录音接入
- 持久化数据库
- 正式权限管理与审计机制

当前版本已经足够支持：

- Skill 演示
- Prompt 实战
- 会议纪要理解
- CRM 字段结构化
- 飞书多维表格写入前的数据准备

---

## 12. 参考资料

- `SKILL.md`
- `references/input_schemas.md`
- `references/output_schemas.md`
- `references/feishu-bitable-mapping.md`
- `references/llm_prompt_template.md`
- `references/llm_output_schema.md`
- `references/user_side_feishu_prompt.md`

---

## 13. 一句话总结

这是一个已经跑通核心链路的 CRM 会议理解 Skill：  
**它能把飞书会议原始数据或转录文本，转换成客户画像、商机推进判断，以及两张飞书表可直接落地的结构化结果。**
