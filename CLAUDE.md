# CLAUDE.md

Context for picking this project up later. The user-facing docs are in README.md; this file covers how the image is built, how to test changes, and what to watch for.

## What this is

A Docker image, `ghcr.io/drakknar/db-fakedisplay`: Birte Kristina Friesel's [DBF](https://github.com/derf/db-fakedisplay) (db-fakedisplay, "spdbf" in the author's setup), rebuilt automatically from `derfnull/db-fakedisplay:latest` with small local patches. It runs on the author's Unraid server and serves the DBF web frontend plus the JSON endpoints used by `Drakknar/ha-spdbf-nearby` and db_infoscreen.

**Policy:** never fork upstream's code. Changes are patch scripts applied to the upstream image, so upstream updates keep flowing in. The author wants upstream changes to always be re-applied with the patches, the same as `Drakknar/ha-dbf-departures-card`.

**Minimal patches (since 2026-10-14):** only what `ha-spdbf-nearby` needs, as small JSON additions; the web UI stays upstream's. The upstream maintainer doesn't want outside changes for now, so don't propose patches upstream. `default-db-bvg.pl` (web UI searches DB + BVG by default, `hafas=1` = BVG, 77 changed lines) was removed then: the Home Assistant stop search replaced it, and nothing there relied on it. The three patches change about 90 lines of `Stationboard.pm`.

```
Dockerfile                  FROM the upstream image (exact digest passed by the workflow), runs every patches/*.pl
                            against lib/DBInfoscreen/Controller/Stationboard.pm, then `perl -c` on the result
patches/
  hafas-geolocation-coordinates.pl   POST /_geolocation also returns lat/lon for HAFAS stops (BVG etc.)
  hafas-trip-id.pl                   HAFAS departures in the JSON board carry tripId (for /z/<tripId>.json)
  station-name-search.pl             POST /_geolocation with q=<name>: stop search by name as JSON
.github/workflows/build.yml         Decide, build, smoke-test, publish
README.md
```

## Patches

- **Patch scripts, not diffs:** each patch is a Perl script that edits `Stationboard.pm` in place. It must `die` when the code it expects isn't found, so an upstream change fails the build instead of silently doing nothing. Each script first checks whether upstream already has the change; if so it prints a note and exits 0, so a patch upstream adopts doesn't break the build (delete the script then). The Dockerfile uses `set -e;` with plain `;` separators on purpose: `set -e` is ignored inside `&&` chains.
- **`hafas-geolocation-coordinates.pl`:** upstream's `/_geolocation` returns coordinates only for IRIS (DB) stations. With this patch HAFAS candidates carry `lat`/`lon` too. `ha-spdbf-nearby` needs it to place BVG stops on the map.
- **`hafas-trip-id.pl`:** the HAFAS branch of the JSON board gets `tripId => $result->id`.
  - **Use:** `GET /z/<tripId>.json?hafas=<service>` returns the trip (`journey` with its stops).
  - **Why:** upstream already puts this id in its HTML board's trip links, but not in the JSON, and HAFAS trips can't be looked up by line and number (`NO_MATCH`, checked 2026-10-14).
  - **DB (IRIS) trips** need no patch: `/z/<type> <number>/<station>.json` works with the board's train name and number.
  - **Who uses it:** `ha-spdbf-nearby`'s trip view, which replaces the Transitous trip popup.
