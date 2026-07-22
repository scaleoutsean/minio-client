FROM golang:1.26-alpine AS build

LABEL maintainer="scaleoutSean <scaleoutsean@users.noreply.github.com>"

ENV GOPATH=/go
ENV CGO_ENABLED=0


RUN apk add -U --no-cache ca-certificates
RUN apk add -U git

WORKDIR /src

COPY . .

RUN LDFLAGS="$(go run buildscripts/gen-ldflags.go 2>/dev/null || echo '-s -w')" && \
	go build -v -trimpath -o /go/bin/mc -ldflags "$LDFLAGS" .
RUN cp LICENSE /go/LICENSE && cp CREDITS /go/CREDITS

FROM scratch

COPY --from=build /go/bin/mc  /usr/bin/mc
COPY --from=build /go/CREDITS /licenses/CREDITS
COPY --from=build /go/LICENSE /licenses/LICENSE
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

ENTRYPOINT ["mc"]
