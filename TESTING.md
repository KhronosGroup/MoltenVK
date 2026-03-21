# Building and Testing MoltenVK from Fork

## Prerequisites

- Xcode 26 beta installed (required for macOS 26 SDK)
- Command Line Tools matching your Xcode version

If you get errors during build about missing SDKs, make sure Xcode 26 is selected:

```bash
sudo xcode-select -s /Applications/Xcode-beta.app
```

---

## 1. Clone

```bash
git clone git@github.com:voidstarone/MoltenVK.git
cd MoltenVK
git checkout fix-depth-bounds-cull-distance
```

---

## 2. Fetch external dependencies

This clones SPIRV-Cross, SPIRV-Tools, Vulkan-Headers, and others. Takes a few minutes.

```bash
./fetchDependencies --macos
```

---

## 3. Build

```bash
make macos
```

Output will be at:

```
Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
```

---

## 4. Install into CrossOver

CrossOver's app bundle is code-signed and sealed, so it can't be modified in-place even with `sudo`. The workaround is to copy it to your Desktop first.

**One-time setup — copy CrossOver to Desktop:**

```bash
cp -R /Applications/CrossOver.app ~/Desktop/CrossOver.app
```

Adjust the source path to match whatever variant you have (`CrossOver-Patched.app`, etc.).

**Remove the signature, swap the library, re-sign:**

```bash
codesign --remove-signature ~/Desktop/CrossOver.app

cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib \
   ~/Desktop/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/libMoltenVK.dylib

codesign --force --deep --sign - ~/Desktop/CrossOver.app
```

**Verify the right library is in place:**

```bash
md5 ~/Desktop/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/libMoltenVK.dylib
md5 Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
```

Both hashes must match before proceeding.

---

## 5. Test

Open the Desktop copy — **not** the one in `/Applications`:

```bash
open ~/Desktop/CrossOver.app
```

Launch your DOOM (2016) bottle from that CrossOver instance.

---

## 6. Re-patching after a rebuild

If you rebuild MoltenVK, you only need to repeat the swap — no need to re-copy the whole app:

```bash
codesign --remove-signature ~/Desktop/CrossOver.app

cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib \
   ~/Desktop/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/libMoltenVK.dylib

codesign --force --deep --sign - ~/Desktop/CrossOver.app
```

---

## 7. Install into a Sikarugir wrapper

Sikarugir bundles MoltenVK 1.4.1 inside each wrapper at `Contents/Frameworks/moltenvkcx/`. You can replace it with the patched build.

**Important: Sikarugir wrappers are usually NOT sealed the way CrossOver is.** Try the copy directly first; only remove/re-sign if it fails.

**Locate your wrapper.** Sikarugir wrappers are `.app` bundles, typically in `~/Applications/`:

```bash
WRAPPER=~/Applications/DOOM.app   # adjust to your wrapper name
```

**Swap the library:**

```bash
cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib \
   "$WRAPPER/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"
```

If that fails with "Operation not permitted", remove the signature first then re-sign after:

```bash
codesign --remove-signature "$WRAPPER"

cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib \
   "$WRAPPER/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"

codesign --force --deep --sign - "$WRAPPER"
```

**Configure the wrapper in Sikarugir:**

Open Configure for the wrapper and enable:
- **MoltenVK CX** — activates the moltenvkcx directory in the library path
- **DXVK** — routes D3D calls through Vulkan → MoltenVK → Metal (required for games that need `depthBounds` or `shaderCullDistance`)

Make sure D3DMetal and DXMT are both unchecked when using DXVK.

**Verify:**

```bash
md5 "$WRAPPER/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"
md5 Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
```

Both hashes must match.

---

## Troubleshooting

**`cp` says "Operation not permitted"**
You forgot to remove the signature first, or the removal failed. Run `codesign --remove-signature` again and retry.

**Game launches Steam but DOOM doesn't start**
You're probably opening the `/Applications` copy instead of the `~/Desktop` copy. Only the Desktop copy has the patched library.

**`./fetchDependencies` fails**
Make sure Xcode 26 command line tools are active:
```bash
sudo xcode-select -s /Applications/Xcode-beta.app
```
