perf: build
	perf stat -e cache-misses ./users.test -test.bench .

build: users.test
	go test -c

