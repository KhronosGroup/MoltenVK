XCODE_PROJ := MoltenVKPackaging.xcodeproj

.PHONY: all
all:
	xcodebuild -quiet -project $(XCODE_PROJ) -scheme "MoltenVK Package" build

.PHONY: macos
macos:
	xcodebuild -quiet -project $(XCODE_PROJ) -scheme "MoltenVK Package (macOS only)" build

.PHONY: ios
ios:
	xcodebuild -quiet -project $(XCODE_PROJ) -scheme "MoltenVK Package (iOS only)" build

.PHONY: clean
clean:
	xcodebuild -project $(XCODE_PROJ) -scheme "MoltenVK Package" clean
	rm -rf Package

