# CLAUDE.md

Context for picking this project up later. The user-facing docs are in README.md; this file covers how the image is built, how to test changes, and what to watch for.

## What this is

A Docker image, `ghcr.io/drakknar/db-fakedisplay`: Birte Kristina Friesel's [DBF](https://github.com/derf/db-fakedisplay) (db-fakedisplay, "spdbf" in the author's setup), rebuilt automatically from `derfnull/db-fakedisplay:latest` with small local patches. It runs on the author's Unraid server and serves the DBF web frontend plus the JSON endpoints used by `Drakknar/ha-spdbf-nearby` and db_infoscreen.

**Policy:** never fork upstream's code. Changes are patch scripts applied to the upstream image, so upstream updates keep flowing in. The author wants upstream changes to always be re-applied with the patches, the same as `Drakknar/ha-dbf-departures-card`.

```
Dockerfile                  FROM the upstream image (exact digest passed by the workflow), runs every patches/*.pl
                            against lib/DBInfoscreen/Controller/Stationboard.pm, then `perl -c` on the result
patches/
  hafas-geolocation-coordinates.pl   POST /_geolocation also returns lat/lon for HAFAS stops (BVG etc.)
  default-db-bvg.pl                  Every frontend search includes DB and BVG by default
.github/workflows/build.yml         Decide, build, smoke-test, publish
README.md
```

## Patches

- **Patch scripts, not diffs:** each patch is a Perl script that edits `Stationboard.pm` in place. It must `die` when the code it expects isn't found, so an upstream change fails the build instead of silently doing nothing. Each script first checks whether upstream already has the change; if so it prints a note and exits 0, so a patch upstream adopts doesn't break the build (delete the script then). The Dockerfile uses `set -e;` with plain `;` separators on purpose: `set -e` is ignored inside `&&` chains.
- **`hafas-geolocation-coordinates.pl`:** upstream's `/_geolocation` returns coordinates only for IRIS (DB) stations. With this patch HAFAS candidates carry `lat`/`lon` too. `ha-spdbf-nearby` needs it to place BVG stops on the map.
- **`default-db-bvg.pl`:**
  - **DB + BVG everywhere:** every web UI search includes DB and BVG by default, a firm preference of the author's. A typed station name shows one list of DB and BVG matches labelled "(DB)" and "(BVG)", and a single match opens its board directly.
  - **Nearby stops** show DB + BVG instead of upstream's DB + ÖBB, and `hafas=1` means BVG.
  - **Unchanged:** train numbers, an explicitly chosen backend and direct board URLs work as upstream.
  - **Other networks:** `DBFAKEDISPLAY_DEFAULT_HAFAS` on the container selects another HAFAS service.

## How the build works

`.github/workflows/build.yml` runs every 6 hours, on push to `main` and on demand (with an optional `force`).

1. **Build key:** upstream manifest digest + hash of `Dockerfile` and `patches/**`. It is compared with the `net.stefanopignataro.build-key` label on the published `:latest`. If they match, nothing happens.
2. **Build** a local test image from the exact upstream digest.
3. **Smoke test** against live DB/BVG data near Berlin Hbf:
   - BVG candidates from `/_geolocation` have coordinates.
   - The default nearby search returns DB and BVG and no ÖBB.
   - A typed search (`Alexanderplatz`) lists both "(DB)" and "(BVG)".
   - BVG stop `900100003` redirects to a `hafas=BVG` board, and DB station `8011155` to a board without `hafas=`.
4. **Publish** `:latest` and `:<run number>` (for rollback) only if the smoke test passed. Otherwise the next scheduled run retries.

## Testing changes locally

```bash
docker build -t dbf-test .
docker run -d --name dbf -p 8092:8092 -e 'DBFAKEDISPLAY_LISTEN=http://*:8092' dbf-test
# then run the curl/jq checks from the workflow's "Smoke test" step against http://localhost:8092
docker rm -f dbf
```

A patch script can also be run directly against a copy of upstream's `Stationboard.pm`, followed by `perl -Ilib -c` in an upstream checkout.

Live data changes: if a smoke test fails without a code change, check whether DB or BVG is down or a station's data changed before touching the patches.

## Deployment

Unraid → Docker → `db-fakedisplay` → Repository `ghcr.io/drakknar/db-fakedisplay:latest`. Unraid's update check picks up new builds. If the GHCR package is ever made private, the server needs `docker login ghcr.io` with a `read:packages` token.

**Licence:** DBF is AGPL-3.0-or-later and this modified version runs as a web service, so this repository must stay public.
