# db-fakedisplay (patched)

[DBF](https://github.com/derf/db-fakedisplay) by Birte Kristina Friesel, rebuilt automatically with small local patches.

## Patches

| Patch | What it changes |
|---|---|
| `hafas-geolocation-coordinates.pl` | `POST /_geolocation` also returns `lat`/`lon` for HAFAS stops (BVG etc.), not only for DB/IRIS stations. Needed to show those stops on a map. |
| `default-db-bvg.pl` | Every search in the web frontend includes DB and BVG by default. A typed station name shows one list of DB and BVG matches, labelled "(DB)" and "(BVG)"; a single match opens its board directly. Nearby stops show DB + BVG instead of DB + ÖBB, and `hafas=1` means BVG. Train numbers, an explicitly chosen backend and direct board URLs work as upstream. Set `DBFAKEDISPLAY_DEFAULT_HAFAS` on the container to use another HAFAS service. |

Each patch fails the build if upstream code changes and the patch no longer applies. Before publishing, the workflow also starts the image and checks the patched behaviour against live DB/BVG data. Either way, a broken image never gets published.

## How it builds

`.github/workflows/build.yml` runs every 6 hours, on every push to `main`, and on demand (Actions → Build patched image → Run workflow).
It compares the current `derfnull/db-fakedisplay:latest` digest and a hash of this repo's patches with the label on the last published image. It only builds when one of them changed.

Published tags:

- `ghcr.io/<owner>/db-fakedisplay:latest`
- `ghcr.io/<owner>/db-fakedisplay:<run number>`, so you can roll back to an earlier build

## Using it on Unraid

1. Docker tab → `db-fakedisplay` → Edit.
2. Set **Repository** to `ghcr.io/<owner>/db-fakedisplay:latest`. Keep every other setting.
3. Apply. Unraid's normal "check for updates" now picks up new builds.

If the GHCR package is private, run `docker login ghcr.io` on the server once with a token that has `read:packages`.

## Licence

DBF is AGPL-3.0-or-later. Because this modified version runs as a public web service, keep this repository public so its source is available.
