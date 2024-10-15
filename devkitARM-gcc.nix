{
  pkgs ? import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/63dacb46bf939521bdc93981b4cbb7ecb58427a0.tar.gz";
    sha256 = "sha256:06jzngg5jm1f81sc4xfskvvgjy5bblz51xpl788mnps1wrkykfhp";
  }) {},
  OSXMIN ? "10.9",
  OSXSDKPATH ? "",
  CPPFLAGS ? "",
  LDFLAGS ? ""
}:
let 
  DEVKITARM_VER = "r65";
  GCC_VER="14.2.0";
  BINUTILS_VER="2.43.1";
  NEWLIB_VER="4.4.0.20231231";
  basedir="dkarm-eabi";
  package="devkitARM";
  target="arm-none-eabi";
  toolchain="DEVKITARM";
  
  DKARM_RULES_VER="1.5.1";
  DKARM_CRTLS_VER="1.2.5";
in
let
  # binutils = (callPackage ./devkitARM-binutils.nix {});

  gcc = (fetchTarball {
    url = "https://downloads.devkitpro.org/gcc-${GCC_VER}.tar.xz";
    sha256 = "sha256:1bdp6l9732316ylpzxnamwpn08kpk91h7cmr3h1rgm3wnkfgxzh9";
    name = "gcc_src";
  });
  
  newlib = (fetchTarball {
    url = "https://downloads.devkitpro.org/newlib-${NEWLIB_VER}.tar.gz";
    sha256 = "sha256:0dj22apaqbpwgvs5wqb5gsdw42cygdqgg3pqvgavxb3zd2cxzaxl";
    name = "newlib_src";
  });

  # these aren't necessary, they're just annoying
  SUPPRESS_WARNINGS_FLAGS = pkgs.lib.strings.concatStringsSep " " [
    "-Wno-error=format-security" 
    "-Wno-error=mismatched-tags" 
    "-Wno-error=array-bounds" 
    "-Wno-error=unknown-warning-option"
    "-Wno-error=char-subscripts"
  ];
