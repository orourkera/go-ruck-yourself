"""Coaching Plan Audit Service

Validates newly created plans to reduce AI hallucinations and enforces guardrails.
- Reviews user_coaching_plans and associated plan_sessions
- Sends plan context to OpenAI for verification (structured JSON)
- Applies SAFE corrections (schedule/labels/notes only) if recommended
- Marks plan as reviewed and stores audit details
- Notifies admins via NotificationManager

No new dependencies: reuses existing OpenAI pattern and NotificationManager.
"""
from __future__ import annotations

import logging
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

from .notification_manager import notification_manager
from ..supabase_client import get_supabase_admin_client
from .openai_utils import create_chat_completion
from .arize_observability import observe_openai_call

logger = logging.getLogger(__name__)


class PlanAuditService:
    def __init__(self, admin_client=None):
        self.admin = admin_client or get_supabase_admin_client()
        self.model = os.getenv('OPENAI_PLAN_AUDIT_MODEL', os.getenv('OPENAI_DEFAULT_MODEL', 'gpt-5'))

    # Public API
    def audit_and_correct_plan(self, user_id: str, plan_id: int) -> Dict[str, Any]:
        """Audit a single plan and optionally correct minor issues.
        Returns a summary dict with status and issues.
        """
        plan = self._fetch_plan(user_id, plan_id)
        if not plan:
            return {"status": "failed", "reason": "plan_not_found"}

        sessions = self._fetch_sessions(plan_id)
        template = self._fetch_template(plan.get('coaching_plan_id'))

        local_findings = self._run_local_checks(plan, sessions, template)
        ai_review = self._run_ai_review(user_id, plan, sessions, template)

        status = 'approved'
        corrections_applied: Dict[str, Any] = {}
        issues: List[Dict[str, Any]] = []

        if ai_review is None and not local_findings['has_issues']:
            status = 'approved'
        else:
            # Merge issues
            if local_findings['issues']:
                issues.extend(local_findings['issues'])
            if ai_review and ai_review.get('issues'):
                issues.extend(ai_review['issues'])

            # Apply only safe corrections (labels/notes/tiny schedule shifts)
            try:
                corrections_applied = self._apply_safe_corrections(plan_id, sessions, ai_review)
                status = 'corrected' if corrections_applied else ('approved' if not issues else 'approved')
            except Exception as corr_err:
                logger.error(f"Plan {plan_id} correction failed: {corr_err}")
                status = 'failed'

        # Persist audit record
        summary = {
            "status": status,
            "issues": issues,
            "corrections": corrections_applied,
            "ai_meta": {k: ai_review.get(k) for k in ("model","token_usage","latency_ms")} if ai_review else None,
        }
        self._persist_audit(plan_id, summary)

        # Mark plan as reviewed
        self._mark_plan_reviewed(plan_id, status, summary)

        # Notify admins
        try:
            self._notify_admins(user_id, plan_id, status, summary)
        except Exception as notif_err:
            logger.error(f"Failed to notify admins for plan {plan_id}: {notif_err}")

        return {"status": status, "issues": issues, "corrections": corrections_applied}

    def process_pending_reviews(self, limit: int = 25) -> int:
        """Process plans with review_status = 'pending'. Returns count processed."""
        try:
            resp = self.admin.table('user_coaching_plans').select('id,user_id').eq('review_status', 'pending').order('created_at').limit(limit).execute()
            rows = resp.data or []
        except Exception as exc:
            logger.error(f"Failed to fetch pending plan reviews: {exc}")
            return 0

        processed = 0
        for row in rows:
            try:
                self.audit_and_correct_plan(row['user_id'], int(row['id']))
                processed += 1
            except Exception as exc:
                logger.error(f"Audit failed for plan {row['id']}: {exc}")
        return processed

    # Internal helpers
    def _fetch_plan(self, user_id: str, plan_id: int) -> Optional[Dict[str, Any]]:
        try:
            resp = self.admin.table('user_coaching_plans').select(
                'id,user_id,coaching_plan_id,coaching_personality,start_date,current_week,current_status,plan_modifications,review_status'
            ).eq('id', plan_id).eq('user_id', user_id).limit(1).execute()
            return resp.data[0] if resp.data else None
        except Exception as exc:
            logger.error(f"Failed to fetch plan {plan_id}: {exc}")
            return None

    def _fetch_sessions(self, plan_id: int) -> List[Dict[str, Any]]:
        try:
            resp = self.admin.table('plan_sessions').select(
                'id,planned_week,planned_session_type,completion_status,scheduled_date,notes'
            ).eq('user_coaching_plan_id', plan_id).order('planned_week').order('id').limit(500).execute()
            return resp.data or []
        except Exception as exc:
            logger.error(f"Failed to fetch plan_sessions for plan {plan_id}: {exc}")
            return []

    def _fetch_template(self, template_id: Optional[int]) -> Optional[Dict[str, Any]]:
        if not template_id:
            return None
        try:
            resp = self.admin.table('coaching_plan_templates').select(
                'id,plan_id,name,duration_weeks,base_structure,progression_rules,non_negotiables,personalization_knobs,retests'
            ).eq('id', template_id).limit(1).execute()
            return resp.data[0] if resp.data else None
        except Exception as exc:
            logger.error(f"Failed to fetch template {template_id}: {exc}")
            return None

    def _run_local_checks(self, plan: Dict[str, Any], sessions: List[Dict[str, Any]], template: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        issues: List[Dict[str, Any]] = []
        has_issues = False

        # Check that planned_week is within template duration
        if template and template.get('duration_weeks'):
            max_week = int(template['duration_weeks'])
            bad_weeks = [s for s in sessions if int(s.get('planned_week', 0)) < 1 or int(s.get('planned_week', 0)) > max_week]
            if bad_weeks:
                has_issues = True
                issues.append({
                    'type': 'invalid_week_range',
                    'message': f"{len(bad_weeks)} sessions fall outside 1..{max_week}",
                    'session_ids': [s['id'] for s in bad_weeks]
                })

        # Ensure scheduled_date present for planned sessions
        missing_dates = [s['id'] for s in sessions if s.get('completion_status') == 'planned' and not s.get('scheduled_date')]
        if missing_dates:
            has_issues = True
            issues.append({'type': 'missing_scheduled_date', 'message': f"{len(missing_dates)} planned sessions without scheduled_date", 'session_ids': missing_dates})

        return {'has_issues': has_issues, 'issues': issues}

    def _run_ai_review(self, user_id: str, plan: Dict[str, Any], sessions: List[Dict[str, Any]], template: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        try:
            import openai
            import json

            api_key = os.getenv('OPENAI_API_KEY')
            if not api_key:
                logger.warning("OPENAI_API_KEY not configured for plan audit")
                return None

            client = openai.OpenAI(api_key=api_key)

            plan_summary = {
                'plan_id': plan['id'],
                'template_id': plan.get('coaching_plan_id'),
                'personality': plan.get('coaching_personality'),
                'start_date': plan.get('start_date'),
                'plan_modifications': plan.get('plan_modifications') or {},
                'template': {
                    'name': template.get('name') if template else None,
                    'duration_weeks': template.get('duration_weeks') if template else None,
                    'progression_rules': template.get('progression_rules') if template else None,
                    'non_negotiables': template.get('non_negotiables') if template else None,
                },
                'sessions': [
                    {
                        'id': s['id'],
                        'week': s['planned_week'],
                        'type': s['planned_session_type'],
                        'date': s.get('scheduled_date'),
                    } for s in sessions
                ]
            }

            system_prompt = (
                "You are an expert strength & endurance coach. Audit a rucking coaching plan for safety and scientific plausibility. "
                "Enforce guardrails: one variable change per week (time or elevation or load), weekly volume cap ~10%, include deloads, "
                "keep quality sessions at fixed load within a week, and ensure sessions are scheduled. "
                "Return STRICT JSON with keys: model, decision ('approved'|'corrected'|'failed'), issues (array of {type,message,session_ids?}), "
                "corrections (object) with optionally: session_type_changes [{session_id,new_type,reason}], schedule_fixes [{session_id,new_date,reason}], "
                "plan_notes (string). Do NOT invent intense changes—prefer minimal viable corrections."
            )

            user_prompt = json.dumps(plan_summary)

            start_time = time.time()
            resp = create_chat_completion(
                client,
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                max_completion_tokens=600,
                temperature=0.2
            )

            latency_ms = (time.time() - start_time) * 1000
            content = resp.choices[0].message.content.strip()

            try:
                observe_openai_call(
                    model=self.model,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ],
                    response=content,
                    latency_ms=latency_ms,
                    user_id=user_id,
                    session_id=str(plan.get('id')) if plan.get('id') else None,
                    context_type='plan_audit',
                    prompt_tokens=getattr(getattr(resp, 'usage', None), 'prompt_tokens', None),
                    completion_tokens=getattr(getattr(resp, 'usage', None), 'completion_tokens', None),
                    total_tokens=getattr(getattr(resp, 'usage', None), 'total_tokens', None),
                    temperature=0.2,
                    max_tokens=600,
                    metadata={
                        'plan_id': plan.get('id'),
                        'session_count': len(sessions),
                        'template_id': plan.get('coaching_plan_id'),
                    }
                )
            except Exception as telemetry_err:
                logger.warning(f"[PLAN_AUDIT] Failed to log Arize telemetry: {telemetry_err}")
            try:
                parsed = json.loads(content)
            except Exception:
                logger.error(f"AI plan audit returned non-JSON: {content}")
                return None

            parsed['token_usage'] = getattr(resp, 'usage', None)
            return parsed
        except Exception as exc:
            logger.error(f"AI audit failed: {exc}")
            return None

    def _apply_safe_corrections(self, plan_id: int, sessions: List[Dict[str, Any]], ai_review: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        if not ai_review or ai_review.get('corrections') is None:
            return {}
        changes = ai_review['corrections']
        applied = {"session_type_changes": [], "schedule_fixes": []}

        # Only allow two types of edits for safety and to avoid feature regressions
        try:
            if changes.get('session_type_changes'):
                for entry in changes['session_type_changes']:
                    sid = int(entry.get('session_id'))
                    new_type = entry.get('new_type')
                    if not new_type:
                        continue
                    self.admin.table('plan_sessions').update({
                        'planned_session_type': new_type,
                        'notes': (entry.get('reason') or 'type adjusted by audit')
                    }).eq('id', sid).execute()
                    applied['session_type_changes'].append({'session_id': sid, 'new_type': new_type})
        except Exception as exc:
            logger.error(f"Failed applying session type changes: {exc}")

        try:
            if changes.get('schedule_fixes'):
                for entry in changes['schedule_fixes']:
                    sid = int(entry.get('session_id'))
                    new_date = entry.get('new_date')
                    if not new_date:
                        continue
                    self.admin.table('plan_sessions').update({
                        'scheduled_date': new_date,
                        'notes': (entry.get('reason') or 'schedule adjusted by audit')
                    }).eq('id', sid).execute()
                    applied['schedule_fixes'].append({'session_id': sid, 'new_date': new_date})
        except Exception as exc:
            logger.error(f"Failed applying schedule fixes: {exc}")

        return applied

    def _persist_audit(self, plan_id: int, summary: Dict[str, Any]) -> None:
        try:
            self.admin.table('plan_review_audit').insert({
                'user_coaching_plan_id': plan_id,
                'status': summary.get('status', 'approved'),
                'issues': summary.get('issues', []),
                'corrections': summary.get('corrections', {}),
                'notes': 'automated review',
            }).execute()
        except Exception as exc:
            logger.debug(f"plan_review_audit insert failed (likely table missing): {exc}")

    def _mark_plan_reviewed(self, plan_id: int, status: str, summary: Dict[str, Any]) -> None:
        try:
            self.admin.table('user_coaching_plans').update({
                'review_status': status,
                'reviewed_at': datetime.utcnow().isoformat(),
                'review_summary': summary
            }).eq('id', plan_id).execute()
        except Exception as exc:
            logger.error(f"Failed to mark plan {plan_id} reviewed: {exc}")

    def _notify_admins(self, user_id: str, plan_id: int, status: str, summary: Dict[str, Any]) -> None:
        # Gather admin users from env
        admin_list = [u.strip() for u in os.getenv('ADMIN_USERS', '').split(',') if u.strip()]
        if not admin_list:
            logger.info("No ADMIN_USERS configured; skipping admin notification for plan audit")
            return

        title = f"Plan audit: {status.upper()}"
        body = f"Plan {plan_id} for user {user_id}: {len(summary.get('issues') or [])} issues, corrections: {bool(summary.get('corrections'))}"

        notification_manager.send_notification(
            recipients=admin_list,
            notification_type='plan_review',
            title=title,
            body=body,
            data={
                'type': 'plan_review',
                'plan_id': plan_id,
                'status': status,
            },
            save_to_db=True,
            sender_id=user_id
        )


# Singleton instance
plan_audit_service = PlanAuditService()
