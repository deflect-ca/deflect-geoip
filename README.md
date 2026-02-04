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
