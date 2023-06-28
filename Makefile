.PHONY: bench build perf

perf: build
	perf stat -e cache-misses ./users.test -test.bench . -test.count=5

bench:
	go test -bench . -count 5

build: users.test

users.test: *.go
	go test -c
  
slice:
	ln -sf slice/* .

array:
	ln -sf array/* .
