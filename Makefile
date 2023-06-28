perf: build
	perf stat -e cache-misses ./users.test -test.bench .

bench:
	go test -bench . -count 5

build: users.test

users.test: *.go
	go test -c

