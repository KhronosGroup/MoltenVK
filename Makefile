XC_PROJ := MoltenVKPackaging.xcodeproj
XC_SCHEME := MoltenVK Package

# Specify individually (not as dependencies) so the sub-targets don't run in parallel
.PHONY: all
all:
	@$(MAKE) macos
	@$(MAKE) iosfat
	@$(MAKE) tvosfat

.PHONY: all-debug
all-debug:
	@$(MAKE) macos-debug
	@$(MAKE) iosfat-debug
	@$(MAKE) tvosfat-debug

.PHONY: macos
macos:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (macOS only)"

.PHONY: macos-debug
macos-debug:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (macOS only)" -configuration "Debug"

.PHONY: ios
ios:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)"

.PHONY: ios-debug
ios-debug:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -configuration "Debug"

.PHONY: iosfat
iosfat: ios
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator"

.PHONY: iosfat-debug
iosfat-debug: ios-debug
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator" -configuration "Debug"

.PHONY: tvos
tvos:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)"

.PHONY: tvos-debug
tvos-debug:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -configuration "Debug"

.PHONY: tvosfat
tvosfat: tvos
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator"

.PHONY: tvosfat-debug
tvosfat-debug: tvos-debug
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator" -configuration "Debug"

.PHONY: clean
clean:
	xcodebuild clean -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME)"
	rm -rf Package

# Usually requires 'sudo make install'
.PHONY: install
install:
	rm -rf /Library/Frameworks/MoltenVK.framework
	cp -a Package/Latest/MoltenVK/macOS/framework/MoltenVK.framework /Library/Frameworks/

