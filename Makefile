.PHONY: test web-test app-test build publish backend android clean

test:
	cd backend && go vet ./... && go test -race ./...

web-test:
	cd web && npm ci && npm run build

app-test:
	cd mobile && flutter pub get && flutter analyze && flutter test

# Satu perintah: backend (server Orange Pi ARM64 + AMD64, web tertanam) + android (hasil di dist/).
# Lihat tool/build.sh untuk konfigurasi (~/.propestindo/build.env atau tool/build.env).
build:
	tool/build.sh all

# make publish TAG=v0.2.0 : build lokal lalu terbitkan ke GitHub Release (tanpa Actions)
publish:
	tool/publish.sh $(TAG)

backend:
	tool/build.sh backend

android:
	tool/build.sh android

clean:
	rm -rf dist .build
	find backend/internal/webui/dist -mindepth 1 ! -name .gitkeep -delete
