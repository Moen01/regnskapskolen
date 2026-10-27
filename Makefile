.PHONY: build test app run install icon onboard clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh release

run: app
	open "build/Regnskapsskolen.app"

install: app
	rm -rf "/Applications/Regnskapsskolen.app"
	cp -R "build/Regnskapsskolen.app" /Applications/
	@echo "Installert i /Applications/Regnskapsskolen.app"

icon:
	swift scripts/make-icon.swift

onboard:
	./scripts/onboard.sh

clean:
	rm -rf .build build
