import datetime
from flask import Blueprint, render_template, abort

blog_bp = Blueprint('blog', __name__)

# Blog posts registry
BLOG_POSTS = [
    {
        "slug": "what-is-rucking",
        "title": "What Is Rucking? The Complete Beginner’s Guide",
        "description": "Rucking explained: benefits, gear, how to start, and tips to avoid injury.",
        "date": "2025-05-01",
        "author": "Get Rucky Team",
        "tags": ["rucking", "beginner", "fitness"],
        "read_time": 8,
        "template": "blog/posts/what-is-rucking.html",
    },
    {
        "slug": "rucking-vs-running",
        "title": "Rucking vs Running: Which Is Better for You?",
        "description": "Compare rucking and running for weight loss, joint impact, and endurance training.",
        "date": "2025-05-01",
        "author": "Get Rucky Team",
        "tags": ["rucking", "running", "training"],
        "read_time": 9,
        "template": "blog/posts/rucking-vs-running.html",
    },
    {
        "slug": "rucking-calories-burned",
        "title": "Rucking Calories Burned: How to Calculate and Improve",
        "description": "Understand calorie burn while rucking and how weight, pace, and terrain affect it.",
        "date": "2025-05-01",
        "author": "Get Rucky Team",
        "tags": ["calories", "weight loss", "metrics"],
        "read_time": 10,
        "template": "blog/posts/rucking-calories-burned.html",
    },
    {
        "slug": "rucking-weight-how-much",
        "title": "How Much Weight Should You Ruck With?",
        "description": "Find your ideal ruck weight based on goal, fitness level, and experience.",
        "date": "2025-05-01",
        "author": "Get Rucky Team",
        "tags": ["ruck weight", "gear", "beginner"],
        "read_time": 7,
        "template": "blog/posts/rucking-weight-how-much.html",
    },
]

# Build a quick lookup
POSTS_BY_SLUG = {p["slug"]: p for p in BLOG_POSTS}


def _sorted_posts():
    def parse_date(d):
        try:
            return datetime.datetime.fromisoformat(d)
        except Exception:
            return datetime.datetime.min
    return sorted(BLOG_POSTS, key=lambda p: parse_date(p.get("date", "")), reverse=True)


@blog_bp.route('/blog')
@blog_bp.route('/blog/')
def blog_index():
    return render_template('blog/index.html', posts=_sorted_posts())


@blog_bp.route('/blog/<slug>')
def blog_post(slug: str):
    post = POSTS_BY_SLUG.get(slug)
    if not post:
        abort(404)
    return render_template('blog/post.html', post=post)
