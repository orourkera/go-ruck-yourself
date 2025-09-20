import datetime
import os
from flask import Blueprint, render_template, abort, current_app

blog_bp = Blueprint('blog', __name__)

# Blog posts registry
BLOG_POSTS = [
    {
        "slug": "rucking-pace-calculator",
        "title": "Rucking Pace Calculator: Estimate and Improve Your Pace",
        "description": "Estimate rucking pace by weight, grade, terrain, and fitness. See pace tables, training tips, and a free calculator to plan smarter, safer sessions.",
        "date": "2025-08-31",
        "author": "rory@getrucky.com",
        "tags": ["pace", "calculator", "training"],
        "read_time": 9,
        "template": "blog/posts/rucking-pace-calculator.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "lcda-vs-pandolf-vs-fusion",
        "title": "LCDA vs Pandolf vs Fusion: Rucking Calories Debate (No Perfect Answer)",
        "description": "LCDA vs Pandolf vs our proprietary Fusion: which rucking calorie model fits best? Evidence, trade-offs, and why our defaults favor stability—no perfect answer.",
        "date": "2025-08-31",
        "author": "rory@getrucky.com",
        "tags": ["calories", "science", "weighted vest", "modeling"],
        "read_time": 9,
        "template": "blog/posts/lcda-vs-pandolf-vs-fusion.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "weighted-vests-viral-military-rucking-explained",
        "title": "Weighted Vests Are Viral — The Military ‘Rucking’ Science, Safety, and How to Start",
        "description": "Weighted vests are trending, but the method is old-school rucking. Evidence, Huberman/Easter insights, safe progressions, and when to pick a vest vs a ruck.",
        "date": "2025-08-31",
        "author": "rory@getrucky.com",
        "tags": ["weighted vest", "rucking", "science", "military"],
        "read_time": 10,
        "template": "blog/posts/weighted-vests-viral-military-rucking-explained.html",
        "image": "images/blog/ruckers.jpg",
    },
    {
        "slug": "weighted-vest-gear-review-rukstr-aion-carry",
        "title": "Best Weighted Vests: RUKSTR vs AION Gear vs The Carry (2025 Review)",
        "description": "Hands-on review of three hyped weighted vests. Fit, bounce, breathability, durability, and who each is best for—plus programming tips.",
        "date": "2025-08-31",
        "author": "rory@getrucky.com",
        "tags": ["weighted vest", "gear", "review"],
        "read_time": 8,
        "template": "blog/posts/weighted-vest-gear-review-rukstr-aion-carry.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "essential-rucking-gear-excluding-rucksacks",
        "title": "Essential Rucking Gear (Excluding the Rucksack): Feet, Socks, Weights, Hydration, Safety",
        "description": "Essential rucking gear (excluding the rucksack): footwear, socks, weights, hydration, first aid, and safety tips to prevent blisters and boost comfort.",
        "date": "2025-08-31",
        "author": "rory@getrucky.com",
        "tags": ["gear", "beginner", "injury prevention"],
        "read_time": 9,
        "template": "blog/posts/essential-rucking-gear-excluding-rucksacks.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "how-to-ruck-with-weighted-vest",
        "title": "How to Ruck with a Weighted Vest: Fit, Progressions, and When to Switch",
        "description": "Can you ruck with a weighted vest? Yes—fit it snug, start light, build time before weight, and know when a backpack is better for longer or hillier sessions.",
        "date": "2025-08-29",
        "author": "rory@getrucky.com",
        "tags": ["weighted vest", "technique", "beginner"],
        "read_time": 8,
        "template": "blog/posts/how-to-ruck-with-weighted-vest.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "rucksack-weight-distribution-how-to-pack-a-ruck",
        "title": "Rucksack Weight Distribution: How to Pack a Ruck (Step-by-Step)",
        "description": "Pack weight high and close to your spine for comfort and efficiency. Step-by-step packing guide, stability tips, and a checklist to prevent hotspots.",
        "date": "2025-08-26",
        "author": "rory@getrucky.com",
        "tags": ["rucking", "gear", "packing"],
        "read_time": 7,
        "template": "blog/posts/rucksack-weight-distribution-how-to-pack-a-ruck.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "rucking-for-beginners-4-week-plan",
        "title": "Rucking for Beginners: Simple 4-Week Starter Plan",
        "description": "A friendly 4-week plan that builds time-on-feet first, then adds load or hills. Conversational efforts, easy progress, and fewer blisters or aches.",
        "date": "2025-08-23",
        "author": "rory@getrucky.com",
        "tags": ["beginner", "plan", "training"],
        "read_time": 7,
        "template": "blog/posts/rucking-for-beginners-4-week-plan.html",
        "image": "images/blog/ruckers.jpg",
    },
    {
        "slug": "is-rucking-safe-knees-spine",
        "title": "Is Rucking Safe? What the Science Says About Knees and Spine",
        "description": "Is rucking bad for knees or back? With smart load placement and gradual progressions, most can ruck safely. Evidence, technique, and risk reducers.",
        "date": "2025-08-20",
        "author": "rory@getrucky.com",
        "tags": ["injury prevention", "knees", "spine"],
        "read_time": 8,
        "template": "blog/posts/is-rucking-safe-knees-spine.html",
        "image": "images/blog/girl.jpg",
    },
    {
        "slug": "rucking-weight-alternatives",
        "title": "Rucking Weight Alternatives: Real-World Ways to Hit 10–50 lbs (Without Buying Plates)",
        "description": "Practical, subtly playful alternatives to ruck plates: water jugs, laptop bags, litter, and more—with simple combos to dial 10–50 lbs.",
        "date": "2025-08-27",
        "author": "rory@getrucky.com",
        "tags": ["rucking", "gear", "weights", "beginner"],
        "read_time": 6,
        "template": "blog/posts/rucking-weight-alternatives.html",
        "image": "images/blog/nathan-dumlao-bxQLEK0tVao-unsplash.jpg",
    },
    {
        "slug": "best-rucking-backpack-guide",
        "title": "The Ultimate Rucking Backpack Guide: GoRuck vs Frontline vs Budget Alternatives (2025)",
        "description": "Comprehensive guide to the best rucking backpacks in 2025. Compare GoRuck, Frontline Athletic, Mystery Ranch, and budget options with real user reviews and pricing.",
        "date": "2025-08-30",
        "author": "RuckTracker Team",
        "tags": ["gear", "backpack", "goruck", "review"],
        "read_time": 12,
        "template": "blog/posts/best-rucking-backpack-guide.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "what-is-rucking",
        "title": "What Is Rucking? The Complete Beginner's Guide",
        "description": "Rucking explained: benefits, gear, how to start, and tips to avoid injury.",
        "date": "2025-08-22",
        "author": "rory@getrucky.com",
        "tags": ["rucking", "beginner", "fitness"],
        "read_time": 8,
        "template": "blog/posts/what-is-rucking.html",
        "image": "images/blog/ruckers.jpg",
    },
    {
        "slug": "rucking-vs-running",
        "title": "Rucking vs Running: Which Is Better for You?",
        "description": "Compare rucking and running for weight loss, joint impact, and endurance training.",
        "date": "2025-08-20",
        "author": "rory@getrucky.com",
        "tags": ["rucking", "running", "training"],
        "read_time": 9,
        "template": "blog/posts/rucking-vs-running.html",
        "image": "images/blog/cool.jpg",
    },
    {
        "slug": "rucking-calories-burned",
        "title": "Rucking Calories Burned: How to Calculate and Improve",
        "description": "Understand calorie burn while rucking and how weight, pace, and terrain affect it.",
        "date": "2025-08-18",
        "author": "rory@getrucky.com",
        "tags": ["calories", "weight loss", "metrics"],
        "read_time": 10,
        "template": "blog/posts/rucking-calories-burned.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "rucking-weight-how-much",
        "title": "How Much Weight Should You Ruck With?",
        "description": "Find your ideal ruck weight based on goal, fitness level, and experience.",
        "date": "2025-08-16",
        "author": "rory@getrucky.com",
        "tags": ["ruck weight", "gear", "beginner"],
        "read_time": 7,
        "template": "blog/posts/rucking-weight-how-much.html",
        "image": "images/blog/lady.jpg",
    },
    {
        "slug": "weighted-vest-vs-ruck-which-is-better",
        "title": "Weighted Vest vs Ruck: Which Is Better?",
        "description": "Vest vs ruck: energy cost, comfort, and when to pick each—based on data.",
        "date": "2025-08-14",
        "author": "rory@getrucky.com",
        "tags": ["weighted vest", "rucking", "comparison"],
        "read_time": 7,
        "template": "blog/posts/weighted-vest-vs-ruck-which-is-better.html",
        "image": "images/blog/girl.jpg",
    },
    {
        "slug": "beginner-weighted-vest-how-much-weight",
        "title": "How Much Weight Should You Use in a Weighted Vest (or Ruck)?",
        "description": "Start smart: 5–10% body weight, simple progressions, and injury-safe rules.",
        "date": "2025-08-12",
        "author": "rory@getrucky.com",
        "tags": ["weighted vest", "ruck weight", "beginner"],
        "read_time": 6,
        "template": "blog/posts/beginner-weighted-vest-how-much-weight.html",
        "image": "images/blog/lady.jpg",
    },
    {
        "slug": "calories-weighted-vest-walking-vs-rucking",
        "title": "Calories: Weighted Vest Walking vs Rucking",
        "description": "Compare calorie methods (mechanical, MET, HR) and see how load/grade matter.",
        "date": "2025-08-10",
        "author": "rory@getrucky.com",
        "tags": ["calories", "weighted vest", "metrics"],
        "read_time": 8,
        "template": "blog/posts/calories-weighted-vest-walking-vs-rucking.html",
        "image": "images/blog/cool.jpg",
    },
    {
        "slug": "rucking-and-knee-back-safety",
        "title": "Is Rucking or Weighted Vest Walking Bad for Your Knees or Back?",
        "description": "Risk, mechanics, and progressions to keep joints happy under load.",
        "date": "2025-08-08",
        "author": "rory@getrucky.com",
        "tags": ["injury prevention", "knees", "back"],
        "read_time": 7,
        "template": "blog/posts/rucking-and-knee-back-safety.html",
        "image": "images/blog/girl.jpg",
    },
    {
        "slug": "backpack-vs-weighted-vest-load-distribution",
        "title": "Backpack vs Weighted Vest: Load Distribution and Breathing",
        "description": "Same weight, different feel—how load placement affects comfort and effort.",
        "date": "2025-08-06",
        "author": "rory@getrucky.com",
        "tags": ["weighted vest", "rucking", "gear"],
        "read_time": 6,
        "template": "blog/posts/backpack-vs-weighted-vest-load-distribution.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "best-pace-distance-weight-loss-rucking",
        "title": "Best Pace and Distance for Weight Loss: Rucking and Weighted Vests",
        "description": "Pace, time, and incline targets that actually move the scale.",
        "date": "2025-08-04",
        "author": "rory@getrucky.com",
        "tags": ["weight loss", "training", "programming"],
        "read_time": 7,
        "template": "blog/posts/best-pace-distance-weight-loss-rucking.html",
        "image": "images/blog/girl.jpg",
    },
    {
        "slug": "weighted-vest-bone-density-evidence",
        "title": "Do Weighted Vests Help Bone Density?",
        "description": "Evidence for preserving or improving BMD with vest walking, especially in older adults.",
        "date": "2025-08-02",
        "author": "rory@getrucky.com",
        "tags": ["bone density", "health", "older adults"],
        "read_time": 6,
        "template": "blog/posts/weighted-vest-bone-density-evidence.html",
        "image": "images/blog/lady.jpg",
    },
    {
        "slug": "rucking-gear-and-weighted-vest-gear",
        "title": "Gear Guide: Rucking Packs and Weighted Vests",
        "description": "What to look for in packs and vests for comfort, fit, and durability.",
        "date": "2025-07-31",
        "author": "rory@getrucky.com",
        "tags": ["gear", "ruck", "weighted vest"],
        "read_time": 6,
        "template": "blog/posts/rucking-gear-and-weighted-vest-gear.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "combine-rucking-with-running-strength",
        "title": "How to Combine Rucking or Weighted Vests with Running and Strength",
        "description": "Weekly templates to balance load carriage, lifting, and running without overcooking it.",
        "date": "2025-07-28",
        "author": "rory@getrucky.com",
        "tags": ["programming", "running", "strength"],
        "read_time": 7,
        "template": "blog/posts/combine-rucking-with-running-strength.html",
        "image": "images/blog/ruckers.jpg",
    },
    {
        "slug": "hills-incline-effects-rucking-weighted-vest",
        "title": "Hills and Incline: How Much Harder with a Weighted Vest or Ruck?",
        "description": "Grade multiplies effort—how to program hills safely and effectively.",
        "date": "2025-07-25",
        "author": "rory@getrucky.com",
        "tags": ["hills", "incline", "training"],
        "read_time": 6,
        "template": "blog/posts/hills-incline-effects-rucking-weighted-vest.html",
        "image": "images/blog/mountaim.jpg",
    },
    {
        "slug": "indoor-treadmill-vest-ruck-guide",
        "title": "Indoor Guide: Treadmill Rucking and Weighted Vest Walking",
        "description": "Make bad-weather sessions count with smart incline and interval setups.",
        "date": "2025-07-22",
        "author": "rory@getrucky.com",
        "tags": ["treadmill", "indoor", "workouts"],
        "read_time": 6,
        "template": "blog/posts/indoor-treadmill-vest-ruck-guide.html",
        "image": "images/blog/lady.jpg",
    },
    {
        "slug": "weighted-vest-form-and-fitting",
        "title": "Weighted Vest and Ruck Fitting: Stop the Bounce, Save the Joints",
        "description": "Fit checklist and why snug gear saves energy and reduces hotspots.",
        "date": "2025-07-19",
        "author": "rory@getrucky.com",
        "tags": ["fit", "technique", "gear"],
        "read_time": 5,
        "template": "blog/posts/weighted-vest-form-and-fitting.html",
        "image": "images/blog/gear.jpg",
    },
    {
        "slug": "weighted-vests-menopause-hormones",
        "title": "Weighted Vests, Menopause, and Hormones: What the Science Actually Says",
        "description": "Evidence-based guide on weighted vests for postmenopausal women: bone density, biomarkers, and safe programming with narrative tips and practical steps.",
        "date": "2025-09-19",
        "author": "rory@getrucky.com",
        "tags": ["menopause", "weighted vest", "bone density", "women"],
        "read_time": 9,
        "template": "blog/posts/weighted-vests-menopause-hormones.html",
        "image": "images/blog/vest.jpg",
    },
    {
        "slug": "science-based-coaching-plans",
        "title": "Science‑Based Rucking Coaching Plans: Personalized, Progressive, Proven",
        "description": "Inside Ruck!’s coaching plans: age-strong, fat loss, speed, capacity, events—personalized progressions grounded in exercise science and load‑carriage research.",
        "date": "2025-09-20",
        "author": "rory@getrucky.com",
        "tags": ["coaching", "plans", "training", "personalization", "science"],
        "read_time": 11,
        "template": "blog/posts/science-based-coaching-plans.html",
        "image": "images/blog/coaching.jpg",
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
    posts = _sorted_posts()
    # Ensure images exist; if not, fall back to a safe placeholder that exists
    static_root = os.path.join(current_app.root_path, 'static')
    safe_default = 'og_preview.png'
    for p in posts:
        img_rel = p.get('image') or ''
        img_path = os.path.join(static_root, img_rel) if img_rel else ''
        if not img_rel or not os.path.exists(img_path):
            p['image'] = safe_default
    return render_template('blog/index.html', posts=posts)


@blog_bp.route('/blog/<slug>')
def blog_post(slug: str):
    post = POSTS_BY_SLUG.get(slug)
    if not post:
        abort(404)
    return render_template('blog/post.html', post=post)
