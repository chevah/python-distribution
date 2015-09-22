#!/usr/bin/env bash
#
# Chevah Build Script for CPython distribution.
#

# Script initialization.
set -o pipefail

PYTHON_UPSTREAM_VERSION='2.7.8'
PYTHON_BUILD_VERSION='+chevah1'
LIBFFI_UPSTREAM_VERSION='3.2.1'

# Import shared code.
. ./functions.sh

# List of OS packages required for building Python.
UBUNTU_PACKAGES="gcc make libssl-dev zlib1g-dev m4 texinfo"
RHEL_PACKAGES="gcc make openssl-devel zlib-devel m4 texinfo"
SLES_PACKAGES="gcc make libopenssl-devel zlib-devel m4 texinfo"
# List of OS packages requested to be installed by this script.
INSTALLED_PACKAGES=''
# For the moment, we don't install anything on OS X, Solaris, AIX and
# unsupported Linux distros. The build requires a C compiler, GNU make, m4,
# makeinfo (from texinfo, optional) and the header files for OpenSSL and zlib.

PYTHON_VERSION=$PYTHON_UPSTREAM_VERSION$PYTHON_BUILD_VERSION

PROG=$0
DIST_FOLDER='dist'
BUILD_FOLDER='build'

# Get OS values from main venv.sh script.
DETECTED_OS=`./venv.sh detect_os`
if [ "$?" -ne 0 ]; then
    exit 1
fi

OS=`echo $DETECTED_OS | cut -d' ' -f 1`
ARCH=`echo $DETECTED_OS | cut -d' ' -f 2`

# In Solaris and AIX we use $ARCH to choose if we build a 32bit or 64bit
# package. This way we are able to force a 32bit build on a 64bit machine,
# for example by exporting ARCH as "x86" instead of "x64" or
# "ppc" instead of "ppc64".
# We also use $ARCH when building the statically compiled libs: libffi and GMP.
export ARCH
# Explicitly choose the C compiler in order to make it possible to switch
# between native compilers and GCC on platforms such as AIX and Solaris.
export CC='gcc'
# CXX is not really needed, we export it to make sure g++ won't get picked up
# when not using gcc and thus silence the associated configure warning. However,
# we'll need to set CPPFLAGS later for linking to statically-compiled libs.
export CXX='g++'
# Use PIC (Position Independent Code) with GCC on 64-bit arches.
if [ "$CC" = 'gcc' -a ${ARCH%%64} != "$ARCH" ]; then
    export CFLAGS="${CFLAGS} -fPIC"
fi

PYTHON_DISTRIBUTION_NAME="python-$OS-$ARCH-$PYTHON_VERSION"
INSTALL_FOLDER=$PWD/${BUILD_FOLDER}/$PYTHON_DISTRIBUTION_NAME
PYTHON_BIN=$INSTALL_FOLDER/bin/python


export MAKE=make

case $OS in
    aix*)
        # By default, we use IBM's XL C compiler. Remove or comment out the
        # CC and CXX lines to use GCC. However, beware that GCC 4.2 from
        # IBM's RPMs will fail with GMP and Python!
        export CC="xlc_r"
        export CXX="xlC_r"
        export MAKE=gmake
        export PATH=/usr/vac/bin:$PATH
        export CFLAGS="-O2"
        # IBM's OpenSSL libs are mixed 32/64bit binaries in AIX, so we need to
        # be specific about what kind of build we want, because otherwise we
        # might get 64bit libraries (eg. when building GMP).
        if [ "${ARCH%64}" = "$ARCH" ]; then
            export OBJECT_MODE="32"
            export ABI="32"
            export AR="ar -X32"
            if [ "${CC}" != "gcc" ]; then
                export CFLAGS="$CFLAGS -qmaxmem=-1 -q32"
            fi
        else
            export OBJECT_MODE="64"
            export ABI="mode64"
            export AR="ar -X64"
            if [ "${CC}" != "gcc" ]; then
                export CFLAGS="$CFLAGS -qmaxmem=-1 -q64"
            fi
        fi
    ;;
    solaris*)
        # By default, we use Sun's Studio compiler. Comment these two for GCC.
        export CC="cc"
        export CXX="CC"
        # Here's where the system-included GCC is to be found.
        if [ "${CC}" = "gcc" ]; then
            export PATH="$PATH:/usr/sfw/bin/"
        fi
        # And this is where the GNU libs are in Solaris 10, including OpenSSL.
        if [ "${ARCH%64}" = "$ARCH" ]; then
            export LDFLAGS="-L/usr/sfw/lib -R/usr/sfw/lib"
        else
            export LDFLAGS="-m64 -L/usr/sfw/lib/64 -R/usr/sfw/lib/64"
            export CFLAGS="-m64 -xcode=abs64"
        fi
        if [ "$OS" = "solaris10" ]; then
            # Solaris 10 has OpenSSL 0.9.7, but Python 2 versions starting with
            # 2.7.9 do not support it, see https://bugs.python.org/issue20981.
            PYTHON_UPSTREAM_VERSION=2.7.8
            # These are the default-included GNU make and makeinfo.
            export MAKE=/usr/sfw/bin/gmake
            export MAKEINFO=/usr/sfw/bin/makeinfo
            # We favour the BSD-flavoured "install" over the default one.
            # "ar", "nm" and "ld" are included by default in the same path.
            export PATH=/usr/ccs/bin/:$PATH
            # sqlite3 lib location in all Solaris'es (incl. 10s10 for Sparc).
            if [ "${ARCH%64}" = "$ARCH" ]; then
                export LDFLAGS="$LDFLAGS -L/usr/lib/mps -R/usr/lib/mps"
            else
                export LDFLAGS="$LDFLAGS -L/usr/lib/mps/64 -R/usr/lib/mps/64"
            fi
        fi
    ;;
    hpux*)
        # For HP-UX we haven't managed yet to compile libffi and GMP with the
        # HP compiler, so we are NOT exporting custom values for CC and CXX.
        export MAKE=gmake
    ;;
