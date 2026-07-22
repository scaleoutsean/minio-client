PWD := $(shell pwd)
GOPATH := $(shell go env GOPATH)
LDFLAGS := $(shell go run buildscripts/gen-ldflags.go)

TARGET_GOARCH ?= $(shell go env GOARCH)
TARGET_GOOS ?= $(shell go env GOOS)

VERSION ?= $(shell git describe --tags)
TAG ?= "minio/mc:$(VERSION)"

GOLANGCI = $(GOPATH)/bin/golangci-lint

LINUX_AMD64_BIN := $(PWD)/minio-client-x64
LINUX_ARM64_BIN := $(PWD)/minio-client-aarch64
MINIO_CLIENT_BIN := $(PWD)/minio-client

all: build

checks:
	@echo "Checking dependencies"
	@(env bash $(PWD)/buildscripts/checkdeps.sh)

getdeps:
	@mkdir -p ${GOPATH}/bin
	@echo "Installing tools" && go install tool

crosscompile:
	@(env bash $(PWD)/buildscripts/cross-compile.sh)

verifiers: getdeps vet lint

docker: build
	@docker build -t $(TAG) . -f Dockerfile.dev

vet:
	@echo "Running $@"
	@GO111MODULE=on go vet github.com/minio/mc/...

lint-fix: getdeps ## runs golangci-lint suite of linters with automatic fixes
	@echo "Running $@ check"
	@$(GOLANGCI) run --build-tags kqueue --timeout=10m --config ./.golangci.yml --fix

lint: getdeps
	@echo "Running $@ check"
	@$(GOLANGCI) run --build-tags kqueue --timeout=10m --config ./.golangci.yml

# Builds mc, runs the verifiers then runs the tests.
check: test
test: verifiers build
	@echo "Running unit tests"
	@GO111MODULE=on CGO_ENABLED=0 go test -tags kqueue ./... 1>/dev/null
	@echo "Running functional tests"
	@GO111MODULE=on MC_TEST_RUN_FULL_SUITE=true go test -race -v --timeout 20m ./... -run Test_FullSuite

test-race: verifiers build
	@echo "Running unit tests under -race"
	@GO111MODULE=on go test -race -v --timeout 20m ./... 1>/dev/null

# Verify mc binary
verify:
	@echo "Verifying build with race"
	@GO111MODULE=on CGO_ENABLED=1 go build -race -tags kqueue -trimpath --ldflags "$(LDFLAGS)" -o $(PWD)/mc 1>/dev/null
	@echo "Running functional tests"
	@GO111MODULE=on MC_TEST_RUN_FULL_SUITE=true go test -race -v --timeout 20m ./... -run Test_FullSuite

# Builds mc locally.
build: checks
	@echo "Building mc binary to './mc'"
	@GO111MODULE=on GOOS=$(TARGET_GOOS) GOARCH=$(TARGET_GOARCH) CGO_ENABLED=0 go build -trimpath -tags kqueue --ldflags "$(LDFLAGS)" -o $(PWD)/mc
	@cp -f $(PWD)/mc $(MINIO_CLIENT_BIN)
	@echo "Also wrote compatibility binary to './minio-client'"

# Builds Linux binaries for common architectures using explicit filenames.
build-linux-binaries: checks
	@echo "Building Linux x64 binary to './minio-client-x64'"
	@GO111MODULE=on GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -tags kqueue --ldflags "$(LDFLAGS)" -o $(LINUX_AMD64_BIN)
	@echo "Building Linux aarch64 binary to './minio-client-aarch64'"
	@GO111MODULE=on GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -tags kqueue --ldflags "$(LDFLAGS)" -o $(LINUX_ARM64_BIN)

# Alias targets for local fork workflows.
build-linux: build-linux-binaries

build-local: build build-linux-binaries

# Builds mc and installs it to $GOPATH/bin.
install: build
	@echo "Installing mc binary to '$(GOPATH)/bin/mc'"
	@mkdir -p $(GOPATH)/bin && cp -f $(PWD)/mc $(GOPATH)/bin/mc
	@echo "Installation successful. To learn more, try \"mc --help\"."

clean:
	@echo "Cleaning up all the generated files"
	@find . -name '*.test' | xargs rm -fv
	@find . -name '*~' | xargs rm -fv
	@rm -rvf mc
	@rm -rvf minio-client
	@rm -rvf minio-client-x64
	@rm -rvf minio-client-aarch64
	@rm -rvf build
	@rm -rvf release
