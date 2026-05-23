FROM docker.io/ziglang/zig:0.16.0 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git bash tree-sitter-cli && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

# Build monobash in ReleaseSmall mode
RUN zig build -Doptimize=ReleaseSmall

# Test stage
FROM docker.io/ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash coreutils && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/zig-out/bin/monobash /usr/local/bin/monobash
COPY --from=builder /build/tests /tests
COPY --from=builder /build/SESSION.md /SESSION.md

ENTRYPOINT ["/usr/local/bin/monobash"]
CMD ["-c", "echo monobash ready"]
