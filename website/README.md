# VenueVibe — website landing page

Static landing page with a **live venue browser** (search, sort, category
filters, detail modal) reading public data straight from Supabase with the
anon key — the same RLS-protected publishable key the mobile app ships with.
No build step, no server-side code: any static/PHP shared host works.

## Files

| File | Purpose |
|---|---|
| `index.html` | Page structure: hero + search, venue browser, how-it-works, app CTA, venue-owner section, footer, detail modal |
| `styles.css` | All styling (brand: navy `#1B2A4A`, purple `#7C3AED`) |
| `app.js` | Supabase client, data load, search/sort/filter, rendering |

## Deploy (FTP)

Upload the **contents** of this folder (`index.html`, `styles.css`,
`app.js`) to the web root (usually `public_html/` or `www/`). Nothing else
is needed. To update: re-upload the changed files.

## Notes

- Pricing shown is the season covering **today** (same logic as the app).
- "Book in the app" buttons link to the latest GitHub release:
  `https://github.com/fabtechonline/venuvibe/releases/latest` — update
  `APP_URL` in `app.js` when the store listing exists.
- The full web app (booking, sign-in, portals) is intended to be wired into
  this shell later; the data layer (`supabase-js`) is already in place.
