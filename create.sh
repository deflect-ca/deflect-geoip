#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   mkdir -p deflect-geoip && cd deflect-geoip
#   bash ./bootstrap.sh
#
# This script creates the deflect-geoip repo files (GitHub Pages / gh-pages build).

write_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
'"$@"'
EOF
}

# Safer writer (no weird quoting)
write() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
EOF
}

# Helper: write from heredoc directly (preferred)
wf() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

wf "README.md" <<'EOF'
# deflect-geoip

Country-only IP prefix database for Deflect / Baskerville.

This repository builds and publishes a country-level IP prefix database
derived from public RIR delegated statistics.
The output is static, data-only, and published via GitHub Pages (gh-pages).

## Outputs

- releases/latest.json
- releases/YYYY-MM-DD/countrydb.csv.gz
- releases/YYYY-MM-DD/countrydb.csv.gz.sha256

Base URL:
https://equalitie.github.io/deflect-geoip/

## Format

CSV (gzipped), UTF-8:

prefix,country
1.0.0.0/24,AU
2a00:1450::/32,US

## Data sources

ARIN, RIPE NCC, APNIC, LACNIC, AFRINIC (delegated extended stats).

## Notes

Country reflects allocation / assignment country in RIR data.
This dataset contains no personal data and no executable code.
EOF

wf "go.mod" <<'EOF'
module github.com/equalitie/deflect-geoip

go 1.22
EOF

wf "Makefile" <<'EOF'
.PHONY: build run clean

build:
	go build ./...

run:
	go run ./cmd/build-countrydb --out dist

clean:
	rm -rf dist
EOF

wf "internal/rir/sources.go" <<'EOF'
package rir

var Sources = map[string]string{
	"arin":    "https://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest",
	"ripe":    "https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest",
	"apnic":   "https://ftp.apnic.net/stats/apnic/delegated-apnic-extended-latest",
	"lacnic":  "https://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-extended-latest",
	"afrinic": "https://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-extended-latest",
}
EOF

wf "internal/rir/parse.go" <<'EOF'
package rir

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
)

type Record struct {
	Prefix  string
	Country string
}

func ParseDelegatedExtended(r io.Reader) ([]Record, error) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)

	var out []Record

	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// registry|cc|type|start|value|date|status|...
		parts := strings.Split(line, "|")
		if len(parts) < 7 {
			continue
		}

		cc := strings.ToUpper(parts[1])
		typ := parts[2]
		start := parts[3]
		value := parts[4]
		status := parts[6]

		if status != "allocated" && status != "assigned" {
			continue
		}
		if !isCountryCode(cc) || cc == "ZZ" {
			continue
		}

		switch typ {
		case "ipv4":
			out = append(out, ipv4RangeToCIDRs(start, value, cc)...)
		case "ipv6":
			if rec, ok := ipv6ToCIDR(start, value, cc); ok {
				out = append(out, rec)
			}
		}
	}

	return out, sc.Err()
}

func isCountryCode(cc string) bool {
	if len(cc) != 2 {
		return false
	}
	for _, r := range cc {
		if r < 'A' || r > 'Z' {
			return false
		}
	}
	return true
}

// Split an IPv4 range into the minimal set of CIDRs.
// start = IPv4 address, value = count of addresses.
func ipv4RangeToCIDRs(start, value, cc string) []Record {
	ip := net.ParseIP(start)
	if ip == nil {
		return nil
	}
	ip4 := ip.To4()
	if ip4 == nil {
		return nil
	}

	count, err := strconv.Atoi(value)
	if err != nil || count <= 0 {
		return nil
	}

	startU := ipToUint32(ip4)
	endU := startU + uint32(count) - 1

	var out []Record
	cur := startU

	for cur <= endU {
		prefix := 32
		for prefix > 0 {
			block := uint32(1) << (32 - prefix)
			// Must be aligned and must fit inside [cur, endU]
			if cur%block != 0 || cur+block-1 > endU {
				prefix--
				continue
			}
			break
		}

		out = append(out, Record{
			Prefix:  fmt.Sprintf("%s/%d", uint32ToIP(cur), prefix),
			Country: cc,
		})

		cur += uint32(1) << (32 - prefix)
	}

	return out
}

func ipv6ToCIDR(start, value, cc string) (Record, bool) {
	ip := net.ParseIP(start)
	if ip == nil || ip.To4() != nil {
		return Record{}, false
	}
	pfx, err := strconv.Atoi(value)
	if err != nil || pfx < 0 || pfx > 128 {
		return Record{}, false
	}
	return Record{
		Prefix:  fmt.Sprintf("%s/%d", start, pfx),
		Country: cc,
	}, true
}

