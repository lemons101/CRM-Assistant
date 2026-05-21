# Lesson 15 Lab：CRM Assistant 落地流程

目标：

```text
让龙虾部署 CRM-Assistant
并把会议结果写入我们预先创建好的飞书多维表格
```

## 一、标准流程

只讲这一条链路：

1. 先让龙虾创建飞书多维表格
2. 拿到 `base` 链接、`app_token`、两张表的 `table_id`
3. 让龙虾部署 `CRM-Assistant`
4. 用 `CRM-Assistant` 把样本写入飞书

核心原则：

- Prompt 只是入口
- 真正的能力主体是 `CRM-Assistant`
- 真正写表发生在：**部署完成 + 飞书配置完成 + 执行写表命令之后**

---

## 二、先让龙虾建飞书表

把下面这段直接发给龙虾：

```text
请你在我的飞书中创建一个 CRM Assistant Demo 的多维表格 Base。

创建两张表：
1. Customers
2. OpportunitySnapshots

Customers 字段：
- 客户ID
- 客户名称
- 客户公司
- 行业
- 家庭标签
- 家庭备注
- 商业偏好
- 风险顾虑
- 沟通风格
- 决策信号
- 最近关注点
- 客户画像摘要
- 客户负责人
- 最后更新时间
- 数据来源

OpportunitySnapshots 字段：
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

创建完成后，必须返回给我：
1. Base 链接
2. app_token
3. Customers 的 table_id
4. OpportunitySnapshots 的 table_id
```

---

## 三、再让龙虾部署 Skill

把下面这段发给龙虾：

```text
请帮我部署并验证 CRM-Assistant。

仓库地址：
https://github.com/lemons101/CRM-Assistant.git

部署目录：
/root/projects/CRM-Assistant

请执行：

mkdir -p /root/projects
cd /root/projects
git clone https://github.com/lemons101/CRM-Assistant.git
cd /root/projects/CRM-Assistant

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

python scripts/crm_assistant.py --help

再跑一遍样本：

python scripts/crm_assistant.py build-context-from-feishu \
  --raw-input-path assets/feishu_raw/pingan_longxiahezi_need_confirmation.json \
  --output-dir runtime/lab15_probe/build

python scripts/crm_assistant.py process-transcript \
  --transcript-path runtime/lab15_probe/build/transcript.txt \
  --context-path runtime/lab15_probe/build/context.json \
  --output-dir runtime/lab15_probe/process

最后请告诉我：
1. 是否部署成功
2. 是否跑通
3. 当前商机阶段、Lead Score、推荐动作
4. 是否已经生成 customer_table_row.json 和 opportunity_snapshot_row.json
```

---

## 四、什么时候真正写飞书

不是部署完就写。

真正写飞书发生在这三个条件都满足后：

1. `CRM-Assistant` 已部署成功
2. 已拿到飞书的 `app_token` 和两张表的 `table_id`
3. 已配置飞书应用 `App ID / App Secret`

然后执行写表命令，才会真的写进去。

---

## 五、最后让龙虾写入飞书

把下面这段发给龙虾：

```text
请使用 CRM-Assistant，把结果写入我之前创建好的飞书多维表格。

要求：
1. 先检查飞书表结构
2. 核对 Customers 和 OpportunitySnapshots 的 table_id
3. 先做一次 dry-run，不要真实写入
4. 确认无误后，再真实写入

请按这个顺序执行：

第一步：检查表结构
python scripts/crm_assistant.py inspect-feishu-bitable ...

第二步：dry-run
python scripts/crm_assistant.py sync-feishu-bitable ...

第三步：真实写入
python scripts/crm_assistant.py ingest-feishu-raw-to-bitable ...

执行完成后，用中文返回：
1. 是否写入成功
2. Customers 是新增还是更新
3. OpportunitySnapshots 是否追加成功
4. 本次写入的客户名称、阶段、Lead Score、推荐动作
5. 如果失败，返回失败命令和完整报错
```

---

## 六、一句话讲法

这节课就一句话：

```text
先让龙虾建飞书表
再让龙虾部署 CRM-Assistant
最后由 CRM-Assistant 把会议结果写进飞书
```
