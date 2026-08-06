# deflect-geoip

IP prefix database for Deflect / Baskerville — country and ASN data.

This repository builds and publishes two static databases derived from
public RIR delegated statistics and iptoasn.com.
Output is static, data-only, published via GitHub Pages (gh-pages).

## Outputs

- releases/latest.json
- releases/YYYY-MM-DD/countrydb.csv.gz
- releases/YYYY-MM-DD/countrydb.csv.gz.sha256
- releases/YYYY-MM-DD/asndb.csv.gz
- releases/YYYY-MM-DD/asndb.csv.gz.sha256

Base URL:
https://equalitie.github.io/deflect-geoip/

## Formats

### countrydb.csv.gz

CSV (gzipped), UTF-8:

```
prefix,country
1.0.0.0/24,AU
2a00:1450::/32,US
```

### asndb.csv.gz

CSV (gzipped), UTF-8:

```
range_start,range_end,asn,org
1.0.0.0,1.0.0.255,13335,CLOUDFLARENET
2400:cb00::,2400:cb00:ffff:ffff:ffff:ffff:ffff:ffff,13335,CLOUDFLARENET
```

## Data sources

- Country: ARIN, RIPE NCC, APNIC, LACNIC, AFRINIC (delegated extended stats)
- ASN: iptoasn.com (public domain, PDDL v1.0)

## Notes

Country reflects allocation / assignment country in RIR data.
This dataset contains no personal data and no executable code.
