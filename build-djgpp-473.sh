#! /bin/bash

# target directory
DJGPP_PREFIX=${DJGPP_PREFIX-/usr/local/djgpp}

# enabled languages
#ENABLE_LANGUAGES=${ENABLE_LANGUAGES-c,c++,f95,objc,obj-c++}
ENABLE_LANGUAGES=${ENABLE_LANGUAGES-c,c++}

#DJGPP_DOWNLOAD_BASE="ftp://ftp.delorie.com/pub"
DJGPP_DOWNLOAD_BASE="http://www.delorie.com/pub"

# source tarball versions
BINUTILS_VERSION=224
DJCRX_VERSION=203
DJLSR_VERSION=203

GCC_VERSION=4.7.3
GCC_VERSION_SHORT=4.73
GMP_VERSION=5.0.5
MPFR_VERSION=3.1.1
MPC_VERSION=1.0
AUTOCONF_VERSION=2.64
AUTOMAKE_VERSION=1.11.1

# tarball location
BINUTILS_ARCHIVE="${DJGPP_DOWNLOAD_BASE}/djgpp/current/v2gnu/bnu${BINUTILS_VERSION}s.zip"
DJCRX_ARCHIVE="${DJGPP_DOWNLOAD_BASE}/djgpp/current/v2/djcrx${DJCRX_VERSION}.zip"
DJLSR_ARCHIVE="${DJGPP_DOWNLOAD_BASE}/djgpp/current/v2/djlsr${DJLSR_VERSION}.zip"

DJCROSS_GCC_ARCHIVE="${DJGPP_DOWNLOAD_BASE}/djgpp/rpms/djcross-gcc-${GCC_VERSION}/djcross-gcc-${GCC_VERSION}.tar.bz2"
GCC_ARCHIVE="http://ftpmirror.gnu.org/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2"
GMP_ARCHIVE="http://ftpmirror.gnu.org/gmp/gmp-${GMP_VERSION}.tar.bz2"
MPFR_ARCHIVE="http://ftpmirror.gnu.org/mpfr/mpfr-${MPFR_VERSION}.tar.bz2"
MPC_ARCHIVE="http://www.multiprecision.org/mpc/download/mpc-${MPC_VERSION}.tar.gz"
AUTOCONF_ARCHIVE="http://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.bz2"
AUTOMAKE_ARCHIVE="http://ftp.gnu.org/gnu/automake/automake-${AUTOMAKE_VERSION}.tar.bz2"

# gcc 4.7.3 unpack-gcc.sh needs to be patched for OSX
PATCH_UNPACK_GCC_SH="patch-unpack-gcc.txt"

# check required programs
REQ_PROG_LIST="g++ gcc unzip bison flex make makeinfo patch"

# MinGW doesn't have curl, so we use wget.
if uname|grep "^MINGW32" > /dev/null; then
  USE_WGET=1
fi

# use curl or wget?
if [ ! -z $USE_WGET ]; then
  REQ_PROG_LIST+=" wget"
else
  REQ_PROG_LIST+=" curl"
fi

for REQ_PROG in $REQ_PROG_LIST; do
  if ! which $REQ_PROG > /dev/null; then
    echo "$REQ_PROG not installed"
    exit 1
  fi
done

# check GNU sed is installed or not.
# It is for OSX, which doesn't ship with GNU sed.
if ! sed --version 2>/dev/null |grep "GNU sed" > /dev/null ;then
  echo GNU sed is not installed, need to download.
  SED_VERSION=4.2.2
  SED_ARCHIVE="http://ftp.gnu.org/gnu/sed/sed-${SED_VERSION}.tar.bz2"
else
  SED_ARCHIVE=""
fi

# check zlib is installed
if ! gcc test-zlib.c -o test-zlib -lz; then
  echo "zlib not installed"
  exit 1
fi
rm test-zlib 2>/dev/null
rm test-zlib.exe 2>/dev/null

# download source files
ARCHIVE_LIST="$BINUTILS_ARCHIVE $DJCRX_ARCHIVE $DJLSR_ARCHIVE $SED_ARCHIVE
              $DJCROSS_GCC_ARCHIVE $GCC_ARCHIVE
              $GMP_ARCHIVE $MPFR_ARCHIVE $MPC_ARCHIVE
              $AUTOCONF_ARCHIVE $AUTOMAKE_ARCHIVE"

