from PIL import Image
import os

# Load the logo
logo_path = "assets/images/TATIS.png"
logo = Image.open(logo_path).convert("RGBA")

def trim_transparency(img: Image.Image) -> Image.Image:
    alpha = img.split()[-1]
    bbox = alpha.getbbox()
    if bbox is None:
        return img
    return img.crop(bbox)

logo = trim_transparency(logo)

# Define target sizes for Android densities
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

base_path = "android/app/src/main/res"

for density, size in sizes.items():
    # Resize the cropped image to fill the icon canvas
    resized = logo.resize((size, size), Image.Resampling.LANCZOS)
    
    # Save to the appropriate directory
    output_path = os.path.join(base_path, density, "ic_launcher.png")
    resized.save(output_path, "PNG")
    print(f"✓ Created {output_path} ({size}x{size})")

print("\n✅ All app icons created successfully!")
