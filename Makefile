.PHONY: \
	array \
	bench \
	build \
	clean \
	perf \
	slice

perf: build
	perf stat -e cache-misses ./users.test -test.bench . -test.benchtime=10s -test.count=5

bench: clean
	go test -bench . -benchtime=10s -count=5     

build: clean
	go test -c
  
slice:
	ln -sf slice/* .

array:
	ln -sf array/* .

# clean cache since it doesn't play nice with symlinks
clean:
	go clean -cache -testcache
