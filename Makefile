.PHONY: run
run:
	swift run WhatsChanged -- $(path)

.PHONY: install
install:
	swift build -c release
	cp .build/release/WhatsChanged /usr/local/bin/whatschanged

.PHONY: release
release:
	@test -n "$(version)" || (echo "Usage: make release version=v0.1.0" && exit 1)
	swift build -c release
	tar -czf whatschanged-$(version)-arm64-apple-macosx.tar.gz -C .build/release WhatsChanged
	gh release create $(version) whatschanged-$(version)-arm64-apple-macosx.tar.gz --title "$(version)" --generate-notes
	rm whatschanged-$(version)-arm64-apple-macosx.tar.gz
