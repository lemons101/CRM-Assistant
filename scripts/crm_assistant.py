from __future__ import annotations

import argparse
import json
import re
from collections import OrderedDict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any


VALID_INTENT_LEVELS = ["low", "medium", "high"]
VALID_STAGES = ["初次接触", "需求确认", "方案沟通", "推进中", "待成交"]
VALID_CHANNELS = ["微信", "邮件", "飞书消息"]


def skill_root() -> Path:
    return Path(__file__).resolve().parent.parent


def read_text(path: str | Path) -> str:
    return Path(path).read_text(encoding="utf-8-sig")


def write_text(path: str | Path, value: str) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value, encoding="utf-8-sig")


def read_json(path: str | Path) -> Any:
    return json.loads(read_text(path))


def write_json(path: str | Path, value: Any) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8-sig")


def get_object_value(obj: Any, property_name: str, default: Any = None) -> Any:
    if obj is None:
        return default
    if isinstance(obj, dict):
        value = obj.get(property_name, default)
    else:
        value = getattr(obj, property_name, default)
    return default if value is None else value


def resolve_str(path: str | Path | None) -> str | None:
    if not path:
        return None
    return str(Path(path).resolve())


def get_lines(text: str) -> list[str]:
    return [line.strip() for line in re.split(r"\r?\n", text) if line.strip()]


def get_matched_lines(lines: list[str], patterns: list[str]) -> list[str]:
    results: list[str] = []
    for line in lines:
        for pattern in patterns:
            if re.search(pattern, line):
                if line not in results:
                    results.append(line)
                break
    return results


def get_labels(text: str, mapping: dict[str, str]) -> list[str]:
    labels: list[str] = []
    for label, pattern in mapping.items():
        if re.search(pattern, text):
            labels.append(label)
    deduped: list[str] = []
    for item in labels:
        if item not in deduped:
            deduped.append(item)
    return deduped


def join_values(values: list[Any] | None, fallback: str = "暂无") -> str:
    if not values:
        return fallback
    items: list[str] = []
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text and text not in items:
            items.append(text)
    return "；".join(items) if items else fallback


def parse_budget_max(text: str) -> int:
    max_value = 0
    for match in re.finditer(r"(\d+)\s*到\s*(\d+)\s*万", text):
        max_value = max(max_value, int(match.group(2)))
    for match in re.finditer(r"(预算|金额超过)\D{0,8}(\d+)\s*万", text):
        max_value = max(max_value, int(match.group(2)))
    return max_value


def clamp_score(value: int) -> int:
    return max(0, min(100, value))


def parse_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    return datetime.fromisoformat(text)


