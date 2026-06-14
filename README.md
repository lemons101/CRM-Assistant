# CRM Assistant

面向销售 / 私域 CRM 跟进场景的会议理解与飞书落表项目。

当前项目已经统一为一个 Python CLI：`scripts/crm_assistant.py`。
它负责把会议文本、飞书会议原始 JSON、飞书云文档正文、Word/DOCX 会议纪要，转换成 CRM 结构化结果，并在具备凭据时同步到飞书多维表格。

---

## 1. 当前项目状态

本项目当前已经和真实链路对齐，核心能力包括：

- `transcript + context` 规则处理
- 飞书会议原始 JSON -> CRM
- 飞书云文档正文 -> CRM
- Word / DOCX -> CRM
- CRM 结果 -> 飞书 `Customers` / `OpportunitySnapshots` 两表
- 多轮客户推进追踪
- Customers 字段“弱值不覆盖强值”更新规则
- `沟通风格` / `风险顾虑` 字段合并策略
- 飞书字段类型转换（尤其日期时间 -> 毫秒时间戳）
- 支持在 app 权限不足时，改走**用户权限**直接写入飞书多维表格

> 当前最贴近真实使用方式的链路：**Word / DOCX -> CRM Assistant -> 用户权限写入飞书表**。

---

## 2. 当前在用的飞书表

当前项目已经对接并验证过一套真实飞书多维表格：

- `app_token`: `BEwNbIlMfaeNFcs3SZWc7SjInvh`
- `Customers.table_id`: `tblCq566fSxHlwkG`
- `OpportunitySnapshots.table_id`: `tblTuZySbF8dA1OP`

### 2.1 Customers
长期客户画像表，按客户身份更新。

当前真实字段：
- 客户ID（主字段 / Primary）
- 客户名称
- 客户公司
- 行业
- MBTI
- 是否单身
- 沟通风格
- 成交阻力
- 价格敏感程度
- 风险顾虑
- 客户画像摘要
- 客户负责人
- 最后更新时间（DateTime）
- 数据来源
- 职务

### 2.2 OpportunitySnapshots
每次会议一条商机快照，不覆盖历史。

当前真实字段：
- 商机ID（主字段 / Primary）
- 客户ID
- 客户名称
- 客户公司
- 机会名称
- 商机描述
- 当前阶段
- Lead Score（Number）
- 意向等级
- 高净值优先（Checkbox）
- 销售区域
- 业务价值
- 推荐动作
- 最新进展
- 下次跟进时间（DateTime）
- 最近会议时间（DateTime）
- 商机负责人
- 数据来源

命名建议：
- `机会名称` 应优先采用 **`客户公司 - 项目主题`**
- 不要把联系人姓名列表硬拼到最前面
- 客户身份已经通过 `客户名称`、`客户公司`、`客户ID` 单独表达，不需要在 `机会名称` 再重复一次

### 2.3 当前已验证的真实表内数据
已经验证成功写入的客户包括：
- 张琪
- 李昊
- 王拓

已经验证成功写入的商机快照包括：
- `O-BBA6BE6702`（需求确认）
- `O-133EBBF3FB`（方案沟通）

---

## 3. 关键业务规则

### 3.1 Customers 字段更新规则
Customers 的所有字段统一遵守：

- 如果本轮值是弱值：`未明确` / `未知` / `待确认` / 空值
  - **不要覆盖**历史上已经明确的旧值
- 如果本轮值是新的明确判断
  - **允许更新**旧值

### 3.2 合并字段
以下字段采用“保留旧值 + 补充新值 + 去重”策略：
- 沟通风格
- 风险顾虑

### 3.3 Customers 命中规则
当前项目已经改为：
- 优先按 `客户ID` 命中已有飞书记录
- 若缺少正式 `客户ID`，再回退到 `客户名称 + 客户公司`

### 3.4 商机快照
商机快照表按会议轮次追加，用于保留推进轨迹，例如：
- 需求确认
- 方案沟通
- 推进中
- 待成交
- 已成交

### 3.5 商机ID 继承规则
如果是**同一个客户、同一个项目、只是推进到了不同阶段**，应优先沿用**同一个商机ID**，并在 `OpportunitySnapshots` 中追加新的阶段快照。

