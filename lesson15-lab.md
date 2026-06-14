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

## 1. 当前真实在用的飞书表

当前项目已经实际对接并验证过这套飞书多维表格：

- `app_token`: `BEwNbIlMfaeNFcs3SZWc7SjInvh`
- `Customers.table_id`: `tblCq566fSxHlwkG`
- `OpportunitySnapshots.table_id`: `tblTuZySbF8dA1OP`

### 1.1 Customers 当前真实字段
- 客户ID（主字段）
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
- 最后更新时间（日期时间）
- 数据来源
- 职务

### 1.2 OpportunitySnapshots 当前真实字段
- 商机ID（主字段）
- 客户ID
- 客户名称
- 客户公司
- 机会名称
- 商机描述
- 当前阶段
- Lead Score（数字）
- 意向等级
- 高净值优先（复选框）
- 销售区域
- 业务价值
- 推荐动作
- 最新进展
- 下次跟进时间（日期时间）
- 最近会议时间（日期时间）
- 商机负责人
- 数据来源

补充规则：
- `机会名称` 优先采用 **`客户公司 - 项目主题`**
- 不要把客户名称再硬拼到最前面
- 客户身份信息已经由 `客户名称`、`客户公司`、`客户ID` 单独承载

### 1.3 已验证写入过的真实记录
Customers 已验证存在：
- 张琪
- 李昊
- 王拓

OpportunitySnapshots 已验证存在：
- `O-BBA6BE6702`（需求确认）
- `O-133EBBF3FB`（方案沟通）

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

## 3. 配置本地 app 写表参数（可选）

如果你想先保留 CLI 侧 app 写表能力，可以在项目目录创建：

`/root/projects/CRM-Assistant/feishu_config.json`

示例：

```json
{
  "app_id": "cli_xxxxxxxx",
  "app_secret": "xxxxxxxx",
  "app_token": "BEwNbIlMfaeNFcs3SZWc7SjInvh",
  "customer_table_id": "tblCq566fSxHlwkG",
  "opportunity_snapshot_table_id": "tblTuZySbF8dA1OP"
}
```

注意：
- 这是本地配置文件，不要提交到 git
- 仓库已默认忽略 `feishu_config.json`
- 当前真实环境中，**app 权限链路可能会遇到 403**；不要把“app token 可读表”误当成“app 一定可写表”

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

如果尝试走 app 权限写表：

```bash
python scripts/crm_assistant.py ingest-docx-to-bitable \
  --docx-path ./meeting.docx \
  --output-dir ./runtime/your_case \
  --config-path ./feishu_config.json \
  --sync-feishu
```

### 4.2 飞书文档 Markdown 入口

```bash
python scripts/crm_assistant.py ingest-feishu-doc-to-bitable \
  --doc-markdown-path ./source_doc.md \
  --output-dir ./runtime/your_case
```

### 4.3 飞书会议原始 JSON 入口

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

### 6.1 走 CLI / app 权限检查

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

### 6.2 走用户权限检查（当前更贴近真实）
如果 app 权限链路不稳，直接用用户权限读取当前表字段和记录，也已经验证可行。

当前真实结果已经确认：
- Customers 主字段是 `客户ID`
- OpportunitySnapshots 主字段是 `商机ID`
- `Lead Score` 是数字字段
- `高净值优先` 是复选框
- 时间字段都使用日期时间类型

---

## 7. dry-run 写表验证

如果你仍然要测试 CLI / app 权限链路，推荐先用 `sync-feishu-bitable` 做 dry-run：

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

## 8. 当前最稳的真实落表方式：用户权限写入

当前项目已经验证过：
- **app 权限写表可能遇到 `403 Forbidden`**
- 但**用户权限写入已经真实跑通**

因此当前最稳的真实使用姿势是：

```text
Word / DOCX
  -> CRM Assistant 结构化处理
  -> 读取 customer_table_rows.json / opportunity_snapshot_row.json
  -> 用用户权限写入 Customers / OpportunitySnapshots
```

### 已经验证跑通的真实结果
- 第一份 Word：
  - Customers 新增：张琪、李昊
  - OpportunitySnapshots 新增：`O-BBA6BE6702`（需求确认）
- 第二份 Word：
  - Customers 更新：张琪、李昊
  - Customers 新增：王拓
  - OpportunitySnapshots 新增：`O-133EBBF3FB`（方案沟通）

### 这条链路验证过的规则
- 弱值不覆盖强值
- `沟通风格` / `风险顾虑` 合并更新
- 优先按 `客户ID` 命中已有客户
- 多客户会议拆成多条 Customers 记录 + 一条 OpportunitySnapshots 快照

---

## 9. 当前项目里的关键业务规则

### 9.1 Customers 更新规则
- 如果本轮值是弱值：`未明确` / `未知` / `待确认` / 空值
- 不要覆盖历史上已经明确的旧值

### 9.2 合并字段
以下字段采用“旧值保留 + 新值补充 + 去重”：
- `沟通风格`
- `风险顾虑`

### 9.3 Customers 命中规则
- 优先按 `客户ID` 命中已有飞书记录
- 缺少正式 ID 时，再回退 `客户名称 + 客户公司`

### 9.4 OpportunitySnapshots
- 每轮会议追加一条快照
- 不覆盖历史

### 9.5 商机ID 继承规则
- 同一个客户、同一个项目、不同阶段推进：优先沿用同一个 `商机ID`
- 不同阶段变化应通过 `OpportunitySnapshots` 追加快照来表达，而不是每轮都新建商机
- 只有明确是新项目 / 新预算 / 新需求线时，才更适合生成新的 `商机ID`

### 9.6 时间字段
真正写飞书前，日期时间字段应按字段类型转换成毫秒时间戳。

---

## 10. 验收清单

- [ ] 项目部署成功
- [ ] `python scripts/crm_assistant.py --help` 正常
- [ ] 当前真实飞书表参数确认无误
  - [ ] `app_token = BEwNbIlMfaeNFcs3SZWc7SjInvh`
  - [ ] `Customers.table_id = tblCq566fSxHlwkG`
  - [ ] `OpportunitySnapshots.table_id = tblTuZySbF8dA1OP`
- [ ] 本地能生成 `crm_packet.json`
- [ ] 能生成 `customer_table_rows.json` 和 `opportunity_snapshot_row.json`
- [ ] 字段检查通过
- [ ] dry-run 结果合理（如仍测试 app 权限链路）
- [ ] 用户权限写表成功
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

### `Feishu API failed` / `403 Forbidden`
当前真实环境里已经验证过，这通常说明：
- app 能读，但不能写
- 应用权限没开齐
- Base / 表未授权给应用

这时不要死磕 app 写入，优先切到：
- **用户权限读取 / 用户权限写入**

### 只生成 JSON，没真正写表
先确认：
- 是不是跑了纯本地命令
- 是不是启用了 `--dry-run`
- 是不是未提供有效写表配置
- 是不是已经改走用户权限链路但还没执行写表

### Customers 旧画像被错误覆盖
优先检查：
- 本轮输入是否只有弱值
- 最终写入前是否正确应用“弱值保护”
- `沟通风格` / `风险顾虑` 是否按合并策略写回