def isoformat_or_none(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def get_business_value(text: str) -> str | None:
    for pattern in [
        r"预算大概在\s*(\d+)\s*到\s*(\d+)\s*万",
        r"(\d+)\s*到\s*(\d+)\s*万",
    ]:
        match = re.search(pattern, text)
        if match:
            return f"{match.group(1)}-{match.group(2)}万"
    match = re.search(r"金额在\s*(\d+)\s*万以内", text)
    if match:
        return f"{match.group(1)}万以内"
    match = re.search(r"预算[^。；\n]{0,10}(\d+)\s*万", text)
    if match:
        return f"约 {match.group(1)} 万"
    return None


def get_sales_region(context: dict[str, Any], text: str) -> str | None:
    context_region = get_object_value(context, "sales_region")
    if context_region and str(context_region).strip():
        return str(context_region).strip()
    for keyword, label in [
        ("华北", "华北地区"),
        ("华东", "华东地区"),
        ("华南", "华南地区"),
        ("西南", "西南地区"),
        ("西北", "西北地区"),
        ("全国", "全国"),
    ]:
        if keyword in text:
            return label
    return None


def get_transcript_text(raw: dict[str, Any]) -> str:
    transcript = raw.get("transcript", {}) or {}
    full_text = transcript.get("full_text")
    if full_text and str(full_text).strip():
        return str(full_text).strip()
    segments = transcript.get("segments") or []
    lines: list[str] = []
    for segment in segments:
        speaker = str(segment.get("speaker") or "发言人").strip() or "发言人"
        text = str(segment.get("text") or "").strip()
        if text:
            lines.append(f"{speaker}：{text}")
    if lines:
        return "\n".join(lines)
    raise ValueError("No transcript.full_text or transcript.segments found in raw input.")


def get_first_participant_by_role(participants: list[dict[str, Any]], roles: list[str]) -> dict[str, Any] | None:
    for participant in participants:
        if participant.get("role") in roles:
            return participant
    return None


def build_context_from_feishu(raw_input_path: str | Path, output_dir: str | Path, context_file_name: str = "context.json", transcript_file_name: str = "transcript.txt") -> dict[str, Any]:
    raw = read_json(raw_input_path)
    participants = list(raw.get("participants") or [])
    crm_binding = raw.get("crm_binding") or {}
    external_participant = get_first_participant_by_role(participants, ["external", "guest", "customer"])
    internal_participant = get_first_participant_by_role(participants, ["internal", "host", "owner"])
    transcript_text = get_transcript_text(raw)

    customer_name = get_object_value(crm_binding, "customer_name")
    if customer_name is None and external_participant is not None:
        customer_name = external_participant.get("name")
    company_name = get_object_value(crm_binding, "company_name")
    if company_name is None and external_participant is not None:
        company_name = external_participant.get("company")
    owner = get_object_value(crm_binding, "owner")
    if owner is None and internal_participant is not None:
        owner = internal_participant.get("name")
    industry = get_object_value(crm_binding, "industry")
    if industry is None and external_participant is not None:
        industry = external_participant.get("industry")

    meeting = raw.get("meeting") or {}
    calendar = raw.get("calendar") or {}
    context = OrderedDict([
        ("customer_id", get_object_value(crm_binding, "customer_id")),
        ("customer_name", customer_name),
        ("company_name", company_name),
        ("owner", owner),
        ("industry", industry),
        ("opportunity_id", get_object_value(crm_binding, "opportunity_id")),
        ("current_stage", get_object_value(crm_binding, "current_stage", "未知")),
        ("sales_region", get_object_value(crm_binding, "sales_region")),
        ("meeting_time", meeting.get("start_time")),
        ("next_meeting_time", calendar.get("next_meeting_time")),
        ("channel", "飞书会议纪要导入"),
        ("source_meeting_id", meeting.get("meeting_id")),
        ("source_event_id", meeting.get("calendar_event_id")),
        ("source_title", meeting.get("title")),
    ])

    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    context_path = output / context_file_name
    transcript_path = output / transcript_file_name
    write_json(context_path, context)
    write_text(transcript_path, transcript_text)

    result = OrderedDict([
        ("raw_input_path", resolve_str(raw_input_path)),
        ("generated_context", resolve_str(context_path)),
        ("generated_transcript", resolve_str(transcript_path)),
    ])
    write_json(output / "build_result.json", result)
    return result


def process_transcript(transcript_path: str | Path, context_path: str | Path, output_dir: str | Path) -> dict[str, Any]:
    context = read_json(context_path)
    transcript = read_text(transcript_path)
    lines = get_lines(transcript)
    company_name = get_object_value(context, "company_name")
    industry_name = get_object_value(context, "industry")
    source_channel = get_object_value(context, "channel", "手动导入")

    customer_lines = [line for line in lines if re.search(r"^(客户|张总|陈女士|刘总|孙总|客户A|客户B|客户C|客户D)[:：]", line)]
    if not customer_lines:
        customer_lines = lines[:]
    all_text = " ".join(lines)
    customer_text = " ".join(customer_lines)

    need_lines = get_matched_lines(customer_lines, ["希望", "想", "需要", "重点", "最好", "计划", "目标", "关注", "更在意", "最大的痛点", "先了解", "有意思"])
    concern_lines = get_matched_lines(customer_lines, ["担心", "顾虑", "怕", "不太喜欢", "不喜欢", "不希望", "合规", "隐私", "安全", "风险", "别太复杂", "不要太长", "别搞太重", "培训周期不要太长"])
    next_action_lines = get_matched_lines(lines, ["下周", "下次", "再约", "安排", "发我", "发邮件", "邮箱", "邮件", "报价", "方案", "演示", "见面", "周一", "周二", "周三", "周四", "周五", "今晚", "明天", "试点"])

    business_preference_map = OrderedDict([
        ("稳健回报优先", "稳健|保守|本金安全|保值|流动性"),
        ("效率优先", "效率|提效|自动化|减少人工|统一起来|打通"),
        ("品牌与可靠性交付", "稳定|成熟|可靠|案例|长期服务|别上线后频繁折腾"),
        ("小步试点", "试点|先跑一个|先覆盖|POC|先做一期"),
        ("偏好多维表格/飞书协同", "飞书|多维表格"),
        ("私密高触达跟进", "微信|私聊|及时沟通"),
    ])
    risk_concern_map = OrderedDict([
        ("价格敏感", "预算|价格|成本|报价"),
        ("交付风险", "实施|交付|上线|周期拖长|培训周期"),
        ("合规与数据安全", "合规|数据安全|权限|隐私|资金进出"),
        ("效果不确定", "效果|ROI|值不值|产出"),
        ("时间窗口紧张", "本周|下周|本月|月底|季度内|尽快|周五之前|明天"),
    ])
    communication_style_map = OrderedDict([
        ("偏好微信触达", "微信"),
        ("偏好简洁表达", "简洁|不要太长|别太长|三点结论|直接"),
        ("偏好先看材料", "先发|先看|发我|材料|方案发我|清单"),
        ("偏好多方共同沟通", "一起看|一起聊|都参与|拉上"),
        ("偏好邮件接收", "发邮件|发我邮箱|邮箱给我|邮件给我|今晚发我邮箱"),
    ])
    decision_signal_map = OrderedDict([
        ("本人为关键决策人", "我本人会盯|我来拍板|我定|我决定|先跟我沟通"),
        ("家庭共同决策", "我先生|我太太|先生会一起看|太太也会看"),
        ("企业多角色决策", "CFO|CTO|采购|法务|财务总监|运营负责人|董事会|合伙人"),
        ("明确预算", "预算|金额超过"),
        ("明确时间表", "下周|本周|本月|月底|季度内|明天|周五之前|六月底前|下周一|下周三|下周四"),
    ])

    family_status: list[str] = []
    if re.search("太太|妻子|先生|丈夫|已婚", customer_text):
        family_status.append("已婚/伴侣参与")
    if re.search("孩子|女儿|儿子", customer_text):
        family_status.append("有子女")
    if re.search("留学|英国读书|新加坡读书|国际学校|学费", customer_text):
        family_status.append("子女教育/留学规划")

    family_notes = get_matched_lines(customer_lines, ["太太", "先生", "孩子", "女儿", "儿子", "留学", "英国读书", "新加坡读书", "学费"])
    business_preferences = get_labels(customer_text, business_preference_map)
    risk_concerns = get_labels(customer_text, risk_concern_map)
    communication_style = get_labels(customer_text, communication_style_map)
    decision_signals = get_labels(customer_text, decision_signal_map)

    recent_interest_points: list[str] = []
    if re.search("资产配置|美元", all_text):
        recent_interest_points.append("关注资产配置")
    if re.search("制造业案例|案例", all_text):
        recent_interest_points.append("关注行业案例")
    if "报价" in all_text:
        recent_interest_points.append("进入报价讨论")
    if re.search("演示|demo|Demo", all_text):
        recent_interest_points.append("期待产品演示")
    if "试点" in all_text:
        recent_interest_points.append("倾向先试点再扩展")
    if re.search("飞书|多维表格", all_text):
        recent_interest_points.append("关注飞书协同落地")

    budget_max = parse_budget_max(customer_text)
    budget_tag = f"预算上限约{budget_max}万"
    if budget_max > 0 and budget_tag not in recent_interest_points:
        recent_interest_points.append(budget_tag)

    meeting_time = parse_datetime(get_object_value(context, "meeting_time"))
    next_meeting_time = parse_datetime(get_object_value(context, "next_meeting_time"))
    sales_region = get_sales_region(context, all_text)
    business_value = get_business_value(all_text)

    lead_score = 50
    if budget_max > 0:
        lead_score += 12
    if re.search("下周|本周|本月|月底|季度内|尽快|明天|周五之前|六月底前", customer_text):
        lead_score += 10
    if next_meeting_time is not None:
        lead_score += 8
    if decision_signals:
        lead_score += 8
    if re.search("报价|方案|演示|试点|实施清单|字段清单", customer_text):
        lead_score += 8
    if re.search("两家工厂|集团|家族办公室|资产配置|华北团队", customer_text):
        lead_score += 6
    if re.search("家族办公室|资产配置|美元", all_text):
        lead_score += 6
    if risk_concerns:
        lead_score += 3
    if re.search("不着急|先了解|明年再说|明年再定|先看看|观察一下", customer_text):
        lead_score -= 15
    if re.search("暂无预算|预算要等明年|预算还没批", customer_text):
        lead_score -= 12
    if re.search("采购|法务", customer_text):
        lead_score += 6
    lead_score = clamp_score(lead_score)

    intent_level = "high" if lead_score >= 75 else ("medium" if lead_score >= 60 else "low")
    opportunity_stage = "初次接触"
    if re.search("合同|签约|付款|定稿", customer_text):
        opportunity_stage = "待成交"
    elif re.search("采购|法务|上线一期", customer_text):
        opportunity_stage = "推进中"
    elif re.search("报价|演示|实施清单|字段清单|保守版|平衡版", customer_text):
        opportunity_stage = "方案沟通"
    elif need_lines:
        opportunity_stage = "需求确认"
    if intent_level == "low":
        opportunity_stage = "初次接触"

    high_value_flag = (
        lead_score >= 75
        or budget_max >= 80
        or bool(re.search("家族办公室|资产配置|两家工厂|集团|高净值", all_text))
        or bool(re.search("家族办公室", str(get_object_value(context, "industry", ""))))
    )

    follow_up_time = next_meeting_time if next_meeting_time is not None else (meeting_time + timedelta(days=2) if meeting_time else None)
    recommended_action = {
        "待成交": "推动最终确认并准备签约/付款材料",
        "推进中": "整理推进清单，锁定关键角色并跟进采购/法务节点",
        "方案沟通": "24小时内发送定制方案/报价并确认下一次沟通",
        "需求确认": "补齐关键需求信息并推动进入方案讨论",
        "初次接触": "发送简洁会后摘要并继续培育客户意向",
    }[opportunity_stage]
    channel = "邮件" if "偏好邮件接收" in communication_style else ("微信" if "偏好微信触达" in communication_style else "飞书消息")

    summary = f"{get_object_value(context, 'customer_name')}本次重点关注{join_values(need_lines, '当前需求待补充')}；主要顾虑为{join_values(concern_lines, '当前未明确提出强顾虑')}；建议下一步{join_values(next_action_lines, recommended_action)}。"
    profile_summary = f"{get_object_value(context, 'customer_name')}当前表现出{join_values(family_status, '暂无明显家庭标签')}特征，偏好{join_values(business_preferences, '需求导向')}，沟通上{join_values(communication_style, '可常规跟进')}。"
    latest_progress = f"本次会议后，客户处于{opportunity_stage}阶段，Lead Score {lead_score}，推荐动作：{recommended_action}"

    if re.search("资产配置|美元", all_text):
        opportunity_theme = "资产配置"
    elif re.search("巡检|售后|工厂", all_text):
        opportunity_theme = "售后巡检试点"
    elif re.search("CRM|客户信息|会议纪要", all_text):
        opportunity_theme = "CRM 一期试点"
    else:
        opportunity_theme = "商机推进"

    opportunity_name = f"{get_object_value(context, 'customer_name')} - {opportunity_theme}"
    opportunity_description = {
        "待成交": "客户已进入合同/定稿推进阶段，重点是锁定签约前材料与排期。",
        "推进中": "客户已进入多角色内部推进阶段，需同步采购、法务或实施边界。",
        "方案沟通": "客户已进入方案、报价或演示讨论阶段，正在细化可落地方案。",
        "需求确认": "客户已明确核心需求与约束条件，下一步应推动进入方案沟通。",
        "初次接触": "客户当前仍处于接触或观察阶段，适合继续培育与补充需求理解。",
    }[opportunity_stage]

    draft_message = (
        f"{get_object_value(context, 'customer_name')} 您好，今天沟通的重点我帮您收了一版：\n"
        f"1. 您当前最关注的是：{join_values(need_lines, '核心需求已记录')}。\n"
        f"2. 我们会重点处理：{join_values(concern_lines, '本次暂无突出顾虑')}。\n"
        f"3. 下一步我会：{recommended_action}。\n"
        f"如果方便，我先通过{channel}发您精简版材料，您看完后我们再按约定时间推进。"
    )
    brief_trigger = next_meeting_time - timedelta(hours=1) if next_meeting_time is not None else None
    opening_script = f"先从客户最在意的{join_values(business_preferences, '当前需求')}切入，再回应{join_values(risk_concerns, '执行细节')}，最后确认{join_values(next_action_lines, recommended_action)}。"

    discussion_points: list[str] = []
    for item in need_lines + concern_lines:
        if item not in discussion_points:
            discussion_points.append(item)
    key_points: list[str] = []
    for item in need_lines + next_action_lines:
        if item not in key_points:
            key_points.append(item)
    commitments = next_action_lines[:3]
    meeting_id_suffix = meeting_time.strftime("%Y%m%d%H%M") if meeting_time else "unknown"

    meeting_record = OrderedDict([
        ("meeting_id", f"MTG-{get_object_value(context, 'customer_id')}-{meeting_id_suffix}"),
        ("customer_id", get_object_value(context, "customer_id")),
        ("customer_name", get_object_value(context, "customer_name")),
        ("company_name", company_name),
        ("meeting_time", isoformat_or_none(meeting_time)),
        ("summary", summary),
        ("discussion_points", discussion_points),
        ("customer_needs", need_lines),
        ("customer_concerns", concern_lines),
        ("next_actions", next_action_lines),
        ("commitments", commitments),
    ])
    customer_profile_update = OrderedDict([
        ("customer_id", get_object_value(context, "customer_id")),
        ("company_name", company_name),
        ("industry", industry_name),
        ("family_status", list(OrderedDict.fromkeys(family_status))),
        ("family_notes", family_notes),
        ("business_preferences", business_preferences),
        ("risk_concerns", risk_concerns),
        ("communication_style", communication_style),
        ("decision_signals", decision_signals),
        ("recent_interest_points", list(OrderedDict.fromkeys(recent_interest_points))),
        ("profile_summary", profile_summary),
    ])
    opportunity_update = OrderedDict([
        ("opportunity_id", get_object_value(context, "opportunity_id")),
        ("opportunity_name", opportunity_name),
        ("opportunity_description", opportunity_description),
        ("sales_region", sales_region),
        ("business_value", business_value),
        ("lead_score", lead_score),
        ("intent_level", intent_level),
        ("opportunity_stage", opportunity_stage),
        ("high_value_flag", bool(high_value_flag)),
        ("recommended_action", recommended_action),
        ("next_follow_up_at", isoformat_or_none(follow_up_time)),
        ("latest_progress", latest_progress),
    ])
    follow_up_task = OrderedDict([
        ("task_title", f"跟进 {get_object_value(context, 'customer_name')} - {opportunity_stage}"),
        ("owner", get_object_value(context, "owner")),
        ("due_at", isoformat_or_none(follow_up_time)),
        ("channel", channel),
        ("draft_message", draft_message),
        ("checklist", ["确认客户核心需求是否完整记录", "按推荐动作发送材料或推进下一次沟通", "更新飞书多维表格中的商机状态"]),
    ])
    pre_meeting_brief = OrderedDict([
        ("next_meeting_at", isoformat_or_none(next_meeting_time)),
        ("trigger_at", isoformat_or_none(brief_trigger)),
        ("headline", f"{get_object_value(context, 'customer_name')} 会前行动简报"),
        ("opening_script", opening_script),
        ("key_points", key_points),
        ("watchouts", list(OrderedDict.fromkeys(concern_lines))),
        ("materials_to_prepare", ["客户画像摘要", "上次会议结论", "与本次需求对应的方案/案例/报价材料"]),
    ])
    customer_table_row = OrderedDict([
        ("客户ID", get_object_value(context, "customer_id")),
        ("客户名称", get_object_value(context, "customer_name")),
        ("客户公司", company_name),
        ("行业", industry_name),
        ("客户负责人", get_object_value(context, "owner")),
        ("家庭标签", join_values(customer_profile_update["family_status"])),
        ("家庭备注", join_values(customer_profile_update["family_notes"])),
        ("商业偏好", join_values(customer_profile_update["business_preferences"])),
        ("风险顾虑", join_values(customer_profile_update["risk_concerns"])),
        ("沟通风格", join_values(customer_profile_update["communication_style"])),
        ("决策信号", join_values(customer_profile_update["decision_signals"])),
        ("最近关注点", join_values(customer_profile_update["recent_interest_points"])),
        ("客户画像摘要", customer_profile_update["profile_summary"]),
        ("最后更新时间", isoformat_or_none(meeting_time)),
        ("数据来源", source_channel),
    ])
    opportunity_snapshot_row = OrderedDict([
        ("商机ID", get_object_value(context, "opportunity_id")),
        ("客户ID", get_object_value(context, "customer_id")),
        ("客户名称", get_object_value(context, "customer_name")),
        ("客户公司", company_name),
        ("机会名称", opportunity_update["opportunity_name"]),
        ("商机描述", opportunity_update["opportunity_description"]),
        ("当前阶段", opportunity_update["opportunity_stage"]),
        ("Lead Score", opportunity_update["lead_score"]),
        ("意向等级", opportunity_update["intent_level"]),
        ("高净值优先", opportunity_update["high_value_flag"]),
        ("销售区域", opportunity_update["sales_region"]),
        ("业务价值", opportunity_update["business_value"]),
        ("推荐动作", opportunity_update["recommended_action"]),
        ("最新进展", opportunity_update["latest_progress"]),
        ("下次跟进时间", opportunity_update["next_follow_up_at"]),
        ("最近会议时间", meeting_record["meeting_time"]),
        ("商机负责人", get_object_value(context, "owner")),
        ("数据来源", source_channel),
    ])
    feishu_payload = OrderedDict([
        ("customer_table", OrderedDict([("mode", "upsert"), ("key_field", "客户ID"), ("key", get_object_value(context, "customer_id")), ("update_fields", customer_table_row)])),
        ("opportunity_snapshot_table", OrderedDict([("mode", "append"), ("append_row", opportunity_snapshot_row)])),
    ])
    crm_packet = OrderedDict([
        ("input", OrderedDict([("transcript_path", resolve_str(transcript_path)), ("context_path", resolve_str(context_path)), ("customer_id", get_object_value(context, "customer_id")), ("opportunity_id", get_object_value(context, "opportunity_id"))])),
        ("meeting", meeting_record),
        ("customer_profile_update", customer_profile_update),
        ("opportunity_update", opportunity_update),
        ("follow_up_task", follow_up_task),
        ("pre_meeting_brief", pre_meeting_brief),
        ("customer_table_row", customer_table_row),
        ("opportunity_snapshot_row", opportunity_snapshot_row),
        ("feishu_bitable_payload", feishu_payload),
    ])

    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    write_json(output / "meeting_record.json", meeting_record)
    write_json(output / "customer_profile_update.json", customer_profile_update)
    write_json(output / "opportunity_update.json", opportunity_update)
    write_json(output / "follow_up_task.json", follow_up_task)
    write_json(output / "pre_meeting_brief.json", pre_meeting_brief)
    write_json(output / "customer_table_row.json", customer_table_row)
    write_json(output / "opportunity_snapshot_row.json", opportunity_snapshot_row)
    write_json(output / "crm_packet.json", crm_packet)
    return crm_packet


def build_example_block(example: dict[str, Any]) -> str:
    return "\r\n".join([
        f"### 示例：{example['name']}",
        f"任务提示：{example['task_hint']}",
        "",
        "输入 context:",
        "```json",
        json.dumps(example["input"]["context"], ensure_ascii=False, indent=2),
        "```",
        "",
        "输入 transcript:",
        "```text",
        example["input"]["transcript"],
        "```",
        "",
        "参考输出:",
        "```json",
        json.dumps(example["output"], ensure_ascii=False, indent=2),
        "```",
    ])


def build_llm_prompt(transcript_path: str | Path, context_path: str | Path, output_dir: str | Path, example_names: list[str] | None = None) -> dict[str, Any]:
    names = example_names or ["chen_familyoffice", "liu_enterprise_it", "sun_observer"]
    template = read_text(skill_root() / "references" / "llm_prompt_template.md")
    schema = read_text(skill_root() / "references" / "llm_output_schema.md")
    context_json = read_text(context_path)
    transcript_text = read_text(transcript_path)
    example_blocks = [build_example_block(read_json(skill_root() / "assets" / "few_shot" / f"{name}.json")) for name in names]
    system_prompt = "\r\n".join([template, "", "以下是输出 schema，请严格遵守：", "", schema]).strip()
    user_prompt = "\r\n".join([
        "以下是 few-shot 示例，请学习其抽取方式、阶段判断标准和输出风格：",
        "",
        "\r\n\r\n".join(example_blocks),
        "",
        "现在请处理新的输入。",
        "",
        "输入 context:",
        "```json",
        context_json,
        "```",
        "",
        "输入 transcript:",
        "```text",
        transcript_text,
        "```",
        "",
        "请只输出 JSON，不要输出解释。",
    ]).strip()
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    prompt_package = OrderedDict([
        ("system_prompt", system_prompt),
        ("user_prompt", user_prompt),
        ("examples", names),
        ("transcript_path", resolve_str(transcript_path)),
        ("context_path", resolve_str(context_path)),
    ])
    write_json(output / "prompt_package.json", prompt_package)
    write_text(output / "system_prompt.txt", system_prompt)
    write_text(output / "user_prompt.txt", user_prompt)
    return prompt_package


def assert_has_property(obj: dict[str, Any], property_name: str, scope: str) -> None:
    if obj is None:
        raise ValueError(f"Missing object [{scope}] in model output.")
    if property_name not in obj:
        raise ValueError(f"Missing property [{scope}.{property_name}] in model output.")


def validate_datetime(value: Any, field_name: str) -> None:
    if value is None or not str(value).strip():
        return
    try:
        datetime.fromisoformat(str(value).strip())
    except ValueError as exc:
        raise ValueError(f"Invalid datetime in [{field_name}]: {value}") from exc


def validate_model_output(model_output_path: str | Path) -> dict[str, Any]:
    model = read_json(model_output_path)
    for top in ["meeting", "customer_profile_update", "opportunity_update", "follow_up_task", "pre_meeting_brief"]:
        assert_has_property(model, top, "root")
    for field in ["customer_id", "customer_name", "company_name", "meeting_time", "summary"]:
        assert_has_property(model["meeting"], field, "meeting")
    for field in ["customer_id", "company_name", "industry", "profile_summary"]:
        assert_has_property(model["customer_profile_update"], field, "customer_profile_update")
    for field in ["opportunity_id", "opportunity_name", "opportunity_description", "sales_region", "business_value", "lead_score", "intent_level", "opportunity_stage", "high_value_flag", "recommended_action", "latest_progress"]:
        assert_has_property(model["opportunity_update"], field, "opportunity_update")
    for field in ["task_title", "owner", "channel", "draft_message", "checklist"]:
        assert_has_property(model["follow_up_task"], field, "follow_up_task")
    for field in ["headline", "opening_script", "key_points", "watchouts", "materials_to_prepare"]:
        assert_has_property(model["pre_meeting_brief"], field, "pre_meeting_brief")
    if model["opportunity_update"]["intent_level"] not in VALID_INTENT_LEVELS:
        raise ValueError(f"Invalid opportunity_update.intent_level: {model['opportunity_update']['intent_level']}")
    if model["opportunity_update"]["opportunity_stage"] not in VALID_STAGES:
        raise ValueError(f"Invalid opportunity_update.opportunity_stage: {model['opportunity_update']['opportunity_stage']}")
    channel = model["follow_up_task"].get("channel")
    if channel and channel not in VALID_CHANNELS:
        raise ValueError(f"Invalid follow_up_task.channel: {channel}")
    lead_score = int(model["opportunity_update"]["lead_score"])
    if lead_score < 0 or lead_score > 100:
        raise ValueError("lead_score must be between 0 and 100.")
    validate_datetime(model["meeting"].get("meeting_time"), "meeting.meeting_time")
    validate_datetime(model["opportunity_update"].get("next_follow_up_at"), "opportunity_update.next_follow_up_at")
    validate_datetime(model["follow_up_task"].get("due_at"), "follow_up_task.due_at")
    validate_datetime(model["pre_meeting_brief"].get("next_meeting_at"), "pre_meeting_brief.next_meeting_at")
    validate_datetime(model["pre_meeting_brief"].get("trigger_at"), "pre_meeting_brief.trigger_at")
    return model


def convert_model_output_to_crm(model_output_path: str | Path, output_dir: str | Path, context_path: str | Path | None = None) -> dict[str, Any]:
    model = validate_model_output(model_output_path)
    context = read_json(context_path) if context_path and Path(context_path).exists() else None
    source_channel = get_object_value(context, "channel", "LLM 结构化输出")
    owner = get_object_value(context, "owner", model["follow_up_task"]["owner"])
    customer_table_row = OrderedDict([
        ("客户ID", model["customer_profile_update"]["customer_id"]),
        ("客户名称", model["meeting"]["customer_name"]),
        ("客户公司", model["customer_profile_update"]["company_name"]),
        ("行业", model["customer_profile_update"]["industry"]),
        ("客户负责人", owner),
        ("家庭标签", join_values(model["customer_profile_update"].get("family_status"))),
        ("家庭备注", join_values(model["customer_profile_update"].get("family_notes"))),
        ("商业偏好", join_values(model["customer_profile_update"].get("business_preferences"))),
        ("风险顾虑", join_values(model["customer_profile_update"].get("risk_concerns"))),
        ("沟通风格", join_values(model["customer_profile_update"].get("communication_style"))),
        ("决策信号", join_values(model["customer_profile_update"].get("decision_signals"))),
        ("最近关注点", join_values(model["customer_profile_update"].get("recent_interest_points"))),
        ("客户画像摘要", model["customer_profile_update"]["profile_summary"]),
        ("最后更新时间", model["meeting"]["meeting_time"]),
        ("数据来源", source_channel),
    ])
    opportunity_snapshot_row = OrderedDict([
        ("商机ID", model["opportunity_update"]["opportunity_id"]),
        ("客户ID", model["meeting"]["customer_id"]),
        ("客户名称", model["meeting"]["customer_name"]),
        ("客户公司", model["meeting"]["company_name"]),
        ("机会名称", model["opportunity_update"]["opportunity_name"]),
        ("商机描述", model["opportunity_update"]["opportunity_description"]),
        ("当前阶段", model["opportunity_update"]["opportunity_stage"]),
        ("Lead Score", model["opportunity_update"]["lead_score"]),
        ("意向等级", model["opportunity_update"]["intent_level"]),
        ("高净值优先", model["opportunity_update"]["high_value_flag"]),
        ("销售区域", model["opportunity_update"]["sales_region"]),
        ("业务价值", model["opportunity_update"]["business_value"]),
        ("推荐动作", model["opportunity_update"]["recommended_action"]),
        ("最新进展", model["opportunity_update"]["latest_progress"]),
        ("下次跟进时间", model["opportunity_update"].get("next_follow_up_at")),
        ("最近会议时间", model["meeting"]["meeting_time"]),
        ("商机负责人", owner),
        ("数据来源", source_channel),
    ])
    crm_packet = OrderedDict([
        ("input", OrderedDict([("model_output_path", resolve_str(model_output_path)), ("context_path", resolve_str(context_path) if context_path and Path(context_path).exists() else None)])),
        ("meeting", model["meeting"]),
        ("customer_profile_update", model["customer_profile_update"]),
        ("opportunity_update", model["opportunity_update"]),
        ("follow_up_task", model["follow_up_task"]),
        ("pre_meeting_brief", model["pre_meeting_brief"]),
        ("customer_table_row", customer_table_row),
        ("opportunity_snapshot_row", opportunity_snapshot_row),
        (
            "feishu_bitable_payload",
            OrderedDict([
                (
                    "customer_table",
                    OrderedDict([
                        ("mode", "upsert"),
                        ("key_field", "客户ID"),
                        ("key", model["customer_profile_update"]["customer_id"]),
                        ("update_fields", customer_table_row),
                    ]),
                ),
                (
                    "opportunity_snapshot_table",
                    OrderedDict([
                        ("mode", "append"),
                        ("append_row", opportunity_snapshot_row),
                    ]),
                ),
            ]),
        ),
    ])
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    write_json(output / "meeting_record.json", model["meeting"])
    write_json(output / "customer_profile_update.json", model["customer_profile_update"])
    write_json(output / "opportunity_update.json", model["opportunity_update"])
    write_json(output / "follow_up_task.json", model["follow_up_task"])
    write_json(output / "pre_meeting_brief.json", model["pre_meeting_brief"])
    write_json(output / "customer_table_row.json", customer_table_row)
    write_json(output / "opportunity_snapshot_row.json", opportunity_snapshot_row)
    write_json(output / "crm_packet.json", crm_packet)
    return crm_packet


def run_sample_tests(output_root: str | Path) -> None:
    sample_dir = skill_root() / "assets" / "samples"
    expected_dir = skill_root() / "assets" / "expected"
    context_files = sorted(sample_dir.glob("*_context.json"))
    if not context_files:
        raise ValueError(f"No sample contexts found in {sample_dir}")
    failures = 0
    for context_file in context_files:
        sample_name = context_file.stem.replace("_context", "")
        transcript_path = sample_dir / f"{sample_name}_transcript.txt"
        expected_path = expected_dir / f"{sample_name}.json"
        out_dir = Path(output_root) / sample_name
        if not transcript_path.exists():
            raise FileNotFoundError(f"Missing transcript for sample {sample_name}")
        if not expected_path.exists():
            raise FileNotFoundError(f"Missing expected assertion file for sample {sample_name}")
        packet = process_transcript(transcript_path, context_file, out_dir)
        expected = read_json(expected_path)
        errors: list[str] = []
        if packet["opportunity_update"]["intent_level"] != expected["intent_level"]:
            errors.append(f"intent_level expected [{expected['intent_level']}] actual [{packet['opportunity_update']['intent_level']}]")
        if int(packet["opportunity_update"]["lead_score"]) < int(expected["min_lead_score"]):
            errors.append(f"lead_score expected >= {expected['min_lead_score']} actual [{packet['opportunity_update']['lead_score']}]")
        if packet["opportunity_update"]["opportunity_stage"] != expected["opportunity_stage"]:
            errors.append(f"opportunity_stage expected [{expected['opportunity_stage']}] actual [{packet['opportunity_update']['opportunity_stage']}]")
        if bool(packet["opportunity_update"]["high_value_flag"]) != bool(expected["high_value_flag"]):
            errors.append(f"high_value_flag expected [{expected['high_value_flag']}] actual [{packet['opportunity_update']['high_value_flag']}]")
        all_tags: list[str] = []
        for group in ["family_status", "business_preferences", "risk_concerns", "communication_style", "decision_signals", "recent_interest_points"]:
            for tag in packet["customer_profile_update"][group]:
                if tag not in all_tags:
                    all_tags.append(tag)
        for tag in expected["required_tags"]:
            if tag not in all_tags:
                errors.append(f"missing required tag [{tag}]")
        required_channel = expected.get("required_channel")
        if required_channel and packet["follow_up_task"]["channel"] != required_channel:
            errors.append(f"required_channel expected [{required_channel}] actual [{packet['follow_up_task']['channel']}]")
        for snippet in expected["summary_must_include"]:
            if snippet not in packet["meeting"]["summary"]:
                errors.append(f"summary missing snippet [{snippet}]")
        if bool(expected["pre_meeting_should_exist"]) != bool(packet["pre_meeting_brief"].get("next_meeting_at")):
            errors.append(f"pre_meeting existence expected [{expected['pre_meeting_should_exist']}] actual [{bool(packet['pre_meeting_brief'].get('next_meeting_at'))}]")
        if errors:
            failures += 1
            print(f"[FAIL] {sample_name}")
            for err in errors:
                print(f"  - {err}")
        else:
            print(f"[PASS] {sample_name}")
    if failures:
        raise RuntimeError(f"{failures} sample test(s) failed.")


def run_feishu_pipeline_tests(output_root: str | Path) -> None:
    raw_dir = skill_root() / "assets" / "feishu_raw"
    expected_dir = skill_root() / "assets" / "expected"
    raw_files = sorted(raw_dir.glob("*.json"))
    if not raw_files:
        raise ValueError(f"No Feishu raw sample files found in {raw_dir}")
    failures = 0
    for raw_file in raw_files:
        sample_name = raw_file.stem
        expected_path = expected_dir / f"{sample_name}.json"
        if not expected_path.exists():
            raise FileNotFoundError(f"Missing expected assertion file for Feishu sample {sample_name}")
        sample_output = Path(output_root) / sample_name
        build_output = sample_output / "build"
        process_output = sample_output / "process"
        build_context_from_feishu(raw_file, build_output)
        packet = process_transcript(build_output / "transcript.txt", build_output / "context.json", process_output)
        expected = read_json(expected_path)
        errors: list[str] = []
        if packet["opportunity_update"]["intent_level"] != expected["intent_level"]:
            errors.append(f"intent_level expected [{expected['intent_level']}] actual [{packet['opportunity_update']['intent_level']}]")
        if int(packet["opportunity_update"]["lead_score"]) < int(expected["min_lead_score"]):
            errors.append(f"lead_score expected >= {expected['min_lead_score']} actual [{packet['opportunity_update']['lead_score']}]")
        if packet["opportunity_update"]["opportunity_stage"] != expected["opportunity_stage"]:
            errors.append(f"opportunity_stage expected [{expected['opportunity_stage']}] actual [{packet['opportunity_update']['opportunity_stage']}]")
        if errors:
            failures += 1
            print(f"[FAIL] {sample_name}")
            for err in errors:
                print(f"  - {err}")
        else:
            print(f"[PASS] {sample_name}")
    if failures:
        raise RuntimeError(f"{failures} Feishu pipeline test(s) failed.")


def run_model_output_tests(output_root: str | Path) -> None:
    model_dir = skill_root() / "runtime" / "llm_outputs"
    sample_dir = skill_root() / "assets" / "samples"
    model_files = sorted(model_dir.rglob("model_output.json"))
    if not model_files:
        raise ValueError(f"No model_output.json files found under {model_dir}")
    for model_file in model_files:
        sample_name = model_file.parent.name
        context_path = sample_dir / f"{sample_name}_context.json"
        out_dir = Path(output_root) / sample_name
        validate_model_output(model_file)
        packet = convert_model_output_to_crm(model_file, out_dir, context_path if context_path.exists() else None)
        if packet["feishu_bitable_payload"].get("customer_table") is None:
            raise RuntimeError(f"customer_table missing in {sample_name}")
        if packet["feishu_bitable_payload"].get("opportunity_snapshot_table") is None:
            raise RuntimeError(f"opportunity_snapshot_table missing in {sample_name}")
        print(f"[PASS] {sample_name}")


def run_customer_journey(manifest_path: str | Path, output_dir: str | Path) -> dict[str, Any]:
    manifest = read_json(manifest_path)
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    rounds: list[dict[str, Any]] = []
    for item in manifest["rounds"]:
        round_name = item["round_id"]
        context_path = skill_root() / item["context_path"]
        transcript_path = skill_root() / item["transcript_path"]
        round_output = output / round_name
        packet = process_transcript(transcript_path, context_path, round_output)
        rounds.append(OrderedDict([
            ("round_id", round_name),
            ("label", item["label"]),
            ("meeting_time", packet["meeting"]["meeting_time"]),
            ("lead_score", packet["opportunity_update"]["lead_score"]),
            ("intent_level", packet["opportunity_update"]["intent_level"]),
            ("opportunity_stage", packet["opportunity_update"]["opportunity_stage"]),
            ("high_value_flag", packet["opportunity_update"]["high_value_flag"]),
            ("recommended_action", packet["opportunity_update"]["recommended_action"]),
            ("summary", packet["meeting"]["summary"]),
            ("next_follow_up_at", packet["opportunity_update"]["next_follow_up_at"]),
        ]))
    sorted_rounds = sorted(rounds, key=lambda item: datetime.fromisoformat(item["meeting_time"]))
    progression_notes: list[str] = []
    for i, current in enumerate(sorted_rounds):
        if i == 0:
            progression_notes.append(f"第1轮为{current['label']}，阶段：{current['opportunity_stage']}，Lead Score {current['lead_score']}")
            continue
        previous = sorted_rounds[i - 1]
        delta = int(current["lead_score"]) - int(previous["lead_score"])
        direction = "提升" if delta > 0 else ("下降" if delta < 0 else "持平")
        delta_text = f" {delta}" if delta != 0 else ""
        progression_notes.append(f"{current['label']} 从 {previous['opportunity_stage']} -> {current['opportunity_stage']}，Lead Score {current['lead_score']}（{direction}{delta_text}）")
    journey = OrderedDict([
        ("customer_id", manifest["customer_id"]),
        ("customer_name", manifest["customer_name"]),
        ("opportunity_id", manifest["opportunity_id"]),
        ("total_rounds", len(sorted_rounds)),
        ("journey_theme", manifest["journey_theme"]),
        ("stage_path", [item["opportunity_stage"] for item in sorted_rounds]),
        ("latest_stage", sorted_rounds[-1]["opportunity_stage"]),
        ("latest_lead_score", sorted_rounds[-1]["lead_score"]),
        ("latest_intent", sorted_rounds[-1]["intent_level"]),
        ("progression_notes", progression_notes),
        ("rounds", sorted_rounds),
    ])
    write_json(output / "journey_summary.json", journey)
    return journey


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="CRM Assistant Python CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("process-transcript")
    p.add_argument("--transcript-path", required=True)
    p.add_argument("--context-path", required=True)
    p.add_argument("--output-dir", required=True)

    p = sub.add_parser("build-context-from-feishu")
    p.add_argument("--raw-input-path", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--context-file-name", default="context.json")
    p.add_argument("--transcript-file-name", default="transcript.txt")

    p = sub.add_parser("build-llm-prompt")
    p.add_argument("--transcript-path", required=True)
    p.add_argument("--context-path", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--example-names", nargs="*", default=["chen_familyoffice", "liu_enterprise_it", "sun_observer"])

    p = sub.add_parser("validate-model-output")
    p.add_argument("--model-output-path", required=True)

    p = sub.add_parser("convert-model-output")
    p.add_argument("--model-output-path", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--context-path")

    p = sub.add_parser("run-sample-tests")
    p.add_argument("--output-root", default=str(skill_root() / "runtime"))

    p = sub.add_parser("run-feishu-pipeline-tests")
    p.add_argument("--output-root", default=str(skill_root() / "runtime" / "feishu_pipeline_py"))

    p = sub.add_parser("run-model-output-tests")
    p.add_argument("--output-root", default=str(skill_root() / "runtime" / "from_model_py"))

    p = sub.add_parser("run-customer-journey")
    p.add_argument("--manifest-path", required=True)
    p.add_argument("--output-dir", required=True)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.command == "process-transcript":
        process_transcript(args.transcript_path, args.context_path, args.output_dir)
        print(f"CRM packet generated at: {args.output_dir}")
    elif args.command == "build-context-from-feishu":
        build_context_from_feishu(args.raw_input_path, args.output_dir, args.context_file_name, args.transcript_file_name)
        print(f"Feishu raw input converted at: {args.output_dir}")
    elif args.command == "build-llm-prompt":
        build_llm_prompt(args.transcript_path, args.context_path, args.output_dir, args.example_names)
        print(f"LLM prompt package generated at: {args.output_dir}")
    elif args.command == "validate-model-output":
        validate_model_output(args.model_output_path)
        print(f"Model output is valid: {args.model_output_path}")
    elif args.command == "convert-model-output":
        convert_model_output_to_crm(args.model_output_path, args.output_dir, args.context_path)
        print(f"Converted model output to CRM artifacts at: {args.output_dir}")
    elif args.command == "run-sample-tests":
        run_sample_tests(args.output_root)
        print(f"All sample tests passed. Output root: {args.output_root}")
    elif args.command == "run-feishu-pipeline-tests":
        run_feishu_pipeline_tests(args.output_root)
        print(f"All Feishu pipeline tests passed. Output root: {args.output_root}")
    elif args.command == "run-model-output-tests":
        run_model_output_tests(args.output_root)
        print(f"All model output tests passed. Output root: {args.output_root}")
    elif args.command == "run-customer-journey":
        run_customer_journey(args.manifest_path, args.output_dir)
        print(f"Customer journey generated at: {args.output_dir}")


if __name__ == "__main__":
    main()