只有在以下情况更适合生成新的商机ID：
- 同一客户下的全新项目
- 不同预算包 / 不同采购线
- 已经明确是另一条独立需求线

换句话说：
- **阶段变化** → 同一个商机ID，不同快照
- **新项目** → 新商机ID

---

## 4. CLI 子命令

查看完整帮助：

```bash
python ./scripts/crm_assistant.py --help
```

当前主命令包括：
- `process-transcript`
- `build-context-from-feishu`
- `build-context-from-feishu-doc`
- `ingest-docx-to-bitable`
- `build-llm-prompt`
- `validate-model-output`
- `convert-model-output`
- `run-sample-tests`
- `run-feishu-pipeline-tests`
- `run-model-output-tests`
- `run-customer-journey`
- `inspect-feishu-bitable`
- `sync-feishu-bitable`
- `ingest-feishu-raw-to-bitable`
- `ingest-feishu-doc-to-bitable`

---

## 5. 常用用法

### 5.1 直接处理 Word / DOCX

```bash
python ./scripts/crm_assistant.py ingest-docx-to-bitable \
  --docx-path ./meeting.docx \
  --output-dir ./runtime/your_case
```

如果还要继续走 app 权限写表：

```bash
python ./scripts/crm_assistant.py ingest-docx-to-bitable \
  --docx-path ./meeting.docx \
  --output-dir ./runtime/your_case \
  --sync-feishu \
  --config-path ./feishu_config.json
```

> 注意：如果命令行环境里的 app 权限不足，CLI 侧 `--sync-feishu` 可能会被 Feishu Open API 拒绝。当前项目已经验证过一种更稳的真实路径：**先让 CLI 产出结构化结果，再通过用户权限把结果写进同一套飞书表**。

### 5.2 处理飞书会议原始 JSON

```bash
python ./scripts/crm_assistant.py ingest-feishu-raw-to-bitable \
  --raw-input-path ./raw.json \
  --output-dir ./runtime/your_case
```

### 5.3 处理飞书文档正文

```bash
python ./scripts/crm_assistant.py ingest-feishu-doc-to-bitable \
  --doc-markdown-path ./source_doc.md \
  --output-dir ./runtime/your_case
```

### 5.4 仅做规则引擎处理

```bash
python ./scripts/crm_assistant.py process-transcript \
  --transcript-path ./transcript.txt \
  --context-path ./context.json \
  --output-dir ./runtime/your_case/process
```

---

## 6. 输出文件

常见输出包括：
- `meeting_record.json`
- `customer_profile_update.json`
- `opportunity_update.json`
- `follow_up_task.json`
- `pre_meeting_brief.json`
- `customer_table_rows.json`
- `opportunity_snapshot_row.json`
- `crm_packet.json`

在 ingest 流程里，还会看到：
- `source_doc.md`
- `transcript.txt`
- `context.json`
- `build_result.json`
- `ingest_*_result.json`

---

## 7. 参考资料

按需阅读：
- `references/input_schemas.md`
- `references/output_schemas.md`
- `references/feishu-bitable-mapping.md`
- `references/llm_prompt_template.md`
- `references/llm_output_schema.md`
- `references/openclaw_user_side_write_prompt.md`
- `references/user_side_feishu_prompt.md`

---

## 8. 当前已知注意点

- DOCX 直连入口已经可用
- 飞书字段类型转换已经补齐（日期/时间会转毫秒时间戳）
- Customers 的弱值保护与合并规则已经补齐
- Customers 当前已经改为：优先按 `客户ID` 命中已有飞书记录；若缺少正式 ID，再回退到 `客户名称 + 客户公司`
- 当前真实表已经验证过：app 权限写表可能会遇到 `403 Forbidden`，但**用户权限写入链路已跑通**

---

## 9. 最低回归检查

每次修改后，至少建议执行：

```bash
python ./scripts/crm_assistant.py --help
python ./scripts/crm_assistant.py run-sample-tests
python ./scripts/crm_assistant.py run-feishu-pipeline-tests
```

说明：
- 当前仓库默认不再保留 `assets/samples/`，所以 `run-sample-tests` 在无样本时会跳过而不是报错
- 若需要真正执行样本回归，请先自行补回脱敏样本与对应断言文件
