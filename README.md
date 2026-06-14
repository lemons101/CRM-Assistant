# CRM Assistant

面向销售 / 私域 CRM 跟进场景的会议理解与飞书落表项目。

当前项目已经统一为一个 Python CLI：`scripts/crm_assistant.py`。
它负责把会议文本、飞书会议原始 JSON、飞书云文档正文、Word/DOCX 会议纪要，转换成 CRM 结构化结果，并在具备凭据时同步到飞书多维表格。

---

## 1. 当前项目状态

本项目当前已经和实际链路对齐，核心能力包括：

- `transcript + context` 规则处理
- 飞书会议原始 JSON -> CRM
- 飞书云文档正文 -> CRM
- Word / DOCX -> CRM
- CRM 结果 -> 飞书 Customers / OpportunitySnapshots 两表
- 多轮客户推进追踪
- 客户字段“弱值不覆盖强值”更新规则
- `沟通风格` / `风险顾虑` 字段合并策略
- 飞书字段类型转换（尤其日期时间 -> 毫秒时间戳）

> 当前最适合的使用方式：直接把 Word / DOCX 或飞书会议数据送进 CLI，再按需要同步到飞书表格。

---

## 2. 两张核心表

### 2.1 Customers
长期客户画像表，按客户身份更新。

常见字段：
- 客户ID
- 客户名称
- 客户公司
- 职务
- 行业
- MBTI
- 是否单身
- 沟通风格
- 成交阻力
- 价格敏感程度
- 风险顾虑
- 客户画像摘要
- 客户负责人
- 最后更新时间
- 数据来源

### 2.2 OpportunitySnapshots
每次会议一条商机快照，不覆盖历史。

常见字段：
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

### 3.3 商机快照
商机快照表按会议轮次追加，用于保留推进轨迹，例如：
- 需求确认
- 方案沟通
- 推进中
- 待成交
- 已成交

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

如果还要继续同步飞书表格，再补：

```bash
python ./scripts/crm_assistant.py ingest-docx-to-bitable \
  --docx-path ./meeting.docx \
  --output-dir ./runtime/your_case \
  --sync-feishu \
  --app-token-or-url 'https://.../base/APP_TOKEN' \
  --customer-table-id tblXXXX \
  --opportunity-table-id tblYYYY
```

> 注意：如果命令行环境没有 Feishu app 凭据，仅加 `--sync-feishu` 还不够，还需要通过参数、配置文件或环境变量提供 app 凭据。

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
- 如果需要“命中已有飞书记录后优先继承正式客户ID / 商机ID”，这是一个仍值得继续加强的点
- 如果当前执行环境没有 Feishu app 凭据，CLI 侧的 `--sync-feishu` 可能会因缺少凭据而失败；这种情况下需要由具备飞书工具能力的一侧继续写表

---

## 9. 最低回归检查

每次修改后，至少建议执行：

```bash
python ./scripts/crm_assistant.py --help
python ./scripts/crm_assistant.py run-sample-tests
python ./scripts/crm_assistant.py run-feishu-pipeline-tests
```
