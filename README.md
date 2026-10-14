# db-fakedisplay (patched)

[DBF](https://github.com/derf/db-fakedisplay) by Birte Kristina Friesel, rebuilt automatically with small local patches.

## Patches

| Patch | What it changes |
|---|---|
| `hafas-geolocation-coordinates.pl` | `POST /_geolocation` also returns `lat`/`lon` for HAFAS stops (BVG etc.), not only for DB/IRIS stations. Needed to show those stops on a map. |
| `hafas-trip-id.pl` | HAFAS departures in the JSON board (`?mode=json`) carry `tripId`, which opens the trip's details: `GET /z/<tripId>.json?hafas=<service>`. Upstream uses this id in its HTML board but leaves it out of the JSON. Used by the trip view in `ha-spdbf-nearby`. |
| `station-name-search.pl` | `POST /_geolocation` with `q=<name>` instead of `lat`/`lon` returns the DB stations and the HAFAS stops (`hafas=X`, e.g. BVG) matching that name, in the same JSON format, with EVA numbers and coordinates. Upstream only lists name matches as an HTML page. Used by the stop search in `ha-spdbf-nearby`. |

The patches are kept small on purpose. The web UI behaves as upstream's; only these JSON additions differ. Upstream doesn't take changes from outside for now, so they live here.

Each patch fails the build if upstream code changes and the patch no longer applies. Before publishing, the workflow also starts the image and checks the patched behaviour against live DB/BVG data. Either way, a broken image never gets published.

## How it builds

`.github/workflows/build.yml` runs every 6 hours and on demand (Actions → Build patched image → Run workflow).
It compares the current `derfnull/db-fakedisplay:latest` digest and a hash of this repo's patches with the label on the last published image. It only builds when one of them changed.

Published tags:

- `ghcr.io/<owner>/db-fakedisplay:latest`
- `ghcr.io/<owner>/db-fakedisplay:<run number>`, so you can roll back to an earlier build

## Using it on Unraid

1. Docker tab → `db-fakedisplay` → Edit.
2. Set **Repository** to `ghcr.io/<owner>/db-fakedisplay:latest`. Keep every other setting.
3. Apply. Unraid's normal "check for updates" now picks up new builds.

If the GHCR package is private, run `docker login ghcr.io` on the server once with a token that has `read:packages`.

## Development

How the patch scripts work, how to test a change locally, and what to check when a build fails are in [`CLAUDE.md`](CLAUDE.md).

## Licence

DBF is AGPL-3.0-or-later. Because this modified version runs as a public web service, keep this repository public so its source is available.