in
pkgs.stdenv.mkDerivation rec {
  version = GCC_VER;

  pname = "devkitARM-gcc";

  src = (pkgs.fetchFromGitHub {
    owner = "devkitPro";
    repo = "buildscripts";
    rev = "devkitARM_${DEVKITARM_VER}";
    name = "buildscripts";
    sha256 = "sha256-HBZX+lEw76GXA05GdjCWMaE/kqO8YJV55rOkVbNyxeQ=";
  });

  buildInputs = with pkgs; [
    (callPackage ./devkitARM-binutils.nix {})
    ########
    # see https://github.com/devkitPro/buildscripts
    ########

    # ### Really basic tools
    # which
    # curl
    # # chmod

  	# ### Required to build on debian/ubuntu
    # bison
    # flex
    # # libncurses5-dev
    # ncurses5
    # # libreadline-dev 
    # readline
    # texinfo 
    # pkg-config

    # ###  For building gcc libgmp, libmpfr and libmpc are required -
    # ### these are built as static libraries to make packaging simpler.
    # ### If you're building the tools for personal use then the versions packaged by your chosen distro should suffice.
    # # https://gmplib.org/
    # # https://www.mpfr.org/
    # # https://www.multiprecision.org/
    # # libgmp-dev 
    gmp
    # # libmpfr-dev 
    mpfr
    # # libmpc-dev
    libmpc
    isl
    zstd

    # ### Some of the tools for devkitARM and devkitPPC also require FreeImage, zlib, expat, and libusb. 
    # ### Again these are built as static libraries for ease of packaging but you can probably use the versions supplied by your distro.
    # # https://freeimage.sourceforge.net/
    # # https://www.zlib.net
    # # https://www.libusb.org
    # # https://expat.sourceforge.net/
    # # libfreeimage-dev 
    # # freeimage
    # # # zlib1g-dev 
    # lzlib
    # zlib
    # # # libusb-dev 
    # # libusb
    # # # libudev-dev 
    # # udev
    # # # libexpat1-dev
    # # expat

    # ### Not part of devkitARM, but needed to download artifacts using cURL:
    # cacert

    ### Unspecified tools used in build:
    perl
    gnupatch
  ];

  LDFLAGS = "-L${pkgs.gmp}/lib -L${pkgs.mpfr}/lib -L${pkgs.libmpc}/lib -L${pkgs.isl}/lib -L${pkgs.zstd}/lib -L${pkgs.zlib}/lib";

  configurePhase = ''
    echo "GCC src: ${gcc}"
    export CPPFLAGS="${SUPPRESS_WARNINGS_FLAGS} ${CPPFLAGS}"
    export LDFLAGS="${LDFLAGS}"
    export CROSS_PARAMS="--build=`./config.guess`"

    PLATFORM=`uname -s`

    case $PLATFORM in
      Darwin )
        cppflags="-mmacosx-version-min=${OSXMIN} -I/usr/local/include"
        ldflags="-mmacosx-version-min=${OSXMIN} -L/usr/local/lib"
        if [ "x${OSXSDKPATH}x" != "xx" ]; then
          cppflags="$cppflags -isysroot ${OSXSDKPATH}"
          ldflags="$ldflags -Wl,-syslibroot,${OSXSDKPATH}"
        fi
        TESTCC=`cc -v 2>&1 | grep clang`
        if [ "x$\{TESTCC\}x" != "xx" ]; then
          cppflags="$cppflags -fbracket-depth=512"
        fi
        ;;
      MINGW32* )
        cppflags="-D__USE_MINGW_ACCESS -D__USE_MINGW_ANSI_STDIO=1"
        ;;
    esac

    cp -r ${gcc} gcc_src
    chmod -R +w gcc_src

    # echo "Root dir $(pwd):"
    # ls

    patchdir=$(pwd)/${basedir}/patches

    # echo "Patch dir $patchdir:"
    # ls $patchdir
    patch -p1 -d gcc_src -i $patchdir/gcc-${GCC_VER}.patch || { echo "Error patching $1"; exit 1; }

    ## see https://stackoverflow.com/a/46530067/929708 for why gcc_src and gcc_build are different dirs
    mkdir gcc_build
    cd gcc_build
    CPPFLAGS="$cppflags $CPPFLAGS" \
    LDFLAGS="$ldflags $LDFLAGS" \
    CFLAGS_FOR_TARGET="-O2 -ffunction-sections -fdata-sections" \
    CXXFLAGS_FOR_TARGET="-O2 -ffunction-sections -fdata-sections" \
    LDFLAGS_FOR_TARGET="" \
    ../gcc_src/configure \
      --enable-languages=c,c++,objc,lto \
      --with-gnu-as --with-gnu-ld --with-gcc \
      --with-march=armv4t\
      --enable-cxx-flags='-ffunction-sections' \
      --disable-libstdcxx-verbose \
      --enable-poison-system-directories \
      --enable-interwork --enable-multilib \
      --enable-threads --disable-win32-registry --disable-nls --disable-debug\
      --disable-libmudflap --disable-libssp --disable-libgomp \
      --disable-libstdcxx-pch \
      --enable-libstdcxx-time=yes \
      --enable-libstdcxx-filesystem-ts \
      --target=${target} \
      --with-newlib \
      --with-headers=${newlib}/newlib/libc/include \
      --prefix=$out \
      --enable-lto\
      --disable-tm-clone-registry \
      --disable-__cxa_atexit \
      --with-bugurl="http://wiki.devkitpro.org/index.php/Bug_Reports" --with-pkgversion="devkitARM release 65" \
      --with-gmp=${pkgs.gmp} \
      --with-mpfr=${pkgs.mpfr} \
      --with-mpc=${pkgs.libmpc} \
      --with-isl=${pkgs.isl} \
      --with-zstd=${pkgs.zstd} \
      $CROSS_PARAMS \
      $CROSS_GCC_PARAMS \
                  $EXTRA_GCC_PARAMS \
      || { echo "Error configuring gcc"; exit 1; }
    cd ..
  '';

  buildPhase = ''
    cd gcc_build
    make all-gcc
    cd ..
  '';


  installPhase = ''
    cd gcc_build
    make install-gcc
    cd ..
  '';
}
