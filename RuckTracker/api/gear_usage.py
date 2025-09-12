import logging
import os
from flask import Blueprint, request, jsonify, g
from sqlalchemy import text

from RuckTracker.extensions import db
from RuckTracker.utils.auth_helper import get_current_user_id

logger = logging.getLogger(__name__)

gear_usage_bp = Blueprint('gear_usage', __name__)


def _gear_enabled() -> bool:
    return (os.environ.get('GEAR_ENABLED', 'true').lower() == 'true')


@gear_usage_bp.route('/rucks/<int:session_id>/gear', methods=['GET'])
def get_session_gear(session_id: int):
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Return gear linked to a ruck session (owner-only)."""
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({'error': 'Authentication required'}), 401

    # Verify session ownership
    owns = db.session.execute(text(
        "select 1 from ruck_session where id = :sid and user_id = :uid"
    ), {'sid': session_id, 'uid': user_id}).first()
    if not owns:
        return jsonify({'error': 'Forbidden'}), 403

    rows = db.session.execute(text(
        """
        select id, role, gear_item_id, external_product_id, carried_weight_kg
        from ruck_session_gear where session_id = :sid order by created_at asc
        """
    ), {'sid': session_id}).mappings().all()
    return jsonify({'session_id': session_id, 'items': list(rows)}), 200


@gear_usage_bp.route('/rucks/<int:session_id>/gear', methods=['PATCH'])
def set_session_gear(session_id: int):
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Replace gear linked to a session. Body: { items: [{role, gear_item_id?|external_product_id?, carried_weight_kg?}] }"""
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({'error': 'Authentication required'}), 401

    payload = request.get_json(silent=True) or {}
    items = payload.get('items') or []
    if not isinstance(items, list):
        return jsonify({'error': 'items must be a list'}), 400

    # Verify session ownership
    owns = db.session.execute(text(
        "select 1 from ruck_session where id = :sid and user_id = :uid"
    ), {'sid': session_id, 'uid': user_id}).first()
    if not owns:
        return jsonify({'error': 'Forbidden'}), 403

    allowed_roles = {'ruck', 'plate', 'shoes', 'device', 'accessory'}
    to_insert = []
    for it in items:
        if not isinstance(it, dict):
            return jsonify({'error': 'invalid item format'}), 400
        role = (it.get('role') or '').strip()
        if role not in allowed_roles:
            return jsonify({'error': f'invalid role: {role}'}), 400
        gear_item_id = it.get('gear_item_id')
        external_product_id = it.get('external_product_id')
        if not gear_item_id and not external_product_id:
            return jsonify({'error': 'gear_item_id or external_product_id required'}), 400
        carried = it.get('carried_weight_kg')
        to_insert.append({
            'session_id': session_id,
            'user_id': user_id,
            'role': role,
            'gear_item_id': gear_item_id,
            'external_product_id': external_product_id,
            'carried_weight_kg': carried,
        })

    try:
        with db.session.begin():
            db.session.execute(text("delete from ruck_session_gear where session_id = :sid"), {'sid': session_id})
            if to_insert:
                db.session.execute(text(
                    """
                    insert into ruck_session_gear
                      (session_id, user_id, role, gear_item_id, external_product_id, carried_weight_kg)
                    values
                      (:session_id, :user_id, :role, :gear_item_id, :external_product_id, :carried_weight_kg)
                    """
                ), to_insert)
        return jsonify({'ok': True, 'count': len(to_insert)}), 200
    except Exception as e:
        logger.exception("Failed to set session gear")
        return jsonify({'error': 'internal_error'}), 500


@gear_usage_bp.route('/stats/gear/usage', methods=['GET'])
def get_user_gear_usage():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Return per-user gear usage aggregates from view_gear_usage_user."""
    user_id = request.args.get('user_id') or get_current_user_id()
    if not user_id:
        return jsonify({'error': 'user_id required'}), 400
    rows = db.session.execute(text(
        """
        select role, canonical_key, title, image_url, category_slug,
               sessions_count, total_distance_km, max_weight_kg, avg_weight_kg, last_used_at
        from view_gear_usage_user where user_id = :uid
        order by total_distance_km desc nulls last, sessions_count desc
        """
    ), {'uid': user_id}).mappings().all()
    return jsonify({'user_id': user_id, 'items': list(rows)}), 200


@gear_usage_bp.route('/stats/gear/top', methods=['GET'])
def get_global_gear_usage():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Return global gear usage aggregates.

    Query: category, role, relation=owned|saved
    - owned → view_gear_usage_global (distance/sessions)
    - saved → view_gear_saved_counts (wishlists)
    """
    category = request.args.get('category')
    role = request.args.get('role')
    relation = (request.args.get('relation') or 'owned').lower()

    if relation == 'saved':
        base = "select null as role, canonical_key, title, image_url, category_slug, saved_count from view_gear_saved_counts"
        clauses = []
        params = {}
        if category:
            clauses.append("category_slug = :cat")
            params['cat'] = category
        where = (" where " + " and ".join(clauses)) if clauses else ""
        order = " order by saved_count desc limit 100"
        rows = db.session.execute(text(base + where + order), params).mappings().all()
        return jsonify({'items': list(rows)}), 200

    base = "select role, canonical_key, title, image_url, category_slug, sessions_count, total_distance_km, max_weight_kg from view_gear_usage_global"
    clauses = []
    params = {}
    if category:
        clauses.append("category_slug = :cat")
        params['cat'] = category
    if role:
        clauses.append("role = :role")
        params['role'] = role
    where = (" where " + " and ".join(clauses)) if clauses else ""
    order = " order by total_distance_km desc nulls last, sessions_count desc limit 100"
    rows = db.session.execute(text(base + where + order), params).mappings().all()
    return jsonify({'items': list(rows)}), 200
