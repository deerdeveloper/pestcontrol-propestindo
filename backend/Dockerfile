FROM golang:1.26-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/api ./cmd/api && CGO_ENABLED=0 go build -o /out/seed ./cmd/seed

# Chromium dibutuhkan untuk mencetak PDF laporan.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends chromium fonts-dejavu-core ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/ /usr/local/bin/
ENV CHROME_PATH=/usr/bin/chromium STORAGE_DIR=/data TZ=Asia/Jakarta
VOLUME /data
EXPOSE 8080
CMD ["api"]
