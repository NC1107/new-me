FROM golang:1.26-alpine AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/server ./cmd/server
RUN mkdir -p /out/voice

FROM gcr.io/distroless/static-debian12:nonroot
LABEL org.opencontainers.image.source="https://github.com/NC1107/new-me"
WORKDIR /app
COPY --from=build /out/server /app/server
# A named volume copies this folder's owner on first use, so the nonroot server can cache voice lines in it.
COPY --from=build --chown=nonroot:nonroot /out/voice /data/voice
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
