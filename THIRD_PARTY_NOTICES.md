# Third-party notices

## Excalidraw

Macdraw contains no Excalidraw code — it is a Swift/AppKit application and
Excalidraw is React/TypeScript. Three things are nonetheless derived from it
and are acknowledged here.

**The colour palette.** The hex values in `Sources/Canvas/Colors.swift` are
`COLOR_PALETTE` from `packages/common/src/colors.ts`, value for value: open-color
at weights 50/200/400/600/800, plus the radix bronze shades, plus Excalidraw's
default stroke/background quick picks and its 5x3 picker ordering.

**Render parameters.** Several constants are taken from
`packages/element/src/shape.ts` and `packages/common/src/constants.ts` so that
shapes drawn in Macdraw match what the same settings produce in Excalidraw:
the dashed and dotted dash arrays (`[8, 8 + strokeWidth]` and a 1.5pt dot every
`6 + strokeWidth`), the hachure spacing and pen weight (`strokeWidth * 4` and
`strokeWidth / 2`), the `ROUGHNESS` levels behind Architect/Artist/Cartoonist,
and the `STROKE_WIDTH` and `FONT_SIZES` presets. The hand-drawn geometry itself
is an independent implementation of the Rough.js approach, not a port.

**The text-to-diagram interaction flow.** Macdraw's drawer follows the shape of
Excalidraw's text-to-diagram dialog — prompt/chat, preview, then explicit
insertion into the canvas.

Excalidraw is licensed under the MIT License.

Copyright (c) 2020 Excalidraw

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
