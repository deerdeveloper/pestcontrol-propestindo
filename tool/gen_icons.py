"""Ikon aplikasi Propestindo.

Emblem lingkaran (hijau/merah/emas) digambar ulang sebagai vektor dari
mobile/assets/logo.png. Koordinat: pusat (77,77), radius luar 70, dalam 56.
"""
import sys, cairosvg
EMB = '''
<defs>
 <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#F5CF45"/><stop offset="0.5" stop-color="#E2B22B"/><stop offset="1" stop-color="#B8861A"/>
 </linearGradient>
 <linearGradient id="gold2" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#F2CB42"/><stop offset="0.6" stop-color="#DCAA28"/><stop offset="1" stop-color="#B08016"/>
 </linearGradient>
 <linearGradient id="red" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F01818"/><stop offset="1" stop-color="#D50000"/></linearGradient>
 <linearGradient id="green" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#22C51E"/><stop offset="1" stop-color="#12A912"/></linearGradient>
</defs>
<!-- green C with arrow tip -->
<path fill="url(#green)" d="M33 22 L48 49 L54 49 L60 61 L37 61 L30.6 47.6
  A56 56 0 0 0 23.5 90 L67 90 L73 102 L11.3 102 A70 70 0 0 1 33 22 Z"/>
<!-- red P -->
<path fill="url(#red)" d="M43.5 15.6 A70 70 0 0 1 145.2 61 L85 61 L80 49 L125.5 49
  A56 56 0 0 0 62 23 L78 61 L63 61 Z"/>
<!-- red lower diagonal -->
<path fill="url(#red)" d="M75 90 L89 90 L109.5 138 L93 131 Z"/>
<!-- gold right arrow: top bar + right arc + inner chevron -->
<path fill="url(#gold)" d="M56 68 L146.3 68 A70 70 0 0 1 118 133.6 L108 106 L99 90 L116 90 L122 104
  A56 56 0 0 0 132.3 82 L63 82 Z"/>

<!-- gold bottom arc -->
<path fill="url(#gold2)" d="M18.5 113.5 L36.5 113.5 A56 56 0 0 0 91 128.6 L109.5 138 A70 70 0 0 1 18.5 113.5 Z"/>
'''
def svg(size, bg=None, scale=1.0, radius=0):
    # emblem bbox approx 7..147 -> width 140 centered 77
    s = size*scale/142.0
    tx = size/2 - 77*s; ty = size/2 - 77*s
    bgel=''
    if bg=='square': bgel=f'<rect width="{size}" height="{size}" fill="#FFFFFF"/>'
    elif bg=='round': bgel=f'<rect width="{size}" height="{size}" rx="{size*radius}" fill="#FFFFFF"/>'
    elif bg=='circle': bgel=f'<circle cx="{size/2}" cy="{size/2}" r="{size/2}" fill="#FFFFFF"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{bgel}<g transform="translate({tx:.3f},{ty:.3f}) scale({s:.5f})">{EMB}</g></svg>'
def png(path, size, **kw):
    cairosvg.svg2png(bytestring=svg(size,**kw).encode(), write_to=path, output_width=size, output_height=size)

# ---------------------------------------------------------------------------
# Generate semua ikon aplikasi dari emblem vektor di atas.
# Jalankan dari root repo:  pip install cairosvg pillow && python3 tool/gen_icons.py all
# ---------------------------------------------------------------------------
def generate_all(root='.'):
    import os, json, io
    from PIL import Image
    j = lambda *p: os.path.join(root, *p)
    # Sumber vektor
    open(j('design/icon/emblem.svg'),'w').write(svg(512, scale=1.0))
    open(j('design/icon/app-icon.svg'),'w').write(svg(512, bg='round', radius=0.22, scale=0.84))
    # Android legacy + round
    res = j('mobile/android/app/src/main/res')
    for d, px in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
        png(f'{res}/mipmap-{d}/ic_launcher.png', px, bg='round', radius=0.22, scale=0.80)
        png(f'{res}/mipmap-{d}/ic_launcher_round.png', px, bg='circle', scale=0.78)
        png(f'{res}/mipmap-{d}/ic_launcher_foreground.png', int(px*108/48), scale=0.58)
    # iOS (tanpa alpha)
    ios = j('mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset')
    for im in json.load(open(f'{ios}/Contents.json'))['images']:
        if 'filename' not in im: continue
        px = round(float(im['size'].split('x')[0]) * int(im['scale'][0]))
        buf = io.BytesIO(cairosvg.svg2png(bytestring=svg(px, bg='square', scale=0.80).encode(), output_width=px, output_height=px))
        Image.open(buf).convert('RGB').save(f'{ios}/{im["filename"]}')
    # Web PWA
    pub = j('web/public')
    png(f'{pub}/icon-192.png', 192, bg='round', radius=0.22, scale=0.84)
    png(f'{pub}/icon-512.png', 512, bg='round', radius=0.22, scale=0.84)
    png(f'{pub}/icon-maskable-192.png', 192, bg='square', scale=0.62)
    png(f'{pub}/icon-maskable-512.png', 512, bg='square', scale=0.62)
    png(f'{pub}/apple-touch-icon.png', 180, bg='square', scale=0.80)
    open(f'{pub}/favicon.svg','w').write(svg(64, scale=1.0))
    ico = [Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg(n, scale=1.0).encode(), output_width=n, output_height=n))) for n in (48,32,16)]
    ico[0].save(f'{pub}/favicon.ico', sizes=[(16,16),(32,32),(48,48)], append_images=ico[1:])

if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == 'all':
    generate_all(sys.argv[2] if len(sys.argv) > 2 else '.')
