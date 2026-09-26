# 0.2.1-beta

- Fix a fade error caused by the unavailable MouseIsOver global. Use the frame method and skip hover checks when fading is off or settings previews are open.

- Add optional fading after a configurable number of seconds, with hover-to-show and always-visible settings previews. Off by default; default time is 10 seconds.

- Add Night Watch Torch to Options > AddOns, with a button to open settings and movable previews.

- Add a small X on the Light Torch button to hide the helper until enabled again.
- Add Show torch helper in settings to restore it and clear any hide timer.

# 0.2.0-beta

- Add an optional smaller Hide button, off by default. Hide duration defaults to 5 minutes.
- Add a settings window with configurable hide duration and delay after combat. Default delay: 0 seconds.
- Show movable previews in settings outside combat; the Hide preview appears only when enabled.
- Save each button position separately and preserve the hide timer across reloads.
- Add controls to clear the hide timer and reset button positions.
- Simulated checks passed; the new settings and movement still need in-game verification.

# 0.1.0-beta

- First public beta for WoW Forever 1.60.1.
- One-click torch reminder after combat, with checks for your bag, zone, buff, and cooldown.
- Duskwood by default, with `/nwt zone` to choose your current zone.
- Simple commands to turn the helper on or off.
- Initial in-game use reported working by the user.
