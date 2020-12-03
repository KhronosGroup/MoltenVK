XC_PROJ := MoltenVKPackaging.xcodeproj
XC_SCHEME := MoltenVK Package

# Specify individually (not as dependencies) so the sub-targets don't run in parallel
.PHONY: all
all:
	@$(MAKE) macos
	@$(MAKE) ios
	@$(MAKE) iossim
	@$(MAKE) maccat
	@$(MAKE) tvos
	@$(MAKE) tvossim

.PHONY: all-debug
all-debug:
	@$(MAKE) macos-debug
	@$(MAKE) ios-debug
	@$(MAKE) iossim-debug
	@$(MAKE) maccat-debug
	@$(MAKE) tvos-debug
	@$(MAKE) tvossim-debug

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

.PHONY: iossim
iossim:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator"

.PHONY: iossim-debug
iossim-debug:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator" -configuration "Debug"

.PHONY: maccat
maccat:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=macOS,variant=Mac Catalyst"

.PHONY: maccat-debug
maccat-debug:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=macOS,variant=Mac Catalyst" -configuration "Debug"

.PHONY: tvos
tvos:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)"

.PHONY: tvos-debug
tvos-debug:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -configuration "Debug"

.PHONY: tvossim
tvossim:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator"

.PHONY: tvossim-debug
tvossim-debug:
	xcodebuild build -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator" -configuration "Debug"

.PHONY: clean
clean:
	xcodebuild clean -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME)"
	rm -rf Package

# Usually requires 'sudo make install'
.PHONY: install
install:
	rm -rf /Library/Frameworks/MoltenVK.framework
	rm -rf /Library/Frameworks/MoltenVK.xcframework
	cp -a Package/Latest/MoltenVK/MoltenVK.xcframework /Library/Frameworks/

# Deprecated target names
.PHONY: iosfat
iosfat:
	@$(MAKE) ios
	@$(MAKE) iossim

.PHONY: iosfat-debug
iosfat-debug:
	@$(MAKE) ios-debug
	@$(MAKE) iossim-debug

.PHONY: tvosfat
tvosfat:
	@$(MAKE) tvos
	@$(MAKE) tvossim

.PHONY: tvosfat-debug
tvosfat-debug:
	@$(MAKE) tvos-debug
	@$(MAKE) tvossim-debug
