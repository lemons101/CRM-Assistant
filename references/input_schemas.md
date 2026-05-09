# 输入结构说明

当前项目支持两层输入：

## 1. 业务处理层输入

这是 `process_transcript.ps1` 直接消费的输入：

- `transcript.txt`
- `context.json`

其中：

- `transcript.txt`：会议转录文本
- `context.json`：从 CRM、日历、会议元信息中补齐的业务上下文

建议字段：

- `customer_id`
- `customer_name`
- `owner`
- `industry`
- `opportunity_id`
- `current_stage`
- `meeting_time`
- `next_meeting_time`
- `channel`

## 2. 飞书原始输入层

这是更接近真实接入飞书会议时的输入。推荐标准化为：

### `feishu_meeting_raw.json`

顶层建议字段：

- `source`
- `meeting`
- `participants`
- `transcript`
- `calendar`
- `crm_binding`

### meeting

- `meeting_id`
- `title`
- `start_time`
- `end_time`
- `host_user_id`
- `meeting_url`
- `calendar_event_id`

### participants

数组，每个元素可包含：

- `user_id`
- `name`
- `role`：`internal` / `external` / `guest` / `host`
- `company`
- `industry`

### transcript

两种方式至少提供一种：

- `full_text`
- `segments`

`segments` 元素建议包含：

- `speaker`
- `text`
- `start_ms`
- `end_ms`

### calendar

- `next_meeting_time`

### crm_binding

这是项目内部的“业务绑定补充层”，用于把飞书会议和 CRM 里的客户/商机关联起来。建议字段：

- `customer_id`
- `customer_name`
- `owner`
- `industry`
- `opportunity_id`
- `current_stage`

## 输入转换关系

项目中通过 `scripts/build_context_from_feishu.ps1` 完成以下转换：

```text
feishu_meeting_raw.json
  -> transcript.txt
  -> context.json
  -> process_transcript.ps1
```

这一步的意义是：

- 飞书提供会议事实和转录文本
- CRM / 多维表格提供客户和商机上下文
- 项目把两者合并成稳定的内部输入格式
