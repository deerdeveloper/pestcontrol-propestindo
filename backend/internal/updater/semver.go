package updater

import (
	"strconv"
	"strings"
)

// Newer mengembalikan true jika versi latest lebih baru dari current.
// Format yang dikenali: v1.2.3 atau 1.2.3, boleh diakhiri -rc.1 dan sejenisnya.
// Versi yang tidak bisa dibaca (misalnya "dev") dianggap 0.0.0.
func Newer(latest, current string) bool {
	return compare(parse(latest), parse(current)) > 0
}

type version struct {
	nums [3]int
	pre  string
}

func parse(s string) version {
	var v version
	s = strings.TrimPrefix(strings.TrimSpace(s), "v")
	if i := strings.IndexByte(s, '+'); i >= 0 {
		s = s[:i]
	}
	if i := strings.IndexByte(s, '-'); i >= 0 {
		v.pre = s[i+1:]
		s = s[:i]
	}
	for i, p := range strings.SplitN(s, ".", 3) {
		n, err := strconv.Atoi(p)
		if err != nil {
			return version{}
		}
		v.nums[i] = n
	}
	return v
}

func compare(a, b version) int {
	for i := range a.nums {
		if a.nums[i] != b.nums[i] {
			if a.nums[i] > b.nums[i] {
				return 1
			}
			return -1
		}
	}
	switch {
	case a.pre == b.pre:
		return 0
	case a.pre == "": // rilis final lebih baru dari pre-release dengan angka sama
		return 1
	case b.pre == "":
		return -1
	case a.pre > b.pre:
		return 1
	default:
		return -1
	}
}
