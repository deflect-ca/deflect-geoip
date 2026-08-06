package asn

import (
	"bufio"
	"fmt"
	"io"
	"strings"
)

// Record represents one ASN IP range entry.
// RangeStart and RangeEnd are dotted-decimal IPv4 or compressed IPv6 strings.
type Record struct {
	RangeStart string
	RangeEnd   string
	ASN        uint32
	Org        string
}

// ParseIPToASN parses the iptoasn.com TSV format:
//
//	range_start\trange_end\tAS_number\tcountry_code\tAS_description
//
// Lines starting with '#' and the sentinel ASN 0 ("Not routed") are skipped.
func ParseIPToASN(r io.Reader) ([]Record, error) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)

	var out []Record

	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "\t", 5)
		if len(parts) < 5 {
			continue
		}

		rangeStart := strings.TrimSpace(parts[0])
		rangeEnd := strings.TrimSpace(parts[1])
		asnStr := strings.TrimSpace(parts[2])
		org := strings.TrimSpace(parts[4])

		if asnStr == "0" || org == "Not routed" {
			continue
		}

		var asn uint32
		if _, err := fmt.Sscanf(asnStr, "%d", &asn); err != nil || asn == 0 {
			continue
		}

		out = append(out, Record{
			RangeStart: rangeStart,
			RangeEnd:   rangeEnd,
			ASN:        asn,
			Org:        sanitizeOrg(org),
		})
	}

	return out, sc.Err()
}

// sanitizeOrg removes commas and normalizes whitespace so the CSV stays valid.
func sanitizeOrg(s string) string {
	s = strings.ReplaceAll(s, ",", " ")
	return strings.Join(strings.Fields(s), " ")
}