echo "Download source files..."
mkdir -p download || exit 1
cd download

for ARCHIVE in $ARCHIVE_LIST; do
  FILE=`basename $ARCHIVE`
  if ! [ -f $FILE ]; then
    echo "Download $ARCHIVE ..."
    if [ ! -z $USE_WGET ]; then
      if ! wget -U firefox $ARCHIVE; then
        rm $FILE
        exit 1
      fi
    else
      if ! curl $ARCHIVE -L -o $FILE; then
        rm $FILE
        exit 1
      fi
    fi
  fi
done
cd ..

# create target directory, check writable.
echo "Make prefix directory : $DJGPP_PREFIX"
mkdir -p $DJGPP_PREFIX

if ! [ -d $DJGPP_PREFIX ]; then
  echo "Unable to create prefix directory"
  exit 1
fi

if ! [ -w $DJGPP_PREFIX ]; then
  echo "prefix directory is not writable."
  exit 1
fi

# make build dir
echo "Make build dir"
rm -rf build || exit 1
mkdir -p build || exit 1
cd build

# build binutils
echo "Building bintuils"
mkdir bnu${BINUTILS_VERSION}s
cd bnu${BINUTILS_VERSION}s
unzip ../../download/bnu${BINUTILS_VERSION}s.zip || exit 1
cd gnu/bnutl-* || exit

# exec permission of some files are not set, fix it.
for EXEC_FILE in install-sh missing; do
  echo "chmod a+x $EXEC_FILE"
  chmod a+x $EXEC_FILE || exit 1
done

sh ./configure \
           --prefix=$DJGPP_PREFIX \
           --target=i586-pc-msdosdjgpp \
           --program-prefix=i586-pc-msdosdjgpp- \
           --disable-werror \
           --disable-nls \
           || exit 1

make configure-bfd || exit 1
make -C bfd stmp-lcoff-h || exit 1
make || exit 1

if [ ! -z $MAKE_CHECK ]; then
  echo "Run make check"
  make check || exit 1
fi

make install || exit 1

cd ../../..
# binutils done

# prepare djcrx
echo "Prepare djcrx"
mkdir djcrx${DJCRX_VERSION}
cd djcrx${DJCRX_VERSION}
unzip ../../download/djcrx${DJCRX_VERSION}.zip || exit 1

cd src/stub
gcc -O2 stubify.c -o stubify || exit 1
gcc -O2 stubedit.c -o stubedit || exit 1

cd ../..

