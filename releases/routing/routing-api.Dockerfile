FROM --platform=$BUILDPLATFORM golang:1-alpine AS builder

ARG TARGETOS TARGETARCH

COPY --from=src . /routing-api
WORKDIR /routing-api/

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/routing-api routing-api

FROM alpine:latest

COPY --from=builder /usr/local/bin/routing-api /usr/local/bin

RUN apk add --no-cache jq

ENTRYPOINT [ "/usr/local/bin/routing-api" ]
CMD [ "--config", "/routing-api/routing-api.yaml", "--ip", "${POD_IP}"]
