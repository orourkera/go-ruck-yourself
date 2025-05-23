#!/bin/bash

# Define the source directory
SOURCE_DIR="/Users/rory/RuckingApp/rucking_app/ios/GRY Watch App/Assets.xcassets/AppIcon.appiconset"
SOURCE_ICON="$SOURCE_DIR/Icon-1024.png"

# Create all required icon sizes
# Format: Size@2x = actual pixel size
echo "Generating watchOS app icons from $SOURCE_ICON..."

# Generate all the required sizes
magick "$SOURCE_ICON" -resize 44x44 "$SOURCE_DIR/Icon-22@2x.png"
magick "$SOURCE_ICON" -resize 48x48 "$SOURCE_DIR/Icon-24@2x.png"
magick "$SOURCE_ICON" -resize 55x55 "$SOURCE_DIR/Icon-27.5@2x.png"
magick "$SOURCE_ICON" -resize 58x58 "$SOURCE_DIR/Icon-29@2x.png"
magick "$SOURCE_ICON" -resize 60x60 "$SOURCE_DIR/Icon-30@2x.png"
magick "$SOURCE_ICON" -resize 64x64 "$SOURCE_DIR/Icon-32@2x.png"
magick "$SOURCE_ICON" -resize 66x66 "$SOURCE_DIR/Icon-33@2x.png"
magick "$SOURCE_ICON" -resize 80x80 "$SOURCE_DIR/Icon-40@2x.png"
magick "$SOURCE_ICON" -resize 87x87 "$SOURCE_DIR/Icon-43.5@2x.png"
magick "$SOURCE_ICON" -resize 88x88 "$SOURCE_DIR/Icon-44@2x.png"
magick "$SOURCE_ICON" -resize 92x92 "$SOURCE_DIR/Icon-46@2x.png"
magick "$SOURCE_ICON" -resize 100x100 "$SOURCE_DIR/Icon-50@2x.png"
magick "$SOURCE_ICON" -resize 102x102 "$SOURCE_DIR/Icon-51@2x.png"
magick "$SOURCE_ICON" -resize 108x108 "$SOURCE_DIR/Icon-54@2x.png"
magick "$SOURCE_ICON" -resize 172x172 "$SOURCE_DIR/Icon-86@2x.png"
magick "$SOURCE_ICON" -resize 196x196 "$SOURCE_DIR/Icon-98@2x.png"
magick "$SOURCE_ICON" -resize 216x216 "$SOURCE_DIR/Icon-108@2x.png"
magick "$SOURCE_ICON" -resize 234x234 "$SOURCE_DIR/Icon-117@2x.png"
magick "$SOURCE_ICON" -resize 258x258 "$SOURCE_DIR/Icon-129@2x.png"

echo "All watchOS app icons generated successfully!"
