# 第 15 节实验手册：让每一场高价值会议，自动沉淀为可经营的 CRM 资产

> 配套课程：AI 业务流架构师 · 第 15 节《CRM Assistant 会议商机推进与飞书落表》
> 预计耗时：30-45 分钟
> 操作方式：全程在飞书 DM 里和龙虾对话完成
> 目标：安装 CRM Assistant，配置飞书表，把仓库自带的 Word 会议纪要通过**用户侧权限**写入飞书 CRM 两张表

---

## 0. 开始前确认

| # | 物料 | 备注 |
|---|---|---|
| 1 | 龙虾可正常对话 | 飞书 DM 发一句话能回复 |
| 2 | CRM Assistant 仓库 | `https://github.com/lemons101/CRM-Assistant` |
| 3 | 飞书多维表格权限 | 能创建 Base / 表 / 字段 |
| 4 | 飞书应用凭据 | `FEISHU_APP_ID`、`FEISHU_APP_SECRET` |
| 5 | 测试会议纪要 | 仓库自带 `assets/meeting_docs/*.docx` |

本实验只走主线：**Word/DOCX 会议纪要 -> CRM Assistant -> 飞书 Customers / OpportunitySnapshots**。

注意：真实写入飞书时，强调使用**用户侧写入**。也就是让龙虾用当前用户已授权的飞书能力完成落表，不要把写入理解成纯 app/bot 身份自动写表。App 配置主要用于定位和检查飞书 Base / 表结构；如果 app 身份写表遇到权限问题，应切到用户侧写入。

---

## 1. 创建飞书多维表格（发给龙虾）

在飞书 DM 里发送：

```text
请帮我创建一个 CRM Assistant Demo 用的飞书多维表格。

要求：
1. 新建一个 Bitable Base
2. 创建两张表：
   - Customers
   - OpportunitySnapshots
3. 字段名称必须和下面完全一致
4. Lead Score 用数字字段
5. 高净值优先用复选框字段
6. 最后更新时间、下次跟进时间、最近会议时间用日期时间字段
7. 其他字段用文本字段

Customers 字段：
客户ID、客户名称、客户公司、行业、职务、MBTI、是否单身、沟通风格、成交阻力、价格敏感程度、风险顾虑、客户画像摘要、客户负责人、最后更新时间、数据来源

OpportunitySnapshots 字段：
商机ID、客户ID、客户名称、客户公司、机会名称、商机描述、当前阶段、Lead Score、意向等级、高净值优先、销售区域、业务价值、推荐动作、最新进展、下次跟进时间、最近会议时间、商机负责人、数据来源

创建完成后请返回：
1. Base 链接
2. app_token
3. Customers 的 table_id
4. OpportunitySnapshots 的 table_id
```

把龙虾返回的 `app_token` 和两个 `table_id` 留好，后面写 `.env.local` 要用。

---

## 2. 安装到龙虾目录（发给龙虾）

把下面这段发给龙虾。路径可以按你的环境调整；如果你的龙虾统一把技能放在别的目录，让龙虾用实际目录。

```text
请帮我安装 CRM Assistant 到龙虾可使用的项目目录。

仓库地址：
https://github.com/lemons101/CRM-Assistant

要求：
1. 如果本地还没有项目，请 clone 这个仓库
2. 如果本地已有项目，请 git pull 更新到 main 最新版本
3. 进入 CRM-Assistant 项目根目录
4. 安装 requirements.txt
5. 运行 python scripts/crm_assistant.py --help，确认 CLI 可用
6. 确认仓库里存在 assets/meeting_docs 目录，并且里面有 .docx 测试会议纪要

完成后告诉我：
1. 项目实际安装目录
2. 当前最新 commit
3. CLI 是否可用
```

---

## 3. 配置 `.env.local`（发给龙虾）

把占位符替换成你自己的真实值后，发给龙虾：

```text
请在 CRM Assistant 项目根目录创建或更新 .env.local。

请写入以下内容：

FEISHU_APP_ID=cli_xxxxxxxx
FEISHU_APP_SECRET=xxxxxxxx
FEISHU_BITABLE_APP_TOKEN=xxxxxxxx
FEISHU_CUSTOMER_TABLE_ID=tblxxxxxxxx
FEISHU_OPPORTUNITY_TABLE_ID=tblxxxxxxxx

要求：
1. .env.local 只保存在本地，不要提交到 git
2. 写完后确认文件存在
3. 不要在回复里完整展示 FEISHU_APP_SECRET
4. 后续运行 CRM Assistant 时默认读取这个 .env.local
```

---

## 4. 检查飞书表连接（发给龙虾）

```text
请用 CRM Assistant 检查飞书多维表格连接是否正常。

要求：
1. 进入 CRM Assistant 项目根目录
2. 使用项目根目录的 .env.local
3. 运行 inspect-feishu-bitable
4. 输出保存到 runtime/lab15_inspect

完成后告诉我：
1. 是否能拿到 tenant_access_token
2. 是否能读取 Base 里的表
3. Customers 表是否存在
4. OpportunitySnapshots 表是否存在
5. 如果失败，请返回完整报错
```

如果这一步失败，先检查 `.env.local`、飞书应用权限、Base 是否授权给应用。

---

## 5. 运行 DOCX 测试并 dry-run（发给龙虾）

先 dry-run，不真实写表。

