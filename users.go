package users

// type Image [128 * 128]byte

type Image []byte

type User struct {
	Login   string
	Icon    Image
	Active  bool
	Country string
}

// CountryCount returns map of country to number of active users.
func CountryCount(users []User) map[string]int {
	counts := make(map[string]int) // country -> count
	for _, u := range users {
		if !u.Active {
			continue
		}
		counts[u.Country]++
	}

	return counts
}
