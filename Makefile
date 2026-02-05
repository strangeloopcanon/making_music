.PHONY: setup check test all run

setup:
	@swift --version

check:
	swift build

test:
	swift run making_music_selftest

all: check test

run:
	swift run making_music
