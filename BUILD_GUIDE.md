# Xiaomi Mi A1 (tissot) Kernel Build Guide

Complete guide for building the kernel using GitHub Actions and local scripts.

## Repository Setup

### 1. Place Files in Your Repository

```bash
# Copy workflow files
mkdir -p .github/workflows
cp kernel-build.yml .github/workflows/
cp kernel-build-simple.yml .github/workflows/

# Copy build scripts
cp build-kernel.sh ./
chmod +x build-kernel.sh

# Copy defconfig if not in tree
cp tissot_defconfig arch/arm64/configs/ 2>/dev/null || cp tissot_defconfig ./
```

### 2. Repository Structure
```
your-kernel-repo/
├── .github/
│   └── workflows/
│       ├── kernel-build.yml          (Full workflow)
│       └── kernel-build-simple.yml   (Quick workflow)
├── arch/
│   └── arm64/
│       ├── configs/
│       │   └── tissot_defconfig      (Kernel config)
│       └── boot/
├── build-kernel.sh                   (Local build script)
├── BUILD_GUIDE.md                    (This file)
└── [kernel source files]
```

## GitHub Actions Workflows

### Option 1: Full Build (kernel-build.yml)
**Features:**
- CLANG + GCC fallback toolchain
- Module compilation
- Device tree blob extraction
- Detailed build logs
- Automatic release creation on tags

**Triggers:**
- Push to main/master
- Manual workflow dispatch (GitHub UI)
- Pull requests

**Usage:**
1. Push changes to `main` or `master` branch
2. Go to Actions tab in GitHub
3. View build progress
4. Download artifacts from "Summary" tab

**Create Release:**
```bash
git tag v4.9.227-perf
git push origin v4.9.227-perf
```

### Option 2: Quick Build (kernel-build-simple.yml)
**Features:**
- Lightweight, fast build
- GCC toolchain only
- Minimal logging
- CCL caching for speed

**Triggers:**
- Push to main/master
- Manual dispatch with toolchain selection

**Usage:**
Same as Full Build but faster compile time (~5-10 mins vs 15-20 mins)

## Local Build Script

### Prerequisites
```bash
# Ubuntu/Debian
sudo apt-get install -y build-essential libncurses-dev libssl-dev \
  bison flex bc libelf-dev lz4 curl git wget rsync \
  device-tree-compiler gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu

# Arch Linux
sudo pacman -S base-devel ncurses openssl bison flex bc elfutils lz4 \
  arm-linux-gnueabihf-gcc arm-linux-gnueabihf-binutils

# Fedora
sudo dnf install -y gcc ncurses-devel openssl-devel bison flex bc \
  elfutils-devel lz4 aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils
```

### Build Commands

**Basic build:**
```bash
./build-kernel.sh
```

**With options:**
```bash
# Clean + build with modules
./build-kernel.sh --clean --modules

# Specify defconfig
./build-kernel.sh --defconfig arch/arm64/configs/tissot_defconfig

# Use CLANG toolchain
./build-kernel.sh --toolchain clang --jobs 8

# Verbose output
./build-kernel.sh --verbose

# Everything combined
./build-kernel.sh -c -m -j$(nproc) -v
```

**Help:**
```bash
./build-kernel.sh --help
```

### Output Structure
```
artifacts/
├── Image              (Kernel binary)
├── Image.gz           (Compressed kernel, if built)
├── vmlinux            (Debug symbols)
├── System.map         (Kernel symbols)
├── config-tissot      (Final .config)
├── *.dtb              (Device tree blobs)
└── modules-tissot.tar.gz (Compiled modules, if requested)
```

## Configuration

### Kernel Config
Edit `out/.config` before build or modify the defconfig:

```bash
# Interactive config menu
make O=out ARCH=arm64 menuconfig

# Oldconfig (preserve existing settings)
make O=out ARCH=arm64 oldconfig

# Defconfig (use defaults)
make O=out ARCH=arm64 defconfig
```

### Environment Variables
Set in `.bashrc` or GitHub workflow secrets:

