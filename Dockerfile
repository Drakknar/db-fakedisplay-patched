# Upstream DBF image plus local patches. The workflow passes the exact upstream
# digest it checked, so each build is reproducible.
ARG BASE_IMAGE=derfnull/db-fakedisplay:latest
FROM ${BASE_IMAGE}

COPY patches/ /tmp/patches/

RUN set -e \
	&& perl /tmp/patches/hafas-geolocation-coordinates.pl lib/DBInfoscreen/Controller/Stationboard.pm \
	&& perl -Ilib -c lib/DBInfoscreen/Controller/Stationboard.pm \
	&& rm -rf /tmp/patches
