# Getting Friendly With Your CPU Cache

## CPU Cache

When a CPU needs to access a piece of data, the data needs to travel into the processor from main memory. 

The architecture looks something like this:

**Figure 1: CPU Cache**  

![](cpu-cache.png)

Figure 1 shows the different layers of memory a piece of data has to travel to be accessible by the processor. Each CPU has its own L1 and L2 cache, and the L3 cache is shared among all CPUs. When the data finally makes its way inside the L1 or L2 cache, the processor can access it for execution purposes. On Intel architectures the L3 cache maintains a copy of what is in L1 and L2.

Performance in the end is about how efficiently data can flow into the processor. As you can see from the diagram, main memory access is about 80 times slower than accessing the L1 cache since the data needs to be moved and copied.

(source: [Memory Performance in a Nutshell][https://www.intel.com/content/www/us/en/developer/articles/technical/memory-performance-in-a-nutshell.html], the data is from 2016 but what’s important are the latency ratios which are pretty constant.)

## An Example

This might be interesting, but how does that affect you as a developer?

Let's have a look...

Say you have the following `User` struct.:

**Listing 1: User struct**

```go
03 type Image [128 * 128]byte
04
05 type User struct {
06 	Login   string
07 	Active  bool
08 	Icon	 Image
09 	Country string
10 }
```

Listing 1 shows a struct named `User`. On line 08, the struct has a field named `Image` which is declared as an array of 128×128 bytes. That is a contiguous block of 16k bytes (16,384) of memory.

You might be wondering *why* the `Icon` field is part of the `User` struct? One reason might be to save an API call when the client retrieves a user from the system. This way the client doesn't need to make a second call to get the icon image.

Now imagine you need to add an API that counts the number of active users in the system by country.

**List 2: CountryCount**

```go
12 // CountryCount returns a map of countries to the number of active users.
13 func CountryCount(users []User) map[string]int{
14 	counts := make(map[string]int) // country -> count
15 	for _, u := range users {
16     	if !u.Active {
17         	    continue
18     	}
19     	counts[u.Country]++
20 	}
21
22 	return counts
23 }
```

## Benchmarking the Code

This API works great, but then you decide to benchmark the function. 

**Listing 2: Benchmark Code**
```go
05 var users []User
06
07 func init() {
08 	const size = 10_000
09
10 	countries := []string{
11         "AD",
12         "BB",
13         "CA",
14         "DK",
15 	}
16
17 	users = make([]User, size)
18 	for i := 0; i < size; i++ {
19         users[i].Active = i%5 > 0 // 20% non active
20         users[i].Country = countries[i%len(countries)]
21 	}
22 }
23
24 func BenchmarkCountryCount(b *testing.B) {
25 	for i := 0; i < b.N; i++ {
26         m := CountryCount(users)
27         if m == nil {
28             b.Fatal(m)
29         }
30 	}
31 }
```

Listing 2 shows the benchmark code. On lines 07-22, an init function is declared to initialize the data for the benchmark. On line 17, a slice is constructed to hold 10,000 users where 20% of them are set to be non active. On lines 24-31, the benchmark function is declared and is written to call the `CountryCount` function in the benchmark loop.

**Listing 3: Running the Benchmark**

```
$ go test -bench . -benchtime 10s -count 5	 

goos: linux
goarch: amd64
pkg: users
cpu: 12th Gen Intel(R) Core(TM) i7-1255U

BenchmarkCountryCount-12     4442     2630315 ns/op
BenchmarkCountryCount-12     4143     2814090 ns/op
BenchmarkCountryCount-12     3848     2642400 ns/op
BenchmarkCountryCount-12     4255     2639497 ns/op
BenchmarkCountryCount-12     4131     2661188 ns/op

PASS
ok     users     67.257s
```

Listing 3 shows how to run the benchmark and provides the results. On the first line the Go test command is used to run the benchmark function 5 times, each time for at least 10 seconds. The results of the benchmark average to 2,677,498ns per operation, or about ~2.67ms per operation.

_Note: You should pay attention to units when running benchmarks. The go tooling usually reports in nanoseconds but you might need to convert to other units. Commonly used units are nanoseconds (ns), microseconds (μs) and milliseconds (ms). If you see the following number in nanoseconds 123,456,789, then 789 are ns, 456 are μs, and 123 are ms. The comma is your friend._

You should have performance goals for your code, and if ~2.67ms meets these goals then don't touch the code to make it run any faster!

Let's assume you need better performance. How can you begin to profile the performance? What should you be looking for?

Let’s inspect cache misses to start.

## Cache Misses

Let's take a look at the size of the CPU caches I’m using to run this code:

**Listing 4: CPU Cache information**

```
$ lscpu --caches

NAME ONE-SIZE ALL-SIZE WAYS TYPE    	LEVEL  SETS PHY-LINE COHERENCY-SIZE
L1d   48K     352K     12   Data        1      64   1        64
L1i   32K     576K      8   Instruction 1      64   1        64
L2   1.3M     6.5M     10   Unified     2    2048   1        64
L3    12M      12M     12   Unified     3   16384   1        64
```

Listing 4 shows how to get the CPU cache information. You can see the sizes of each cache: L1 is 48K, L2 is 1.3M, and L3 is 12M.

Remember the `Icon` field in the `User` struct requires ~16k bytes of contiguous memory. When you multiply that with the 10k users we created for the benchmark, the slice requires ~163 MiB of contiguous memory.That means the slice once it’s constructed can’t fit in any of the caches in its entirety.

This is going to cause the hardware to be thrashing memory as it constantly needs to move data from main memory to cache for every element in the slice that is read. The system will behave as if there is random access memory happening even though the memory is laid out contiguously.

To verify that cache misses are not letting the program run as fast as it could be running, you can use the Linux [perf][https://perf.wiki.kernel.org/index.php/Main_Page] utility. The`perf` command works on an executable, so you need to run the test executable directly and not via `go test`.

By default, `go test` will delete the test executable at the end of running the test, so use the `-c` flag to keep it around.

**Listing 5: Building Test Executable**

```
$ go test -c

$ ls *.test
users.test
```

Listing 5 shows how to build and keep the test executable. Once you have the test executable you can run it under `perf`.

**Listing 6: Running the Test Executable Under `perf`**

```
$ perf stat -e cache-misses ./users.test -test.bench . -test.benchtime=10s -test.count=5

goos: linux
goarch: amd64
pkg: users
cpu: 12th Gen Intel(R) Core(TM) i7-1255U

BenchmarkCountryCount-12     3799     3153389 ns/op
BenchmarkCountryCount-12     3460     3094920 ns/op
BenchmarkCountryCount-12     3662     3073355 ns/op
BenchmarkCountryCount-12     3774     3166086 ns/op
BenchmarkCountryCount-12     3688     3091225 ns/op

PASS

Performance counter stats for
    './users.test -test.bench . -test.benchtime=10s -test.count=5':

     14,075,274,489    cpu_core/cache-misses:u/                                               
     (99.43%)
     
     8,668,379,326     cpu_atom/cache-misses:u/                                            	
     (0.77%)

     58.990510463 seconds time elapsed
     58.926667000 seconds user
      0.119521000 seconds sys
```

Listing 6 shows how to run the test executable using the `perf` command. You can see the amount of cache misses that occurred on both the core and atom CPUs.There were ~14 billion cache misses during the execution of the benchmark on the core cpu and another ~8 billion on the atom cpu.

_Note: For some Intel platforms (such as AlderLake which is a hybrid platform) there is an atom cpu and core cpu. Each cpu has a dedicated event list. A part of events are available on the core cpu and a part of events are also available on the atom cpu, and even part of events are available on both._

## Using a Slice

How can we reduce this number of cache misses? If we reduce the size of a `User` struct so more user values fit in the cache at the same time, we could reduce the number of cache misses. Right now we can only fit a few user values in the L1 cache at a time. Using a slice will let us significantly reduce the size of a `User` value.

But why will this help? Let’s look at the declaration of a slice value from the language.

https://github.com/golang/go/blob/master/src/runtime/slice.go#L15

**Listing 7: Slice Implementation**

```go
01 type slice struct {
02    array unsafe.Pointer
03    len   int
04    cap   int
05 }
```

Listing 7 shows the declaration of a slice in Go. On a 64 bit OS, an integer will be 64 bits or 8 bytes. This means a slice value is a total of 24 bytes. By using a slice, we can reduce the size of a user value from ~16k+ bytes to 24 bytes. A significant change.

**Listing 8: New Image**

```go
03 type Image []byte
04
05 type User struct {
06 	Login   string
07 	Active  bool
08 	Icon	 Image
09 	Country string
10 }
```

Listing 8 shows the new implementation of the `Image` and `User` types. The only change is on line 03 which uses a slice and the underlying type.

To be fair let's change the benchmark code to allocate memory for the icons in the initialization of `users`. This memory is no longer allocated with the construction of a User.

**Listing 9: New Initialization**

```go
07 func init() {
08 	const size = 10_000
09
10 	countries := []string{
11         "AD",
12         "BB",
13         "CA",
14         "DK",
15 	}
16
17 	users = make([]User, size)
18 	for i := 0; i < size; i++ {
19         users[i].Active = i%5 > 0 // 20% non active
20         users[i].Country = countries[i%len(countries)]
21         users[i].Icon = make([]byte, 128*128)
22 	}
23 }
```

Listing 9 shows the new benchmark code, the only change is the addition of line 21 that allocates memory for the `Icon` field.

Now let's run the benchmark again.

**Listing 10: Running the Benchmark**

```
$ go test -bench . -benchtime=10s -count=5	 

goos: linux
goarch: amd64
pkg: users
cpu: 12th Gen Intel(R) Core(TM) i7-1255U

BenchmarkCountryCount-12     189669     63774 ns/op
BenchmarkCountryCount-12     185011     63880 ns/op
BenchmarkCountryCount-12     188542     63865 ns/op
BenchmarkCountryCount-12     187938     64261 ns/op
BenchmarkCountryCount-12     186956     64297 ns/op

PASS
ok     users     63.364s
```

Listing 10 shows the second run of the benchmark. You can see the average is now 64015.40ns per operation or ~64 microseconds. About ~41.8 times faster than the previous version.

To make sure there are less cache misses, let's run the code under `perf` again.

**Listing 11: Running the Test Executable Under `perf`**

```
$ perf stat -e cache-misses ./users.test -test.bench . -test.benchtime=10s -test.count=5

goos: linux
goarch: amd64
pkg: users
cpu: 12th Gen Intel(R) Core(TM) i7-1255U

BenchmarkCountryCount-12     191288     62885 ns/op
BenchmarkCountryCount-12     193185     63890 ns/op
BenchmarkCountryCount-12     185040     63432 ns/op
BenchmarkCountryCount-12     190237     63356 ns/op
BenchmarkCountryCount-12     191358     63726 ns/op

PASS

Performance counter stats for
     './users.test -test.bench . -test.benchtime=10s -test.count=5':

     1,828,311  	cpu_core/cache-misses:u/                                            	
     (99.69%)

     306,533,948  	cpu_atom/cache-misses:u/                                            	
     (0.31%)

     63.630108076 seconds time elapsed
     63.610744000 seconds user
      0.103127000 seconds sys
```

Listing 11 shows the second run of `perf`. You can see there are now ~1.8 million cache misses on the cpu core and another ~306 million on the atom core. Back in listing 6 you will see the original values were in the billions.

Now that more users fit inside the cache, we are seeing less cache misses and better performance.

## Summary

One of the reasons I love optimizing code for my clients is the extent of knowledge I need to learn.
Not only data structures and algorithms, but also computer architecture, how the Go runtime works, networking and much more. And I also get to play with cool new tools (such as `perf`)

You got a significant performance boost from a small code change, but [There ain't no such thing as a free lunch](https://en.wikipedia.org/wiki/There_ain%27t_no_such_thing_as_a_free_lunch).

The code is riskier since now `Icon` might be `nil`.

You also need to allocate memory on the heap per `User` struct, heap allocation takes more time.
Lastly, the garbage collector needs to work harder since we have more data on the heap - but that is a discussion for another blog post.

If you want to read more on the subject, you can start with reading [Cache-oblivious algorithm][https://en.wikipedia.org/wiki/Cache-oblivious_algorithm] and following the links there.

You can find the code for this blog post [here][https://github.com/353words/cpu_cache].