```bash
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export OUT_DIR=out
export JOBS=$(nproc)
```

## Troubleshooting

### Build Fails: "defconfig not found"
```bash
# Solution 1: Place defconfig in arch/arm64/configs/
mkdir -p arch/arm64/configs/
cp tissot_defconfig arch/arm64/configs/

# Solution 2: Use --defconfig flag
./build-kernel.sh --defconfig /path/to/tissot_defconfig
```

### Build Fails: "aarch64-linux-gnu-gcc: command not found"
```bash
# Install toolchain
sudo apt-get install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu

# Or use CLANG
./build-kernel.sh --toolchain clang
```

### Out of disk space during build
```bash
# Check space
df -h .

# Clean build directory
./build-kernel.sh --clean

# Or use smaller defconfig (disable debug symbols):
sed -i 's/CONFIG_DEBUG_KERNEL=y/# CONFIG_DEBUG_KERNEL is not set/' out/.config
```

### CLANG toolchain not found
CLANG is optional. Download from:
- https://android.googlesource.com/platform/prebuilts/clang/
- https://github.com/ClangBuiltLinux/linux/wiki/Supported-Toolchains

Place in `~/toolchain/clang_r416183b/` or set `TOOLCHAIN_DIR` env var.

## GitHub Secrets (Optional)

For automated releases to Telegram, Discord, etc., add secrets:

**Example Telegram notification** (add to workflow):
```yaml
- name: Notify Telegram
  if: always()
  run: |
    BUILD_STATUS=$([ -f artifacts/Image ] && echo "✅ Success" || echo "❌ Failed")
    curl -s -X POST https://api.telegram.org/bot${{ secrets.TELEGRAM_BOT_TOKEN }}/sendMessage \
      -d chat_id=${{ secrets.TELEGRAM_CHAT_ID }} \
      -d text="Kernel Build: $BUILD_STATUS%0A${{ github.sha }}"
```

## Performance Tips

### Speed up builds:
```bash
# Use all CPU cores
./build-kernel.sh --jobs $(nproc)

# Enable ccache (10x faster rebuilds)
export USE_CCACHE=1
./build-kernel.sh

# Use `-O1` instead of `-O2` (if not stability critical)
```

### Reduce artifact size:
```bash
# Strip debug symbols
aarch64-linux-gnu-strip out/arch/arm64/boot/Image

# Compress modules
tar -xzf artifacts/modules-tissot.tar.gz -C out/
rm -f artifacts/modules-tissot.tar.gz
```

## Advanced: Custom Actions

### Build on schedule
```yaml
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly Sunday
```

### Build on pull requests
```yaml
on:
  pull_request:
    branches: [ main, master ]
    paths:
      - 'arch/arm64/**'
      - 'drivers/**'
```

### Multi-variant builds
```yaml
strategy:
  matrix:
    defconfig: [tissot_defconfig, other_defconfig]
    toolchain: [gcc, clang]
```

## Flashing the Kernel

Once built, flash to your Mi A1:

```bash
# Using ADB fastboot
adb reboot bootloader
fastboot flash boot out/arch/arm64/boot/Image

# Or package into boot.img (requires mkbootimg)
mkbootimg --kernel artifacts/Image \
  --ramdisk ramdisk.img \
  --output boot.img
```

## References

- [Linux Kernel Build Documentation](https://www.kernel.org/doc/html/latest/kbuild/kbuild.html)
- [ARM64 Architecture](https://www.kernel.org/doc/html/latest/arm64/index.html)
- [Qualcomm SoC Documentation](https://www.qualcomm.com)
- [LineageOS Kernel Compilation](https://wiki.lineageos.org/devices/tissot/build)

## Support

For issues:
1. Check build logs: `out/build.log` or GitHub Actions logs
2. Review kernel config: `out/.config`
3. Search kernel documentation
4. Check LineageOS forums for device-specific issues

---

**Kernel Version:** Linux 4.9.227  
**Device:** Xiaomi Mi A1 (tissot)  
**Architecture:** ARM64
