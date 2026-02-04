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