esac


#
# Install OS package required to build Python.
#
install_dependencies() {

    packages='packages-not-defined'
    install_command='install-command-not-defined'
    check_command='check-command-not-defined'

    case $OS in
        ubuntu*)
            packages=$UBUNTU_PACKAGES
            install_command='sudo apt-get --assume-yes install'
            check_command='dpkg --status'
        ;;
        rhel*)
            packages=$RHEL_PACKAGES
            install_command='sudo yum -y install'
            check_command='rpm --query'
        ;;
        sles*)
            packages=$SLES_PACKAGES
            install_command='sudo zypper --non-interactive install -l'
            check_command='rpm --query'
        ;;
        linux|aix*|solaris*|osx*)
            packages=''
            install_command=''
            check_command=''
        ;;
    esac

    # We install one package after another since some package managers
    # (I am looking at you yum) will exit with 0 exit code if at least
    # one package was successfully installed.
    if [ -n "$packages" ]; then
        echo "Checking for packages to be installed..."
        for package in $packages ; do
            echo "Checking if $package is installed..."
            $check_command $package
            if [ $? -ne 0 ]; then
                echo "Installing $package using ${install_command}..."
                execute $install_command $package \
                    && INSTALLED_PACKAGES="$INSTALLED_PACKAGES $package"
            fi
        done
    fi
}


#
# This function should do its best to remove the packages previously
# installed by `install_dependencies` and leave the system clean.
#
remove_dependencies() {
    local rpm_leaves
    local zypper_options
    local libzypp_version

    if [ -n "$INSTALLED_PACKAGES" ]; then
        echo "Uninstalling the following packages: $INSTALLED_PACKAGES"
    else
        return
    fi

    case $OS in
        ubuntu*)
            execute sudo apt-get --assume-yes --purge remove $INSTALLED_PACKAGES
            execute sudo apt-get --assume-yes --purge autoremove
            ;;
        rhel*)
            execute sudo yum -y remove $INSTALLED_PACKAGES
            # RHEL7's yum learned how to auto-remove installed dependencies.
            if [ ${OS##rhel} -ge 7 ]; then
                execute sudo yum -y autoremove
            else
                # This partially works in RHEL 4 to 6 for automatically
                # removing packages installed as dependencies (aka "leaves").
                rhel_yum_autoremove() {
                    rpm_leaves=$(package-cleanup --leaves --quiet 2>/dev/null \
                        | egrep -v ^'Excluding|Finished')
                    if [ -z "$rpm_leaves" ]; then
                        (exit 0)
                    else
                        execute sudo yum -y remove $rpm_leaves
                        rhel_autoremove
                    fi
                }
                rhel_yum_autoremove
            fi
            ;;
        sles*)
            zypper_options="--non-interactive"
            # zypper version 7.4 got support for automatically removing
            # unneeded packages, but only when removing installed packages.
            libzypp_version=$(rpm --query --queryformat '%{VERSION}' libzypp)
            IFS=. read -a libzypp_version_array <<< "$libzypp_version"
            if [ ${libzypp_version_array[0]} -gt 7 ]; then
                zypper_options="$zypper_options --clean-deps"
            fi
            execute sudo zypper $zypper_options remove $INSTALLED_PACKAGES
            ;;
    esac
}


help_text_clean="Clean the build."
command_clean() {
    if [ -e ${BUILD_FOLDER} ]; then
        echo 'Previous build sub-directory found. Removing...'
        rm -rf ${BUILD_FOLDER}
    fi
}


help_text_build="Create the Python binaries for current OS."
command_build() {
    #install_dependencies

    # Clean the build dir to avoid contamination from previous builds.
    command_clean

    case $OS in
        aix*|solaris*|hpux*)
            build 'libffi' $LIBFFI_UPSTREAM_VERSION ${PYTHON_DISTRIBUTION_NAME}
            ;;
    esac

    build 'python' $PYTHON_UPSTREAM_VERSION ${PYTHON_DISTRIBUTION_NAME}

    execute pushd ${BUILD_FOLDER}/${PYTHON_DISTRIBUTION_NAME}
        # Clean the build folder.
        execute rm -rf tmp
        execute mkdir -p lib/config
        safe_move share lib/config
        # Move all bin to lib/config
        safe_move bin lib/config
        execute mkdir bin
        # Copy back python binary and pip
        execute cp lib/config/bin/python2.7 bin/python
        execute cp lib/config/bin/pip bin/pip
    execute popd

    #remove_dependencies

    make_dist $PYTHON_VERSION ${PYTHON_DISTRIBUTION_NAME}
}


#
# Test the newly created Python binary dist from withing the build folder.
#
help_text_test=\
"Run a quick test for the Python from build."
command_test() {
    test_file='test_python_binary_dist.py'
    execute mkdir -p build/
    execute cp test/* build/
    execute pushd build
        execute ./$PYTHON_DISTRIBUTION_NAME/bin/python ${test_file}
    execute popd
}

# Launch the whole thing.
select_command $@
