# Source 2D V6 preparation gap

The source 2D lowerer is fail-closed for the current prepared `SELECTFILE`
image.  The final GEFV packet does contain a typed consumable row, but its
decoded payload is entirely zero and therefore cannot produce the visible
File Select title image.

Evidence from `build/native/source-frontend-v6/source-frontend-v6.gefv`:

- category: `texture_payload`
- family: `frontend`
- name: `SELECTFILE.payload`
- record ID: `1480`
- source row: `SELECTFILE`
- linked image-stream record: `1479`
- source SHA-256: `7f0bf6431a2406d5edceabe7722204c374618f72df41119794a939d24d76f09d`
- decoded SHA-256: `2eb78abb1edd521a5a7652ccc0fd16d7aeae8941920f64324bd33b5d6ab26eb6`
- raw size: `907` bytes
- decoded size: `8784` bytes (`122 x 18 x 4`)
- flags: `DECODED_RGBA8_BASE_LEVEL`, `GLOBAL_TEXTURE_PAYLOAD`
- `tex2png` output: gray+alpha `122 x 18` PNG whose decoded scanline bytes are all zero

The source 2D V6 loader throws a typed `preparationGap` for this row rather
than substituting a font, block glyphs, or a synthetic image.  Legal remains
renderable from the validated Zurich packet, and Bank Gothic metrics/pixels
are parsed from the validated `font_payload` rows.  File Select cannot claim
visible source completeness until the `SELECTFILE` decoder/preparation row is
regenerated with non-zero decoded pixels and the packet/manifest hashes are
refreshed.
