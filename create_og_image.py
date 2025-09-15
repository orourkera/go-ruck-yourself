#!/usr/bin/env python3
"""
Create a professional Open Graph image for getrucky.com
Size: 1200x630px (Facebook/Twitter recommended)
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_og_image():
    # Image dimensions for Open Graph
    width, height = 1200, 630

    # Create image with gradient background
    img = Image.new('RGB', (width, height), color='#2D4A2B')
    draw = ImageDraw.Draw(img)

    # Create gradient effect
    for y in range(height):
        # Gradient from dark green to slightly lighter green
        ratio = y / height
        r = int(45 + (20 * ratio))
        g = int(74 + (30 * ratio))
        b = int(43 + (20 * ratio))
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Try to load fonts, fall back to default if not available
    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/Arial.ttc", 84)
        subtitle_font = ImageFont.truetype("/System/Library/Fonts/Arial.ttc", 42)
        tagline_font = ImageFont.truetype("/System/Library/Fonts/Arial.ttc", 32)
    except:
        title_font = ImageFont.load_default()
        subtitle_font = ImageFont.load_default()
        tagline_font = ImageFont.load_default()

    # Main title
    title_text = "RUCK"
    title_bbox = draw.textbbox((0, 0), title_text, font=title_font)
    title_width = title_bbox[2] - title_bbox[0]
    title_x = (width - title_width) // 2
    title_y = 120

    # Draw title with shadow effect
    draw.text((title_x + 3, title_y + 3), title_text, fill=(0, 0, 0, 128), font=title_font)
    draw.text((title_x, title_y), title_text, fill='white', font=title_font)

    # Subtitle
    subtitle_text = "The Ultimate Rucking Tracker"
    subtitle_bbox = draw.textbbox((0, 0), subtitle_text, font=subtitle_font)
    subtitle_width = subtitle_bbox[2] - subtitle_bbox[0]
    subtitle_x = (width - subtitle_width) // 2
    subtitle_y = title_y + 100

    draw.text((subtitle_x + 2, subtitle_y + 2), subtitle_text, fill=(0, 0, 0, 100), font=subtitle_font)
    draw.text((subtitle_x, subtitle_y), subtitle_text, fill='white', font=subtitle_font)

    # Feature highlights
    features = [
        "📍 GPS Tracking & Route Maps",
        "🏆 Achievements & Challenges",
        "📊 Performance Analytics",
        "👥 Community & Social Sharing"
    ]

    feature_y = subtitle_y + 80
    for i, feature in enumerate(features):
        feature_bbox = draw.textbbox((0, 0), feature, font=tagline_font)
        feature_width = feature_bbox[2] - feature_bbox[0]
        feature_x = (width - feature_width) // 2
        current_y = feature_y + (i * 45)

        draw.text((feature_x + 1, current_y + 1), feature, fill=(0, 0, 0, 80), font=tagline_font)
        draw.text((feature_x, current_y), feature, fill='#E8F5E8', font=tagline_font)

    # Bottom tagline
    bottom_text = "getrucky.com"
    bottom_bbox = draw.textbbox((0, 0), bottom_text, font=subtitle_font)
    bottom_width = bottom_bbox[2] - bottom_bbox[0]
    bottom_x = (width - bottom_width) // 2
    bottom_y = height - 80

    draw.text((bottom_x + 2, bottom_y + 2), bottom_text, fill=(0, 0, 0, 100), font=subtitle_font)
    draw.text((bottom_x, bottom_y), bottom_text, fill='#90EE90', font=subtitle_font)

    # Add some decorative elements
    # Corner accents
    accent_color = '#4A7C59'
    draw.rectangle([0, 0, 8, height], fill=accent_color)
    draw.rectangle([width-8, 0, width, height], fill=accent_color)
    draw.rectangle([0, 0, width, 8], fill=accent_color)
    draw.rectangle([0, height-8, width, height], fill=accent_color)

    return img

if __name__ == "__main__":
    # Create the image
    og_image = create_og_image()

    # Save to the static images directory
    output_path = "/Users/rory/RuckingApp/RuckTracker/static/images/new_og_preview.png"
    og_image.save(output_path, "PNG", quality=95)
    print(f"✅ Created new Open Graph image: {output_path}")
    print("📐 Size: 1200x630px")
    print("🎨 Professional design with app branding")