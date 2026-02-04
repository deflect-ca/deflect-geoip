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
	client := &http.Client{Timeout: 5 * time.Minute}
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
