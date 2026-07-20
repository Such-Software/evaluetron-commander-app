# Brand system

Evaluetron Commander uses the Evaluetron signal mark: a bounded pulse line representing work entering,
being evaluated, and leaving a controlled system. Commander uses blue and violet to distinguish
operator surfaces from Worker while retaining the same mark, dark foundation, lockup, and geometry.

## Palette

| Token | Value | Use |
| --- | --- | --- |
| Commander accent | `#718CFF` | Primary actions, selected state, mark start |
| Commander depth | `#6F54DD` | Mark gradient and supporting accents |
| Signal | `#FFB65C` | Attention that is not an error |
| Void | `#080B12` | Dark application and icon foundation |
| Light surface | `#F5F7FC` | Light application foundation |

The role label is uppercase with expanded tracking. The Evaluetron name remains lowercase. Product
copy uses the platform system typeface so text remains native, accessible, and compact across phones,
tablets, and keyboard/mouse desktops.

## Assets

`brand/evaluetron-commander-icon.svg` is the source for launcher and launch-screen raster assets.
Regenerate checked-in platform assets from the repository root:

```sh
./tool/generate_brand_assets.sh
```

The script requires `rsvg-convert`. Do not stretch, rotate, recolor, outline, or place text inside the
mark. Keep the pulse white and preserve the supplied safe area. UI marks smaller than 24 logical pixels
should be avoided. State and role must never be communicated by color alone.