```text
请用 CRM Assistant 处理仓库自带的 Word 会议纪要，并做一次飞书写表 dry-run。

要求：
1. 进入 CRM Assistant 项目根目录
2. 使用这份测试文档：
   assets/meeting_docs/中国平安龙虾盒子需求梳理会.docx
3. 执行 ingest-docx-to-bitable
4. 使用 .env.local
5. 加上 --dry-run
6. 输出目录放到 runtime/lab15_docx_dry

完成后告诉我：
1. 是否生成 runtime/lab15_docx_dry/process/crm_packet.json
2. 是否生成 runtime/lab15_docx_dry/process/customer_table_rows.json
3. 是否生成 runtime/lab15_docx_dry/process/opportunity_snapshot_row.json
4. 是否生成 runtime/lab15_docx_dry/sync/feishu_sync_result.json
5. dry_run 是否为 true
6. 本次准备写入的客户名称、机会名称、当前阶段、Lead Score
```

看到 `dry_run=true` 代表只是预演，飞书表里还不会出现记录。

---

## 6. 真实写入飞书（发给龙虾）

dry-run 正常后，再真实写表：

```text
请用 CRM Assistant 把仓库自带的 Word 会议纪要真实写入飞书多维表格。

要求：
1. 进入 CRM Assistant 项目根目录
2. 使用这份测试文档：
   assets/meeting_docs/中国平安龙虾盒子需求梳理会.docx
3. 执行 ingest-docx-to-bitable
4. 使用 .env.local
5. 不要加 --dry-run
6. 写入飞书时使用用户侧权限，不要用无写权限的 app/bot 身份硬写
7. 输出目录放到 runtime/lab15_docx_write

完成后告诉我：
1. 是否写入成功
2. 是否确认是用户侧写入
3. Customers 是 created / updated / batch 中的哪一种
4. OpportunitySnapshots 是 created 还是 updated
5. 本次写入的客户名称、机会名称、当前阶段、Lead Score、推荐动作
6. 如果失败，请返回完整报错
```

完成后打开飞书多维表格，只看最终效果：
- Customers 里是否出现客户画像
- OpportunitySnapshots 里是否出现商机推进记录

---

## 7. 再跑一份推进阶段文档（可选，发给龙虾）

如果要展示同一客户后续阶段推进，可以再跑一份仓库自带的后续会议文档：

```text
请用 CRM Assistant 再处理一份后续阶段的 Word 会议纪要，并真实写入飞书。

要求：
1. 进入 CRM Assistant 项目根目录
2. 使用这份测试文档：
   assets/meeting_docs/中国平安龙虾盒子方案沟通会.docx
3. 执行 ingest-docx-to-bitable
4. 使用 .env.local
5. 写入飞书时继续使用用户侧权限
6. 输出目录放到 runtime/lab15_docx_write_round2

完成后告诉我：
1. 是否写入成功
2. Customers 是否复用了已有客户并更新画像
3. OpportunitySnapshots 写入结果是什么
4. 当前阶段、Lead Score、推荐动作是否和第一份文档不同
```

然后回到飞书表观察：
- Customers 是否更新了客户画像
- OpportunitySnapshots 是否体现了推进阶段变化

---

## 8. 验收检查清单

- [ ] 龙虾能正常对话
- [ ] CRM Assistant 已安装到龙虾可访问目录
- [ ] `python scripts/crm_assistant.py --help` 正常
- [ ] `assets/meeting_docs` 中存在 Word 测试文档
- [ ] 飞书 Base 已创建
- [ ] Customers 字段完整
- [ ] OpportunitySnapshots 字段完整
- [ ] `.env.local` 已配置
- [ ] `inspect-feishu-bitable` 能读取飞书表
- [ ] dry-run 成功生成 `feishu_sync_result.json`
- [ ] 真实写表通过用户侧权限完成
- [ ] 飞书 Customers 能看到客户画像
- [ ] 飞书 OpportunitySnapshots 能看到商机推进记录

---

## 9. 常见问题速查

| 龙虾报的错 | 可能原因 | 你发什么 |
|---|---|---|
| `Missing Feishu app token` | `.env.local` 里没有 `FEISHU_BITABLE_APP_TOKEN` | “请检查 .env.local 里的 FEISHU_BITABLE_APP_TOKEN” |
| `Missing customer table id` | 缺少 `FEISHU_CUSTOMER_TABLE_ID` | “请检查 .env.local 里的 FEISHU_CUSTOMER_TABLE_ID” |
| `Missing opportunity snapshot table id` | 缺少 `FEISHU_OPPORTUNITY_TABLE_ID` | “请检查 .env.local 里的 FEISHU_OPPORTUNITY_TABLE_ID” |
| `tenant_access_token missing` | App ID / Secret 错误或权限不足 | “请核对 FEISHU_APP_ID 和 FEISHU_APP_SECRET” |
| `403 Forbidden` | app/bot 身份没有写表权限，或 Base 未授权 | “请改用用户侧写入；如果仍需 app 检查，请把 Base 授权给应用” |
| 找不到 DOCX | 没有拉到最新仓库，或路径不对 | “请 git pull，并列出 assets/meeting_docs 下的文件” |
| dry-run 成功但飞书没记录 | dry-run 不会真实写表 | “请去掉 --dry-run 后再执行一次” |

---

## 实验记录

| # | 发生在哪一步 | 预期行为 | 实际行为 | 解决方法 |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

> 本节实验只要求跑通主链路：安装 Skill、配置 `.env.local`、处理 Word 会议纪要，并通过用户侧权限确认飞书两张表出现结果。
