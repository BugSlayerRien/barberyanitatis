from PIL import Image
from pathlib import Path

src = Path(r'assets/images/TATIS.png')
out = Path(r'assets/images/app_icon.png')
fg = Path(r'assets/images/app_icon_foreground.png')

im = Image.open(src).convert('RGBA')
size = 1024

# Legacy/fallback icon: slight padding so the circle isn't clipped by launcher masks.
legacy_pad = int(size * 0.06)
legacy_inner = size - (legacy_pad * 2)
legacy = Image.new('RGBA', (size, size), (0, 0, 0, 255))
legacy_logo = im.resize((legacy_inner, legacy_inner), Image.Resampling.LANCZOS)
legacy.paste(legacy_logo, (legacy_pad, legacy_pad), legacy_logo)
legacy.save(out, 'PNG')

# Adaptive foreground: full-bleed on black. flutter_launcher_icons already applies a 16% inset.
fg_img = Image.new('RGBA', (size, size), (0, 0, 0, 255))
full = im.resize((size, size), Image.Resampling.LANCZOS)
fg_img.paste(full, (0, 0), full)
fg_img.save(fg, 'PNG')

print(f'wrote {out} {legacy.size}')
print(f'wrote {fg} {fg_img.size}')