- **`station-name-search.pl`:**
  - **What:** `POST /_geolocation` with `q=<name>` and `hafas=X` (upstream's default, ÖBB, if not given) returns the DB (IRIS) stations, then the HAFAS stops, matching that name. The format is the coordinate search's, without `distance`: DB entries carry EVA numbers (not DS100 codes), and every entry has `lat`/`lon`. `ha-spdbf-nearby` uses it for its stop search.
  - **Why:** upstream only offers name matches as an HTML `<select>` on the landing page, and its JSON mode returns just an error for ambiguous names.
  - **Route:** it reuses `/_geolocation` so every patch stays within `Stationboard.pm`.
  - **Details:** queries shorter than 2 or longer than 100 characters return no candidates (the IRIS lookup compares the query with every station, so a long POST body would block a worker). DB matches whose name contains the query (or whose DS100/EVA equals it) win; `get_station`'s closest-by-Levenshtein extras (e.g. "Neanderthal" for "Alexanderplatz") are kept only when nothing contains the query, as a typo fallback. DB matches are capped at 10, and a HAFAS "no match" (`LOCATION` error) is not reported as a `warning`.
  - **Already applied?** Only the patch's own `Patched (station-name-search.pl)` marker counts; a matching function name doesn't.
  - **Upstream clashes stop the build** with a message to check by hand: upstream defining its own `stations_by_name`, or reading a `q` parameter. A second `stations_by_name` would only be a Perl "redefined" warning, so the build would otherwise pass.

## How the build works

`.github/workflows/build.yml` runs every 6 hours and on demand (with an optional `force`).

1. **Build key:** upstream manifest digest + hash of `Dockerfile` and `patches/**`. It is compared with the `net.stefanopignataro.build-key` label on the published `:latest`. If they match, nothing happens.
2. **Build** a local test image from the exact upstream digest.
3. **Smoke test** against live DB/BVG data near Berlin Hbf:
   - BVG candidates from `/_geolocation` have coordinates.
   - The name search (`q=Alexanderplatz`) returns DB station `8011155` and BVG stop `900100003`, both with coordinates, and no DB station without "Alexanderplatz" in its name.
   - A BVG departure at `900100003` carries a `tripId`, and `/z/<tripId>.json?hafas=BVG` returns its journey.
4. **Publish** `:latest` and `:<run number>` (for rollback) only if the smoke test passed. Otherwise the next scheduled run retries.

**When a scheduled build fails** on a new upstream version, the `triage`, `fix` and `report` jobs in the same workflow hand it to Claude (`anthropics/claude-code-action`, secret `CLAUDE_CODE_OAUTH_TOKEN`), which follows `.github/prompts/upstream-fix.md`.
- **Separate access:** Claude works with read-only access. The `report` job turns its verdict and diff into a pull request on a `claude/fix-upstream-*` branch.
- **Checking the fix:** the report job runs `build.yml` on that branch, which never publishes from a branch, waits for it and posts the result on the pull request. If the check fails, the pull request becomes a draft.
- **Issues:** if Claude can't fix the failure, or finds nothing to change while the build still fails, the report job opens an issue. Everything it opens is labelled `upstream-watch` and `upstream-fix` and assigned to the owner, and GitHub emails it.
- **One at a time:** each failing build key is handled once, recorded on the `watch-state` branch by `.github/scripts/watch.sh`. An outage is retried after a day. While an `upstream-fix` pull request or issue is open, new failures aren't sent to Claude, so a new upstream image doesn't produce a second pull request. Close or merge it to re-enable. Failures after the owner's own pushes are never sent to Claude.
- **Write access:** only the `publish` job, which runs on `main` only, can push to the registry. The build and test job runs read-only, because it runs upstream code and, on a branch, fixes proposed by Claude.
- **Isolation (tested 2026-10-11):**
  - **Before Claude runs:** the review job turns on the action's subprocess secret scrub and installs bubblewrap, so Claude's commands don't see the Claude token or any other process. It also blocks reading other processes' memory and removes sudo. Docker stays on because Claude needs it here.
  - **After Claude:** the steps that follow ignore variables and PATH entries its commands could plant, and make the diff in a fresh clone.
  - **Publishing:** the report job won't publish output that contains the token, or a piece of it, and deletes the review's artifact.
  - **What's left:** Claude's commands never see the token, so leaking it would take a way around the sandbox, and Docker, which this job needs, amounts to root and is one. The scan is a second line of defence.

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
