XCODE_PROJ := MoltenVKPackaging.xcodeproj
XCODE_SCHEME_BASE := MoltenVK Package

# Specify individually (not as dependencies) so the sub-targets don't run in parallel
.PHONY: all
all:
	@$(MAKE) macos
	@$(MAKE) iosfat
	@$(MAKE) tvosfat

.PHONY: macos
macos:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (macOS only)" build

.PHONY: ios
ios:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (iOS only)" build

.PHONY: iosfat
iosfat: ios
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (iOS only)" -destination "generic/platform=iOS Simulator" build

.PHONY: tvos
tvos:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (tvOS only)" build

.PHONY: tvosfat
tvosfat: tvos
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE) (tvOS only)" -destination "generic/platform=tvOS Simulator" build

.PHONY: clean
clean:
	xcodebuild -quiet -project "$(XCODE_PROJ)" -scheme "$(XCODE_SCHEME_BASE)" clean
	rm -rf Package

# Usually requires 'sudo make install'
.PHONY: install
install:
	rm -rf /Library/Frameworks/MoltenVK.framework
	cp -a Package/Latest/MoltenVK/macOS/framework/MoltenVK.framework /Library/Frameworks/

