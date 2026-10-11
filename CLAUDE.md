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