func ipToUint32(ip net.IP) uint32 {
	return uint32(ip[0])<<24 |
		uint32(ip[1])<<16 |
		uint32(ip[2])<<8 |
		uint32(ip[3])
}

func uint32ToIP(v uint32) string {
	return fmt.Sprintf("%d.%d.%d.%d",
		byte(v>>24),
		byte(v>>16),
		byte(v>>8),
		byte(v),
	)
}
EOF

wf "cmd/build-countrydb/main.go" <<'EOF'
package main

import (
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/equalitie/deflect-geoip/internal/rir"
)

type Latest struct {
	Name        string     `json:"name"`
	Version     string     `json:"version"`
	GeneratedAt time.Time  `json:"generated_at"`
	Sources     []string   `json:"sources"`
	Artifacts   []Artifact `json:"artifacts"`
}

type Artifact struct {
	Type   string `json:"type"`
	Path   string `json:"path"`
	Sha256 string `json:"sha256"`
	Bytes  int64  `json:"bytes"`
}

func main() {
	out := flag.String("out", "dist", "output directory")
	version := flag.String("version", time.Now().UTC().Format("2006-01-02"), "version")
	flag.Parse()

	recs, sources := build()
	sort.Slice(recs, func(i, j int) bool { return recs[i].Prefix < recs[j].Prefix })

	releaseDir := filepath.Join(*out, "releases", *version)
	must(os.MkdirAll(releaseDir, 0o755))

	gz := filepath.Join(releaseDir, "countrydb.csv.gz")
	bytes, sha := writeCSVGZ(gz, recs)

	must(os.WriteFile(gz+".sha256", []byte(fmt.Sprintf("%s  countrydb.csv.gz\n", sha)), 0o644))

	latest := Latest{
		Name:        "deflect-geoip-country",
		Version:     *version,
		GeneratedAt: time.Now().UTC(),
		Sources:     sources,
		Artifacts: []Artifact{{
			Type:   "countrydb.csv.gz",
			Path:   fmt.Sprintf("releases/%s/countrydb.csv.gz", *version),
			Sha256: sha,
			Bytes:  bytes,
		}},
	}

	must(os.MkdirAll(filepath.Join(*out, "releases"), 0o755))
	writeJSON(filepath.Join(*out, "releases", "latest.json"), latest)
}

func build() ([]rir.Record, []string) {
	client := &http.Client{Timeout: 60 * time.Second}
	var all []rir.Record
	var src []string

	for name, url := range rir.Sources {
		resp, err := client.Get(url)
		must(err)
		recs, err := rir.ParseDelegatedExtended(resp.Body)
		resp.Body.Close()
		must(err)
		all = append(all, recs...)
		src = append(src, name+"-delegated")
	}

	seen := map[string]string{}
	var out []rir.Record
	for _, r := range all {
		if prev, ok := seen[r.Prefix]; ok && prev != r.Country {
			panic("country conflict for prefix " + r.Prefix)
		}
		if _, ok := seen[r.Prefix]; !ok {
			seen[r.Prefix] = r.Country
			out = append(out, r)
		}
	}
	sort.Strings(src)
	return out, src
}

func writeCSVGZ(path string, records []rir.Record) (int64, string) {
	f, err := os.Create(path)
	must(err)
	defer f.Close()

	h := sha256.New()
	mw := io.MultiWriter(f, h)
	gw := gzip.NewWriter(mw)

	_, _ = gw.Write([]byte("prefix,country\n"))
	for _, r := range records {
		_, _ = gw.Write([]byte(r.Prefix + "," + r.Country + "\n"))
	}
	must(gw.Close())

	st, err := os.Stat(path)
	must(err)
	return st.Size(), hex.EncodeToString(h.Sum(nil))
}

func writeJSON(path string, v any) {
	b, err := json.MarshalIndent(v, "", "  ")
	must(err)
	must(os.WriteFile(path, append(b, '\n'), 0o644))
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
EOF

wf ".github/workflows/build-and-publish.yml" <<'EOF'
name: Build and publish countrydb

on:
  workflow_dispatch: {}
  schedule:
    - cron: "17 3 * * 1"

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: "1.22"
      - name: Build database
        run: |
          VERSION="$(date -u +%F)"
          go run ./cmd/build-countrydb --out dist --version "$VERSION"
      - name: Publish to GitHub Pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_branch: gh-pages
          publish_dir: dist
          force_orphan: true
EOF

echo "✅ deflect-geoip scaffold created."
echo "Next:"
echo "  1) git init && git add . && git commit -m 'Initial deflect-geoip builder'"
echo "  2) git remote add origin git@github.com:equalitie/deflect-geoip.git"
echo "  3) git push -u origin main"
echo "  4) Enable Pages: Settings → Pages → Branch: gh-pages / root"
echo "  5) Run workflow: Actions → Build and publish countrydb → Run workflow"
