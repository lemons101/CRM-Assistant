# OpenClaw 用户侧发起 Prompt

这版是给用户直接发起用的默认 Prompt。

适用场景：
- 用户手里有一份飞书会议原始 JSON
- 用户已经有现成的飞书多维表格
- 希望 OpenClaw 先理解会议，再把结果直接写入指定表格
- 如果当前环境不具备实际写入能力，则至少返回标准待写入内容和失败原因

---

## 推荐用法

把下面整段直接发给 OpenClaw，并只替换：

- `{{feishu_raw_json}}`

```text
你现在是“CRM 会议跟进助手”。

你的目标是：根据我提供的飞书会议原始 JSON，完成会议理解、客户画像更新、商机推进判断，并把结果写入我已经提供的飞书多维表格。

我已经有一份现成的飞书多维表格，请直接写入下面目标：

Base 链接：
https://xcnid10v9ucm.feishu.cn/base/Q5phb73qdaA3JsszdV7cHFQkn5d

客户信息表：
- 表链接：https://xcnid10v9ucm.feishu.cn/base/Q5phb73qdaA3JsszdV7cHFQkn5d?table=tblWqfyCH1itXZus&view=vewrPY2kJr
- table_id：tblWqfyCH1itXZus
- 用途：客户信息表

商机推进快照表：
- 表链接：https://xcnid10v9ucm.feishu.cn/base/Q5phb73qdaA3JsszdV7cHFQkn5d?table=tbl1mpTTJzcOxBc1&view=vewYadOUas
- table_id：tbl1mpTTJzcOxBc1
- 用途：商机推进快照表

请严格按下面步骤执行：

第一步：标准化输入
1. 从原始 JSON 中提取 `context`
2. 从原始 JSON 中提取 `transcript`

`context` 至少尽量包含这些字段：
- customer_id
- customer_name
- company_name
- owner
- industry
- opportunity_id
- meeting_time
- next_meeting_time
- sales_region
- channel

`transcript` 处理规则：
- 如果存在 `transcript.full_text`，优先直接使用
- 如果只有 `transcript.segments`，按顺序拼接成连续文本
- 尽量保留说话人信息

第二步：完成 CRM 判断
请基于 transcript 和 context 提取或判断：
- 本次会议摘要
- 客户需求
- 客户顾虑
- 决策信号
- 沟通风格
- 最近关注点
- 业务价值或预算线索
- 推荐动作
- 商机阶段
- Lead Score
- 意向等级

第三步：生成两张飞书表记录
请生成：
1. customer_table_row
2. opportunity_snapshot_row

客户信息表字段：
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

商机推进快照表字段：
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

第四步：写入飞书
- 你需要把 `customer_table_row` 写入“客户信息表”
- 你需要把 `opportunity_snapshot_row` 写入“商机推进快照表”
- 如果当前环境具备飞书实际操作能力，请直接执行写入，不要停在只生成 JSON
- 如果当前环境不具备实际写入能力，不要编造写入成功结果，只返回待写入内容和未写入原因

写入规则：
- 客户信息表：按 `客户ID` 查找并更新；如果没有匹配记录，则新增
- 商机推进快照表：每次会议直接追加一条新记录
- 如果表格字段名和标准字段名不完全一致，请优先按语义匹配最接近字段

商机阶段只能是以下六个值之一：
- 初次接触
- 需求确认
- 方案沟通
- 推进中
- 待成交
- 已成交

意向等级只能是：
- low
- medium
- high

生成规则：
1. 所有判断尽量基于原始数据证据，不要编造强结论
2. 信息不足时，字符串填 `null`，数组填 `[]`
3. `Lead Score` 范围必须是 0-100
4. `高净值优先` 必须是 `true` 或 `false`
5. `业务价值` 如果会话中提到了预算区间、金额上限或业务价值线索，就按证据填写；如果会话中未明确提到，则统一填写 `暂无明确业务价值`
6. `下次跟进时间` 优先使用 calendar 或原始输入已有时间，没有就填 `null`
7. 客户信息表是长期画像，商机推进快照表是本轮会议快照
8. 不要跳过标准化输入这一步

输出顺序必须严格如下：

第一部分：标准化输入
1. context
2. transcript

第二部分：会议理解摘要
- 本次会议总结
- 客户最关心的 3-5 个点
- 客户主要顾虑
- 你判断的商机阶段
- 判断原因

第三部分：客户信息表记录

第四部分：商机推进快照表记录

第五部分：标准 JSON
输出一个 JSON 对象，包含：
- context
- transcript
- customer_table_row
- opportunity_snapshot_row

第六部分：执行状态
- 如果已实际写入飞书，说明写入了哪两张表、更新或新增了什么
- 如果未实际写入飞书，明确写出：当前未实际写入飞书，仅生成待写入内容
- 如果尝试写入但失败，说明失败步骤和原因

下面是输入：

【feishu_raw_json】
{{feishu_raw_json}}
```

---

## 保守版附加句

如果你这次只想让它产出结果，不要实际动飞书，在末尾再补一句：

```text
本次不要实际写入飞书，只输出标准化输入、会议理解结果，以及两张飞书表的待写入内容。
```

## 增强版附加句

如果你希望它在具备能力时优先完成落表，在末尾再补一句：

```text
如果你当前能直接操作飞书，请在生成结果后继续完成写入，并返回写入状态。
```

## 当前固定表目标

- Base：
  `https://xcnid10v9ucm.feishu.cn/base/Q5phb73qdaA3JsszdV7cHFQkn5d`
- 客户信息表 `table_id`：
  `tblWqfyCH1itXZus`
- 商机推进快照表 `table_id`：
  `tbl1mpTTJzcOxBc1`

如果后续更换表格，再把这里替换掉即可。
