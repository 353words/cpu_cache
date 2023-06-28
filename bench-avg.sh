#!/bin/bash

awk '/BenchmarkCountry/{count++; total+=$3} END {printf "%.2f\n", total/count}'
