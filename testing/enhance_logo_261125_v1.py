# Created: 2026-11-25
# Purpose: Layer glossy detail (highlights, rim light, depth, layered shadow) over the traced omt logo.
# Dependencies: stdlib only
# Test Status: exploratory
import re
s = open("../omt-logo.svg").read()
body = re.search(r'<clipPath id="clip"><path d="([^"]+)"', s).group(1)
paths = re.findall(r'<path d="([^"]+)" fill="url\(#(left|right)\)"', s)
left = next(d for d, k in paths if k == "left"); right = next(d for d, k in paths if k == "right")
eyes = re.findall(r'<ellipse [^>]+/>', s)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<linearGradient id="bg" gradientUnits="userSpaceOnUse" x1="76" y1="63" x2="946" y2="953"><stop offset="0" stop-color="#1644B4"/><stop offset="1" stop-color="#4238B8"/></linearGradient>
<radialGradient id="bgGlow" gradientUnits="userSpaceOnUse" cx="512" cy="470" r="470"><stop offset="0" stop-color="#6F7DFF" stop-opacity=".22"/><stop offset="1" stop-color="#6F7DFF" stop-opacity="0"/></radialGradient>
<linearGradient id="bgSheen" gradientUnits="userSpaceOnUse" x1="512" y1="63" x2="512" y2="420"><stop offset="0" stop-color="#fff" stop-opacity=".07"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<linearGradient id="body" gradientUnits="userSpaceOnUse" x1="512" y1="200" x2="540" y2="830"><stop offset="0" stop-color="#EDEBFA"/><stop offset=".35" stop-color="#F6F4FD"/><stop offset=".6" stop-color="#F1EFFB"/><stop offset="1" stop-color="#DCD8F1"/></linearGradient>
<radialGradient id="hl" gradientUnits="userSpaceOnUse" cx="430" cy="300" r="260"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".6" stop-color="#fff" stop-opacity=".5"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
<radialGradient id="belly" gradientUnits="userSpaceOnUse" cx="560" cy="860" r="380"><stop offset="0" stop-color="#7A6FD0" stop-opacity=".38"/><stop offset="1" stop-color="#7A6FD0" stop-opacity="0"/></radialGradient>
<linearGradient id="rim" gradientUnits="userSpaceOnUse" x1="300" y1="200" x2="760" y2="840"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".45" stop-color="#fff" stop-opacity=".15"/><stop offset="1" stop-color="#B7B0F0" stop-opacity=".9"/></linearGradient>
<linearGradient id="left" gradientUnits="userSpaceOnUse" x1="293" y1="506" x2="340" y2="822"><stop offset="0" stop-color="#1CD0F0"/><stop offset=".3" stop-color="#1AA9E8"/><stop offset=".55" stop-color="#4C63DC"/><stop offset=".78" stop-color="#9A3FC4"/><stop offset="1" stop-color="#FF3C95"/></linearGradient>
<linearGradient id="right" gradientUnits="userSpaceOnUse" x1="613" y1="661" x2="769" y2="778"><stop offset="0" stop-color="#FF5A3C"/><stop offset=".5" stop-color="#FF7A2A"/><stop offset="1" stop-color="#FF9A2E"/></linearGradient>
<linearGradient id="armShade" gradientUnits="userSpaceOnUse" x1="512" y1="640" x2="512" y2="840"><stop offset="0" stop-color="#fff" stop-opacity=".32"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#1B0A5A" stop-opacity=".28"/></linearGradient>
<filter id="softShadow" x="-25%" y="-25%" width="150%" height="160%">
<feDropShadow dx="0" dy="26" stdDeviation="26" flood-color="#0A1250" flood-opacity=".38"/></filter>
<filter id="contact" x="-20%" y="-20%" width="140%" height="150%">
<feDropShadow dx="0" dy="6" stdDeviation="6" flood-color="#0A1250" flood-opacity=".35"/></filter>
<filter id="blur8"><feGaussianBlur stdDeviation="8"/></filter>
<filter id="blur3"><feGaussianBlur stdDeviation="3"/></filter>
<clipPath id="clip"><path d="{body}"/></clipPath>
</defs>

<rect x="76" y="63" width="871" height="891" rx="175" fill="url(#bg)"/>
<rect x="76" y="63" width="871" height="891" rx="175" fill="url(#bgGlow)"/>
<rect x="76" y="63" width="871" height="891" rx="175" fill="url(#bgSheen)"/>
<rect x="77" y="64" width="869" height="889" rx="174" fill="none" stroke="#fff" stroke-opacity=".18" stroke-width="2"/>

<g filter="url(#softShadow)"><path d="{body}" fill="#fff"/></g>
<g filter="url(#contact)"><path d="{body}" fill="url(#body)"/></g>

<g clip-path="url(#clip)">
  <path d="{body}" fill="url(#belly)"/>
  <path d="{body}" fill="url(#hl)"/>
  <!-- inner shade hugging the lower silhouette -->
  <path d="{body}" fill="none" stroke="#5B4FC0" stroke-opacity=".26" stroke-width="26" filter="url(#blur8)" transform="translate(0,10)"/>
  <path d="{left}" fill="url(#left)"/>
  <path d="{right}" fill="url(#right)"/>
  <path d="{left}" fill="url(#armShade)"/>
  <path d="{right}" fill="url(#armShade)"/>
  <!-- rim light on the top-left edge -->
  <path d="{body}" fill="none" stroke="url(#rim)" stroke-width="7" filter="url(#blur3)" opacity=".9"/>
</g>

<!-- glossy specular on the crown -->
<ellipse cx="420" cy="290" rx="105" ry="52" transform="rotate(-32 420 290)" fill="#fff" opacity=".85" filter="url(#blur8)"/>
<ellipse cx="372" cy="338" rx="26" ry="14" transform="rotate(-32 372 338)" fill="#fff" opacity=".9" filter="url(#blur3)"/>
<!-- soft bounce light on the right bump -->
<ellipse cx="770" cy="668" rx="34" ry="14" transform="rotate(-18 770 668)" fill="#fff" opacity=".55" filter="url(#blur3)"/>

<g fill="#101018">{"".join(eyes)}</g>
</svg>'''
open("../omt-logo-detailed.svg", "w").write(svg)
print(len(svg))
