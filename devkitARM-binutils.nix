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
  BINUTILS_VER="2.43.1";
  target="arm-none-eabi";
  toolchain="DEVKITARM";
  
  DKARM_RULES_VER="1.5.1";
  DKARM_CRTLS_VER="1.2.5";
in
let 
  binutils = (fetchTarball {
    url = "https://downloads.devkitpro.org/binutils-${BINUTILS_VER}.tar.xz";
    sha256 = "sha256:1z0lq9ia19rw1qk09i3im495s5zll7xivdslabydxl9zlp3wy570";
    name = "binutils_src";
  });
in
pkgs.stdenv.mkDerivation rec {
  version = BINUTILS_VER; # TODO apply CROSSBUILD

  pname = "devkitARM-binutils";

  buildInputs = with pkgs; [
    gnupatch
    gcc
  ];

  src = pkgs.fetchFromGitHub {
    owner = "devkitPro";
    repo = "buildscripts";
    rev = "devkitARM_${DEVKITARM_VER}";
    name = "buildscripts";
    sha256 = "sha256-HBZX+lEw76GXA05GdjCWMaE/kqO8YJV55rOkVbNyxeQ=";
  };

  configurePhase = ''
    export CPPFLAGS="-Wno-error=format-security ${CPPFLAGS}"
    export LDFLAGS="${LDFLAGS}"
    CROSS_PARAMS="--build=`./config.guess`"

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

    cp -r ${binutils} binutils
    chmod -R +w binutils
    cd binutils

    CPPFLAGS="$cppflags $CPPFLAGS" LDFLAGS="$ldflags $LDFLAGS" ./configure \
          --prefix=$out --target=${target} --disable-nls --disable-werror \
    --enable-lto --enable-plugins \
    --enable-poison-system-directories \
    $CROSS_PARAMS \
          || { echo "Error configuring binutils"; cat config.log ; exit 1; }
  '';

  buildPhase = ''
    make || { echo "Error building binutils"; exit 1; }
  '';

  installPhase = ''
    make install || { echo "Error installing binutils"; exit 1; }
  '';
}
