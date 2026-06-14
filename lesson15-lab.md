# 第 15 节实验手册：CRM Assistant 会议商机推进与飞书落表

> 配套课程：AI 业务流架构师 · 第 15 节《CRM Assistant 会议商机推进与飞书落表》
> 预计耗时：45-75 分钟
> 操作方式：可在飞书 DM 中让助手代执行，也可以在服务器命令行手动执行
> 前置条件：OpenClaw 已部署、CRM-Assistant 已拉到服务器、飞书应用具备多维表格权限

---

## 0. 这份手册对应的当前项目状态

当前仓库已经做过清理，默认**不再保留 raw 客户数据样本和 runtime 运行产物**。

因此本手册统一基于以下真实现状：
- raw 输入样本不再默认提交到仓库
- `runtime/` 默认是空目录，仅保留 `.gitkeep`
- `feishu_config.json` 属于本地配置文件，不应提交到 git
- 推荐优先使用：
  - Word / DOCX
  - 飞书文档 Markdown
  - 用户自己提供的飞书会议原始 JSON

---

## 1. 创建飞书多维表格

你需要准备一个 Bitable Base，并创建两张表：
- `Customers`
- `OpportunitySnapshots`

### 1.1 Customers 建议字段
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

### 1.2 OpportunitySnapshots 建议字段
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

### 1.3 字段类型建议
- `Lead Score`：数字字段
- `高净值优先`：复选框 / 布尔字段
- `最后更新时间`、`下次跟进时间`、`最近会议时间`：日期时间字段
- 其他大部分字段可先使用文本字段

完成后记录：
- Base 链接 / app_token
- Customers 的 `table_id`
- OpportunitySnapshots 的 `table_id`

---

## 2. 部署项目

如果目录不存在：

```bash
git clone https://github.com/lemons101/CRM-Assistant.git /root/projects/CRM-Assistant
```

如果目录已存在：

```bash
cd /root/projects/CRM-Assistant
git pull
```

建议使用独立虚拟环境：

```bash
cd /root/projects/CRM-Assistant
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python scripts/crm_assistant.py --help
```

验收点：
- `python scripts/crm_assistant.py --help` 能正常输出

---

## 3. 配置飞书写表参数

在项目目录创建本地配置文件：

`/root/projects/CRM-Assistant/feishu_config.json`

示例：

```json
{
  "app_id": "cli_xxxxxxxx",
  "app_secret": "xxxxxxxx",
  "app_token": "bascnxxxxxxxx",
  "customer_table_id": "tblxxxxxxxx",
  "opportunity_snapshot_table_id": "tblyyyyyyyy"
}
```

注意：
- 这是本地配置文件，不要提交到 git
- 仓库已默认忽略 `feishu_config.json`

---

## 4. 推荐输入方式

当前项目推荐 3 种入口：

### 4.1 Word / DOCX 入口
最适合真实会议纪要落表：

```bash
python scripts/crm_assistant.py ingest-docx-to-bitable \
  --docx-path ./meeting.docx \
  --output-dir ./runtime/your_case
```

如果要直接写飞书：

```bash
python scripts/crm_assistant.py ingest-docx-to-bitable \
  --docx-path ./meeting.docx \
  --output-dir ./runtime/your_case \
  --config-path ./feishu_config.json \
  --sync-feishu
```

### 4.2 飞书文档 Markdown 入口
适合已经把飞书文档导出的情况：

```bash
python scripts/crm_assistant.py ingest-feishu-doc-to-bitable \
  --doc-markdown-path ./source_doc.md \
  --output-dir ./runtime/your_case
```

如需直接写飞书：

```bash
python scripts/crm_assistant.py ingest-feishu-doc-to-bitable \
  --doc-markdown-path ./source_doc.md \
  --output-dir ./runtime/your_case \
  --config-path ./feishu_config.json \
  --sync-feishu
```

### 4.3 飞书会议原始 JSON 入口
适合用户自己提供 raw 数据：

```bash
python scripts/crm_assistant.py ingest-feishu-raw-to-bitable \
  --raw-input-path ./your_raw.json \
  --output-dir ./runtime/your_case \
  --config-path ./feishu_config.json
```

如果只想做 dry-run：

```bash
python scripts/crm_assistant.py ingest-feishu-raw-to-bitable \
  --raw-input-path ./your_raw.json \
  --output-dir ./runtime/your_case \
  --config-path ./feishu_config.json \
  --dry-run
```

> 注意：当前 raw ingest 命令本身没有 `--sync-feishu` 开关；是否继续走写表，由你是否提供写表配置以及是否 dry-run 决定。

---

## 5. 仅做本地结构化验证

如果你只想验证 CRM 结果是否能正常生成，可以先走本地链路。

