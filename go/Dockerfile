FROM golang:1.22.2-bullseye
ENV CGO_ENABLED 1

RUN apt-get update \
    && apt-get install -y --no-install-recommends inotify-tools psmisc \
    && go install github.com/go-delve/delve/cmd/dlv@latest

COPY scrip.sh /entrypoint.sh

ENV DELVE_PORT 40000

EXPOSE $DELVE_PORT

ENTRYPOINT ["/entrypoint.sh"]
