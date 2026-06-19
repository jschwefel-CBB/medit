# App Store listing assets

Account-independent material for the Mac App Store listing.

- **`LISTING.md`** — name, subtitle, description, keywords, promo text, privacy,
  category, price (Free). Field lengths verified against App Store limits.
- **`screenshots/`** — five 1280×800 (16:10) App Store screenshots, composed from
  the captured app shots in `../images/` with captions. 1280×800 is a valid Mac
  App Store screenshot size; upload these (App Store Connect also accepts 1440×900,
  2560×1600, 2880×1800).
- **`make-screenshots.sh`** — regenerates the screenshots from the source shots
  (requires ImageMagick). Re-run after updating `../images/`.

These need no developer account. The build/signing side lives in
`../APP-STORE-SUBMISSION.md` and `scripts/`.
