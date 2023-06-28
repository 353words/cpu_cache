package users

type Image [128 * 128]byte

type User struct {
	Login   string
	Active  bool
	Icon    Image
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
