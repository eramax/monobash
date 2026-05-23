SHELL := /bin/bash
BIN := zig-out/bin/monobash

.PHONY: all build release debug check clean

all: release

build: debug

release:
	zig build -Doptimize=ReleaseSmall

debug:
	zig build

# Build for the K8s test pod (Ubuntu 24.04, glibc 2.39)
pod:
	zig build-exe -lcrypt -OReleaseSmall -target x86_64-linux-gnu.2.39 \
		-Mroot=main.zig -lc -L/usr/lib/x86_64-linux-gnu -I/usr/include \
		--cache-dir .zig-cache --global-cache-dir $(HOME)/.cache/zig --name monobash
	mv monobash zig-out/bin/monobash

check:
	zig build

clean:
	rm -rf zig-out .zig-cache monobash
