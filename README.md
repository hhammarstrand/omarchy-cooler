# Omarchy Cooler

Omarchy bar plugin for the **Corsair Hydro H100i Pro** (USB `1b1c:0c15`).
Shows liquid temperature in the bar and opens a native panel for pump mode,
fan speed, and logo RGB.

The USB product string often says "H100i Platinum". That ID is the Pro.

## Install

Requires [liquidctl](https://github.com/liquidctl/liquidctl) and a session
with access to the cooler USB device (the `liquidctl` package ships udev
rules for this).

```bash
omarchy pkg add liquidctl
omarchy plugin add https://github.com/hhammarstrand/omarchy-cooler.git --enable
omarchy bar move hhammarstrand.cooler --section right --before omarchy.power
```

Optional: re-apply saved pump, fan, and logo settings after login.

```bash
omarchy hook install post-boot hooks/apply-cooler
```

Run that from the plugin directory, or copy `hooks/apply-cooler` first.

## Usage

| Input | Action |
| --- | --- |
| Left click | Open / close the panel |
| Right click | Cycle bar: temperature, fan rpm, pump rpm |
| Scroll | Fan speed ±5% |
| Middle click | Refresh status |

In the panel:

- **Pump mode:** Quiet, Balanced, Performance
- **Fan speed:** slider for a fixed percent; **Auto** applies a liquid-temp curve
- **Logo:** Fixed (one color), Pulse (breathe), Blink (on/off), Shift (two colors)
- Color swatches are saturated so they match the LED ring more closely
- Shift: left-click first color, right-click second color
- Pulse / Blink / Shift show Slower, Normal, Faster

Settings are stored in `~/.config/omarchy/cooler.json`. Fan and pump
firmware curves are left alone until you change them in the panel.

## Hardware

Tested on Corsair H100i Pro, firmware `1.0.4.0`, via `liquidctl` 1.16.

## License

MIT