mkdir -p $DJGPP_PREFIX/i586-pc-msdosdjgpp/sys-include || exit 1
cp -rp include/* $DJGPP_PREFIX/i586-pc-msdosdjgpp/sys-include/ || exit 1
cp -rp lib $DJGPP_PREFIX/i586-pc-msdosdjgpp/ || exit 1
cp -p src/stub/stubify $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/ || exit 1
cp -p src/stub/stubedit $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/ || exit 1

cd ..
# djcrx done

# build djlsr (for exe2coff)
echo "Prepare djlsr"
mkdir djlsr${DJLSR_VERSION}
cd djlsr${DJLSR_VERSION}
unzip ../../download/djlsr${DJLSR_VERSION}.zip || exit 1
cd src/stub
patch exe2coff.c ../../../../patch-exe2coff.txt || exit 1
gcc -o exe2coff exe2coff.c || exit 1
cp -p exe2coff $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/ || exit 1
cd ../../..
# djlsr done

# build gcc
tar -xjvf ../download/djcross-gcc-${GCC_VERSION}.tar.bz2 || exit 1
cd djcross-gcc-${GCC_VERSION}/

BUILDDIR=`pwd`

echo "Building autoconf"
cd $BUILDDIR
tar xjf ../../download/autoconf-${AUTOCONF_VERSION}.tar.bz2 || exit 1
cd autoconf-${AUTOCONF_VERSION}/
./configure --prefix=$BUILDDIR/tmpinst || exit 1
make all install || exit 1

echo "Building automake"
cd $BUILDDIR
tar xjf ../../download/automake-${AUTOMAKE_VERSION}.tar.bz2 || exit 1
cd automake-${AUTOMAKE_VERSION}/
PATH="$BUILDDIR//tmpinst/bin:$PATH" \
./configure --prefix=$BUILDDIR/tmpinst || exit 1
PATH="$BUILDDIR//tmpinst/bin:$PATH" \
make all install || exit 1

# build GNU sed if needed.
if [ ! -z $SED_VERSION ]; then
  echo "Building sed"
  cd $BUILDDIR
  tar xjf ../../download/sed-${SED_VERSION}.tar.bz2 || exit 1
  cd sed-${SED_VERSION}/
  ./configure --prefix=$BUILDDIR/tmpinst || exit 1
  make all install || exit 1
fi

cd $BUILDDIR
tar xjf ../../download/gmp-${GMP_VERSION}.tar.bz2 || exit 1
tar xjf ../../download/mpfr-${MPFR_VERSION}.tar.bz2 || exit 1
tar xzf ../../download/mpc-${MPC_VERSION}.tar.gz || exit 1

if [ ! -z $PATCH_UNPACK_GCC_SH ]; then
  echo "Patch unpack-gcc.sh"
  patch unpack-gcc.sh ../../${PATCH_UNPACK_GCC_SH} || exit 1
fi

echo "Running unpack-gcc.sh"
PATH="$BUILDDIR/tmpinst/bin:$PATH" sh unpack-gcc.sh --no-djgpp-source ../../download/gcc-${GCC_VERSION}.tar.bz2 || exit 1

# copy stubify programs
cp $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/stubify $BUILDDIR/tmpinst/bin

echo "Building gmp"
cd $BUILDDIR/gmp-${GMP_VERSION}/
./configure --prefix=$BUILDDIR/tmpinst --enable-static --disable-shared || exit 1
make all || exit 1
if [ ! -z $MAKE_CHECK ]; then
  echo "Run make check"
  make check || exit 1
fi
make install || exit 1

echo "Building mpfr"
cd $BUILDDIR/mpfr-${MPFR_VERSION}/
./configure --prefix=$BUILDDIR/tmpinst --with-gmp-build=$BUILDDIR/gmp-${GMP_VERSION} --enable-static --disable-shared || exit 1
make all || exit 1
if [ ! -z $MAKE_CHECK ]; then
  echo "Run make check"
  make check || exit 1
fi
make install || exit 1

echo "Building mpc"
cd $BUILDDIR/mpc-${MPC_VERSION}/
./configure --prefix=$BUILDDIR/tmpinst --with-gmp=$BUILDDIR/tmpinst --with-mpfr=$BUILDDIR/tmpinst --enable-static --disable-shared || exit 1
make all || exit 1
if [ ! -z $MAKE_CHECK ]; then
  echo "Run make check"
  make check || exit 1
fi
make install || exit 1

echo "Building gcc"
cd $BUILDDIR/

mkdir djcross
cd djcross

PATH="$BUILDDIR//tmpinst/bin:$PATH" \
../gnu/gcc-${GCC_VERSION_SHORT}/configure \
                                 --target=i586-pc-msdosdjgpp \
                                 --program-prefix=i586-pc-msdosdjgpp- \
                                 --prefix=$DJGPP_PREFIX \
                                 --disable-nls \
                                 --disable-lto \
                                 --enable-libquadmath-support \
                                 --with-gmp=$BUILDDIR/tmpinst \
                                 --with-mpfr=$BUILDDIR/tmpinst \
                                 --with-mpc=$BUILDDIR/tmpinst \
                                 --enable-version-specific-runtime-libs \
                                 --enable-languages=${ENABLE_LANGUAGES} \
                                 || exit 1

make j=4 "PATH=$BUILDDIR/tmpinst/bin:$PATH" || exit 1

make install || exit 1

# gcc done

echo "Testing DJGPP."
cd $BUILDDIR
cd ..
echo "Use DJGPP to build a test C program."
$DJGPP_PREFIX/bin/i586-pc-msdosdjgpp-gcc ../hello.c -o hello || exit 1

for x in $(echo $ENABLE_LANGUAGES | tr "," " ")
do
  case $x in
    c++)
      echo "Use DJGPP to build a test C++ program."
      $DJGPP_PREFIX/bin/i586-pc-msdosdjgpp-c++ ../hello-cpp.cpp -o hello-cpp || exit 1
      ;;
  esac
done
exit 1

echo "build-djgpp.sh done."