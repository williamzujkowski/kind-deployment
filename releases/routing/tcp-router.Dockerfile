FROM --platform=$BUILDPLATFORM golang:1-alpine AS builder

ARG TARGETOS TARGETARCH

COPY --from=src . /routing-release/src
WORKDIR /routing-release/src/code.cloudfoundry.org

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/tcp-router code.cloudfoundry.org/cf-tcp-router

FROM alpine:latest

COPY --from=builder /usr/local/bin/tcp-router /usr/local/bin

RUN apk add --no-cache jq

ENTRYPOINT [ "/usr/local/bin/tcp-router" ]
CMD [ "--config", "/tcp-router/tcp-router.yaml" ]
