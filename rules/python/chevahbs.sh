#!/bin/bash
#
# Chevah Build Script for Python.
#
# Import shared code.
. ./functions.sh

chevahbs_get() {
    # Python and pip sources are downloaded from their upstream location.
    upstream_version=$PYTHON_VERSION
    python_tar_gz="Python-${upstream_version}.tgz"
    python_tar="Python-${upstream_version}.tar"
    execute wget -c \
        https://www.python.org/ftp/python/${upstream_version}/${python_tar_gz} \
        -O $python_tar_gz
    execute gunzip $python_tar_gz
    execute tar -xf $python_tar
    mv Python-${upstream_version} src
    execute wget -c https://bootstrap.pypa.io/get-pip.py -O get-pip.py
}


chevahbs_patch() {
    cp setup.py src/setup.py
    # Move all back into base folder.
    mv src/* .
}

chevahbs_configure() {
    CONFIG_ARGS="--disable-shared"

    CONFIGURE_ENVIRONMENT=""

    case $OS in
        "hpux")
            export EXTRA_CFLAGS="-D_REENTRANT"
            export LIBS="-lpthread"
            CONFIG_ARGS="${CONFIG_ARGS} --without-gcc --without-ctypes"
            ;;
        "ubuntu1004")
            # On Ubuntu there are no libXXX.o, but rather linked against the
            # full version number.
            CONFIG_ARGS="${CONFIG_ARGS} \
                --with-bz2-version=1 \
                --with-crypt-version=1 \
                --with-openssl-version=0.9.8 \
                "
            ;;
        "ubuntu1204")
            CONFIG_ARGS="${CONFIG_ARGS} \
                --with-bz2-version=1 \
                --with-crypt-version=1 \
                --with-openssl-version=1.0.0 \
                "
            ;;
        aix*)
            # In AIX we build _ctypes with external libffi, but not the system
            # one. We use our libffi files and statically link against its libs.
            execute mkdir -p build/libffi
            execute cp $INSTALL_FOLDER/tmp/libffi/* build/libffi/
            # The following two parameters are picked up by Python's setup.py
            # and will convince it to use our external libffi for _ctypes.
            export CPPFLAGS="${CPPFLAGS} -Ibuild/libffi/"
            export LDFLAGS="${LDFLAGS} -Lbuild/libffi/"
            # Workaround for http://bugs.python.org/issue21917
            echo "import os; os.__dict__.pop('O_NOFOLLOW', None)" \
                >> Lib/site-packages/sitecustomize.py
            # These files are already created in the Python distribution,
            # but for some strange reason, make tries to recreate them.
            # We just touch them so that make will see them up to date.
            touch Include/Python-ast.h Python/Python-ast.c
            # MAXMEM option with a value greater than 8192.
            CONFIG_ARGS="${CONFIG_ARGS} \
                --with-system-ffi \
                "
            ;;
        solaris*)
            # In Solaris the default OpenSSL installation lives in /usr/sfw/.
            # Both include options are needed to match both the native Sun
            # Studio compiler and GCC.
            if [ "${ARCH%64}" = "$ARCH" ]; then
                echo "_ssl _ssl.c -I/usr/sfw/include" \
                    "-I/usr/sfw/include/openssl -L/usr/sfw/lib" \
                    " -R/usr/sfw/lib -lssl -lcrypto" >> Modules/Setup.local
            else
                CONFIG_ARGS="${CONFIG_ARGS} CFLAGS=-m64 LDFLAGS=-m64"
                echo "_ssl _ssl.c -I/usr/sfw/include" \
                    "-I/usr/sfw/include/openssl -L/usr/sfw/lib/64" \
                    " -R/usr/sfw/lib/64 -lssl -lcrypto" >> Modules/Setup.local
            fi
            ;;
    esac

    execute ./configure --prefix="" $CONFIG_ARGS

    case $OS in
        "hpux")
            cp Makefile Makefile.orig
            # On HPUX -DNDEBUG is causing troubles.
            sed "s/^OPT=.*-O/OPT= -O/"  Makefile.orig > Makefile
            ;;
    esac

}


chevahbs_compile() {
    execute $MAKE
}


chevahbs_install() {
    upstream_version=$1
    install_folder=$2
    execute $MAKE install DESTDIR=$INSTALL_FOLDER
    # Install pip
    execute $INSTALL_FOLDER/bin/python get-pip.py
    # Install virtualenv fixer.
    execute cp chevah_virtualenv_fix.py \
        $INSTALL_FOLDER/lib/python2.7/site-packages/
}


select_chevahbs_command $@
