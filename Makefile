XCODE_PROJ := MoltenVKPackaging.xcodeproj
XCODE_SCHEME_BASE := MoltenVK Package

.PHONY: all
all:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE)" build

.PHONY: macos
macos:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (macOS only)" build

.PHONY: ios
ios:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (iOS only)" build

.PHONY: tvos
tvos:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (tvOS only)" build

.PHONY: clean
clean:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE)" clean
	rm -rf Package

#Usually requires 'sudo make install'
.PHONY: install
install:
	rm -rf /Library/Frameworks/MoltenVK.framework
	cp -a Package/Latest/MoltenVK/macOS/framework/MoltenVK.framework /Library/Frameworks/

