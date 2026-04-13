.PHONY: run
run:
	swift run WhatsChanged -- $(path)

.PHONY: install
install:
	mkdir -p ~/.local/bin
	printf '#!/bin/sh\nswift run --package-path %s WhatsChanged -- "$$@" > /dev/null 2>&1 &\n' "$(CURDIR)" > ~/.local/bin/whatschanged
	chmod +x ~/.local/bin/whatschanged

.PHONY: release
release:
	@test -n "$(version)" || (echo "Usage: make release version=v0.1.0" && exit 1)
	swift build -c release
	tar -czf whatschanged-$(version)-arm64-apple-macosx.tar.gz -C .build/release WhatsChanged
	gh release create $(version) whatschanged-$(version)-arm64-apple-macosx.tar.gz --title "$(version)" --generate-notes
	rm whatschanged-$(version)-arm64-apple-macosx.tar.gz