### 5.1 已有 `transcript + context`

```bash
python scripts/crm_assistant.py process-transcript \
  --transcript-path ./transcript.txt \
  --context-path ./context.json \
  --output-dir ./runtime/local_probe/process
```

### 5.2 已有飞书原始 JSON
先提取：

```bash
python scripts/crm_assistant.py build-context-from-feishu \
  --raw-input-path ./your_raw.json \
  --output-dir ./runtime/local_probe/build
```

再处理：

```bash
python scripts/crm_assistant.py process-transcript \
  --transcript-path ./runtime/local_probe/build/transcript.txt \
  --context-path ./runtime/local_probe/build/context.json \
  --output-dir ./runtime/local_probe/process
```

重点检查输出：
- `crm_packet.json`
- `meeting_record.json`
- `customer_profile_update.json`
- `opportunity_update.json`
- `customer_table_rows.json`
- `opportunity_snapshot_row.json`

> 兼容旧链路时，也可能看到 `customer_table_row.json`。

---

## 6. 检查飞书表结构

在真实写表前，建议先检查目标表结构：

```bash
python scripts/crm_assistant.py inspect-feishu-bitable \
  --config-path ./feishu_config.json \
  --output-dir ./runtime/inspect_feishu
```

检查点：
- 是否能拿到 `tenant_access_token`
- 是否能读到 Customers 表
- 是否能读到 OpportunitySnapshots 表
- 字段是否完整
- 时间字段类型是否合理

---

## 7. dry-run 写表验证

推荐先用 `sync-feishu-bitable` 做 dry-run：

```bash
python scripts/crm_assistant.py sync-feishu-bitable \
  --crm-packet-path ./runtime/local_probe/process/crm_packet.json \
  --output-dir ./runtime/dry_run_sync \
  --config-path ./feishu_config.json \
  --dry-run
```

重点检查：
- 是否生成 `feishu_sync_result.json`
- `dry_run` 是否为 `true`
- Customers 计划是 `create` 还是 `update`
- OpportunitySnapshots 计划是否为追加
- 待写入的客户、阶段、Lead Score、推荐动作是否正确

---

## 8. 真实写入飞书

确认 dry-run 正常后，再执行真实写入：

```bash
python scripts/crm_assistant.py sync-feishu-bitable \
  --crm-packet-path ./runtime/local_probe/process/crm_packet.json \
  --output-dir ./runtime/write_once \
  --config-path ./feishu_config.json
```

写入成功后，建议返回并核对：
- Customers 是新增还是更新
- OpportunitySnapshots 是否追加成功
- 本次写入的客户名称、阶段、Lead Score、意向等级、推荐动作

---

## 9. 当前项目里的关键业务规则

### 9.1 Customers 更新规则
- 如果本轮值是弱值：`未明确` / `未知` / `待确认` / 空值
- 不要覆盖历史上已经明确的旧值

### 9.2 合并字段
以下字段采用“旧值保留 + 新值补充 + 去重”：
- `沟通风格`
- `风险顾虑`

### 9.3 OpportunitySnapshots
- 每轮会议追加一条快照
- 不覆盖历史

### 9.4 时间字段
真正写飞书前，日期时间字段应按字段类型转换成毫秒时间戳。

---

## 10. 验收清单

- [ ] 项目部署成功
- [ ] `python scripts/crm_assistant.py --help` 正常
- [ ] 飞书 Base 已创建并有两张表
- [ ] `feishu_config.json` 已配置真实值
- [ ] 本地能生成 `crm_packet.json`
- [ ] 能生成 `customer_table_rows.json` 和 `opportunity_snapshot_row.json`
- [ ] `inspect-feishu-bitable` 能读到表结构
- [ ] `sync-feishu-bitable --dry-run` 正常
- [ ] 真实写入成功
- [ ] 飞书里能看到 Customers 与 OpportunitySnapshots 结果

---

## 11. 常见问题

### `tenant_access_token missing`
通常是：
- App ID / App Secret 错误
- 飞书应用权限未开通

### `Missing customer table id` / `Missing opportunity table id`
通常是：
- `feishu_config.json` 缺字段
- 字段名写错

### `Feishu API failed`
通常需要排查：
- 表 ID 错误
- 字段名不一致
- 字段类型不匹配
- 应用无权限

### 只生成 JSON，没真正写表
先确认：
- 是不是跑了纯本地命令
- 是不是启用了 `--dry-run`
- 是不是未提供有效写表配置

### Customers 旧画像被错误覆盖
优先检查：
- 本轮输入是否只有弱值
- 最终写入前是否正确应用“弱值保护”
- `沟通风格` / `风险顾虑` 是否按合并策略写回
