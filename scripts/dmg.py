# dmgbuild settings for build/Stash.dmg. Run from the repo root:
#   dmgbuild -s scripts/dmg.py Stash build/Stash.dmg
# The window size matches App/DMG/background.svg; the icon positions match its arrow.
app = 'build/Stash.app'
files = [app]
symlinks = {'Applications': '/Applications'}
icon = f'{app}/Contents/Resources/AppIcon.icns'
background = 'App/DMG/background.tiff'
format = 'UDZO'
window_rect = ((200, 120), (660, 400))
icon_size = 112
text_size = 13
hide_extensions = ['Stash.app']
icon_locations = {'Stash.app': (170, 190), 'Applications': (490, 190)}
