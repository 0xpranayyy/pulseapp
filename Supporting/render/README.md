# Design render

A browser reproduction of Pulse's screens, used to review the design without
a Mac. **It is not the app** — it is HTML built from the same inputs the app
uses, so colour, type and proportion are faithful while behaviour is not.

It reads:

* theme hexes parsed straight out of `PulseCore/.../Design/Palette.swift`,
* the bundled Allo faces (woff2 of the same outlines the app ships as OTF),
* layout constants copied from `Typography.swift`,
* live market data from the Gamma API.

Because the palette is parsed rather than retyped, the render cannot drift
from the app's colours without the parse failing.

## Running it

```sh
cd Supporting/render && node build.js && node shot.js
```

## What it cannot show

Liquid Glass. The browser's `backdrop-filter` is blur plus a wash, which is
the same idea, but iOS 26 adds specular edges and refraction that only
appear on device.
