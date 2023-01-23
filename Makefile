APP = $(shell basename $$PWD)
BINDIR ?= bin
DESTDIR ?= /usr/local/bin
GC = go build
GCFLAGS =
LDFLAGS = -ldflags="-s -w"
GO111MODULES = on
UPX := $(shell command -v upx 2> /dev/null)
#LDFLAGS=-ldflags "-X=main.Version=$(VERSION) -X=main.Build=$(BUILD)"
#VERSION := $(shell git describe --tags)
#BUILD := $(shell git rev-parse --short HEAD)
#ROJECTNAME := $(shell basename "$(PWD)")
#COMMIT_SHA = $(shell git rev-parse --short HEAD)
.DEFAULT_GOAL = help

# Ignore dependencies since we are using command aliases instead of targets
.PHONY: hello run build uninstall compile clean help

## nws: Build the package binary (in the bin/ directory)
nws:
#	$(GC) $(GCFLAGS) -o $(BINDIR)/$(APP) cmd/$(APP)/main.go
	cp sh/nws.sh bin/nws

## install: Install the program on the local system
install: nws
	@echo Installing $(BINDIR)/$(APP) in $(DESTDIR)/$(APP)
	@sudo cp $(BINDIR)/$(APP) $(DESTDIR)/$(APP)

## uninstall: Remove an installed program
uninstall:
	@echo Removing $(APP) from $(DESTDIR)
	@sudo rm $(DESTDIR)/$(APP)

## clean: Run "go clean"
clean:
	go clean
	@rm -f $(BINDIR)/$(APP)

## help: Show available make targets and a brief description of each
help: Makefile
	@echo
	@echo Available make targets:
	@echo
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo
