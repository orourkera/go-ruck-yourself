"""Create notifications table

Revision ID: 0e4e2af782ac
Revises: 
Create Date: 2025-05-25 11:48:00

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '0e4e2af782ac'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'notifications',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('recipient_id', sa.String(36), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('sender_id', sa.String(36), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('type', sa.String(50), nullable=False),
        sa.Column('message', sa.String(255), nullable=False),
        sa.Column('data', sa.JSON, nullable=True),
        sa.Column('is_read', sa.Boolean, nullable=False, default=False),
        sa.Column('read_at', sa.DateTime, nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, nullable=False, server_default=sa.func.now(), onupdate=sa.func.now())
    )
    
    # Create index for faster notification fetching
    op.create_index('idx_notifications_recipient_created', 'notifications', ['recipient_id', 'created_at'])
    op.create_index('idx_notifications_unread', 'notifications', ['recipient_id', 'is_read'])


def downgrade():
    op.drop_index('idx_notifications_unread')
    op.drop_index('idx_notifications_recipient_created')
    op.drop_table('notifications')
