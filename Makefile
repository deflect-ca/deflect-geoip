.PHONY: build run clean

build:
	go build ./...

run:
	go run ./cmd/build-countrydb --out dist

clean:
	rm -rf dist
