# Upstream DBF image plus local patches. The workflow passes the exact upstream
# digest it checked, so each build is reproducible.
ARG BASE_IMAGE=derfnull/db-fakedisplay:latest
# The build workflow passes the exact upstream digest as BASE_IMAGE.
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

COPY patches/ /tmp/patches/

# Plain ";" on purpose: "set -e" is ignored inside "&&" chains, which would let
# a failing patch slip through.
RUN set -e; \
	for patch in /tmp/patches/*.pl; do \
		perl "$patch" lib/DBInfoscreen/Controller/Stationboard.pm; \
	done; \
	perl -Ilib -c lib/DBInfoscreen/Controller/Stationboard.pm; \
	rm -rf /tmp/patches
