#!/usr/bin/env bash
# Copyright (c) 2010-2015 Adi Roiban.
# See LICENSE for details.
#
# Helper script for creating a Python virtualenv system on Unix/Msys.
#
# It creates a virtualenv without requiring an existing Python.
#
# Beside creating the virtualenv it can be used to chain the build system
# used by your project.
#
# To use this script you will need to publish binary archive files for the
# following components Python distribution.
#
# It will delegate the arguments to the custom hook, with the exception of
# these commands:
#
# * virtualenv PATH_TO_VENV - create a base Python distribution in specified
#                             directory
# * clean - remove all build files, except the cache directory.
# * detect_os - print OS name, version and arch and exit
# * get_python OSVER-ARCH - download Python distribution in cache for the OS
#                           at VER and ARCH.

# Script initialization.
set -o nounset
set -o errexit
set -o pipefail

#
# Documentation
#
# You can customize the behaviour of venv.sh by creating a `venv.conf`.
# It will be sourced before executing the logic from venv.sh
# It can be used to overwrite both the configuration variables and the
# hook functions.
#
# The configuration variables and the hook functions are documented below.

# Major version of Python. ex 2.5, 2.7, 3.4
PYTHON_FAMILY='2.7'
# Exact version of Python used at generating the virtualenv.
PYTHON_VERSION='2.7.8.c1'
# URL from where to download the virtualenv sources.
BINARY_DIST_URI='http://chevah.com/binary/python-distribution'
# List of commands for which dependencies are installed before invoking
# those commands.
RUN_DEPENDENCIES_FOR_COMMANDS="deps test"

#
# Hook called after python was install to allow installing additional custom
# packages from the shell.
#
# You can overwrite it in venv.conf.
after_python_install(){
    echo "Not installing anything after Python"
}

#
# Hook called before installing/updating the python dependencies to install
# dependencies which can not be reloaded inside python.
#
# You can overwrite it in venv.conf.
before_dependencies() {
    echo "Not installing anything before dependencies."
}

#
# Hook called before installing/updating the python dependencies to install
# dependencies which can not be reloaded inside python.
#
# You can overwrite it in venv.conf.
after_done() {
    echo "Not doing any default action."
}

#
# Documentation ends here.
##########################

# Initialize default value.
COMMAND=${1-''}
DEBUG=${DEBUG-0}

# Set default locale.
# We use C (alias for POSIX) for having a basic default value and
# to make sure we explictly convert all unicode values.
export LANG='C'
export LANGUAGE='C'
export LC_ALL='C'
export LC_CTYPE='C'
export LC_COLLATE='C'
export LC_MESSAGES='C'
export PATH=$PATH:'/sbin:/usr/sbin:/usr/local/bin'

#
# Global variables.
#
# Used to return non-scalar value from functions.
RESULT=''
DIST_FOLDER='dist'

# Path global variables.
BUILD_DIR="build"
CACHE_FOLDER="cache"
PYTHON_BIN=""
PYTHON_LIB=""

# Put default values and create them as global variables.
OS='not-detected-yet'
ARCH='x86'

# Load repo specific configuration if we have them.
if [ -e venv.conf ]; then
    source venv.conf
fi


clean_build() {
    # Shortcut for clear since otherwise it will depend on python
    echo "Removing ${BUILD_DIR}..."
    delete_folder ${BUILD_DIR}
    echo "Removing dist..."
    delete_folder ${DIST_FOLDER}
    echo "Removing publish..."
    delete_folder 'publish'
    echo "Cleaning project temporary files..."
    rm -f DEFAULT_VALUES
    echo "Cleaning pyc files ..."
    if [ $OS = "rhel4" ]; then
        # RHEL 4 don't support + option in -exec
        # We use -print0 and xargs to no fork for each file.
        # find will fail if no file is found.
        touch ./dummy_file_for_RHEL4.pyc
        find ./ -name '*.pyc' -print0 | xargs -0 rm
    else
        # AIX's find complains if there are no matching files when using +.
        [ $(uname) == AIX ] && touch ./dummy_file_for_AIX.pyc
        # Faster than '-exec rm {} \;' and supported in most OS'es,
        # details at http://www.in-ulm.de/~mascheck/various/find/#xargs
        find ./ -name '*.pyc' -exec rm {} +
    fi
    # In some case pip hangs with a build folder in temp and
    # will not continue until it is manually removed.
    rm -rf /tmp/pip*
}


#
# Delete the folder as quickly as possible.
#
delete_folder() {
    local target="$1"
    # On Windows, we use internal command prompt for maximum speed.
    # See: http://stackoverflow.com/a/6208144/539264
    if [ $OS = "windows" -a -d $target ]; then
        cmd //c "del /f/s/q $target > nul"
        cmd //c "rmdir /s/q $target"
    else
        rm -rf $target
    fi
}


#
# Wrapper for executing a command and exiting on failure.
#
execute() {
    if [ $DEBUG -ne 0 ]; then
        echo "Executing:" $@
    fi

    #Make sure $@ is called in quotes as otherwise it will not work.
    set +e
    "$@"
    exit_code=$?
    set -e
    if [ $exit_code -ne 0 ]; then
        echo "Fail:" $@
        exit 1
    fi
}

#
# Update global variables with current paths.
#
_update_path_variables() {

    if [ "${OS}" = "windows" ] ; then
        PYTHON_BIN="/lib/python.exe"
        PYTHON_LIB="/lib/Lib/"
    else
        PYTHON_BIN="/bin/python"
        PYTHON_LIB="/lib/python${PYTHON_FAMILY}/"
    fi

    PYTHON_BIN="${BUILD_DIR}${PYTHON_BIN}"
    PYTHON_LIB="${BUILD_DIR}${PYTHON_LIB}"

    export PYTHONPATH=${BUILD_DIR}
}


#
# Print the detected operating system
#
show_detected_os() {
    echo ${OS} ${ARCH}
}

#
# Download and extract a binary distribution.
#
get_python_distribution() {
    local os_signature=$1
    local remote_url=$BINARY_DIST_URI
    local dist_name=python-$os_signature-$PYTHON_VERSION

    echo "Getting $dist_name from $remote_url..."

    tar_file=${dist_name}.tar
    tar_gz_file=${tar_file}.gz

    mkdir -p ${CACHE_FOLDER}
    pushd ${CACHE_FOLDER}

        # Get and extract archive.
        rm -rf $dist_name
        rm -f $tar_gz_file
        rm -f $tar_file
        # Use 1M dot to reduce console pollution.
        execute wget --progress=dot -e dotbytes=1M \
            $remote_url/$PYTHON_VERSION/${tar_gz_file}
        execute gunzip $tar_gz_file
        execute tar -xf $tar_file
        rm -f $tar_gz_file
        rm -f $tar_file

    popd
}


#
# Copy python to build folder from binary distribution.
#
copy_python() {
    local python_distributable="${CACHE_FOLDER}/python-${OS}-${ARCH}-${PYTHON_VERSION}"

    # Check that python dist was installed
    if [ ! -s ${PYTHON_BIN} ]; then
        # Install python-dist since everything else depends on it.
        echo "Creating ${PYTHON_VERSION} environment to ${BUILD_DIR}..."
        mkdir -p ${BUILD_DIR}

        # If we don't have a cached python distributable,
        # get one together with default build system.
        if [ ! -d ${python_distributable} ]; then
            echo "No ${PYTHON_VERSION} environment. Start downloading it..."
            get_python_distribution \
                ${OS}-${ARCH}
        fi
        echo "Copying virtualenv files... "
        cp -R ${python_distributable}/* ${BUILD_DIR}
        echo "Fixing interpretor path in the new virtualenv..."
        $PYTHON_BIN -m 'chevah_virtualenv_fix'
        echo "Running after_python_install hook"
        after_python_install
    fi

}


#
# Check version of current OS to see if it is supported.
# If it's too old, exit with a nice informative message.
# If it's supported, return through eval the version numbers to be used for
# naming the package, for example '5' for RHEL 5.x, '1204' for Ubuntu 12.04',
# '53' for AIX 5.3.x.x , '10' for Solaris 10 or '1010' for OS X 10.10.1.
#
check_os_version() {
    # First parameter should be the human-readable name for the current OS.
    # For example: "Red Hat Enterprise Linux" for RHEL, "OS X" for Darwin etc.
    # Second and third parameters must be strings composed of integers
    # delimited with dots, representing, in order, the oldest version
    # supported for the current OS and the current detected version.
    # The fourth parameter is used to return through eval the relevant numbers
    # for naming the Python package for the current OS, as detailed above.
    local name_fancy="$1"
    local version_good="$2"
    local version_raw="$3"
    local version_chevah="$4"
    local version_constructed=''
    local flag_supported='good_enough'
    local version_raw_array
    local version_good_array

    # Using '.' as a delimiter, populate the version_raw_* arrays.
    IFS=. read -a version_raw_array <<< "$version_raw"
    IFS=. read -a version_good_array <<< "$version_good"

    # Iterate through all the integers from the good version to compare them
    # one by one with the corresponding integers from the supported version.
    for (( i=0 ; i < ${#version_good_array[@]}; i++ )); do
        version_constructed="${version_constructed}${version_raw_array[$i]}"
        if [ ${version_raw_array[$i]} -gt ${version_good_array[$i]} -a \
            "$flag_supported" = 'good_enough' ]; then
            flag_supported='true'
        elif [  ${version_raw_array[$i]} -lt ${version_good_array[$i]} -a \
            "$flag_supported" = 'good_enough' ]; then
            flag_supported='false'
        fi
    done

    if [ "$flag_supported" = 'false' ]; then
        echo "The current version of ${name_fancy} is too old: ${version_raw}"
        echo "Oldest supported version of ${name_fancy} is: ${version_good}"
        exit 13
    fi

    # The sane way to return fancy values with a bash function is to use eval.
    eval $version_chevah="'$version_constructed'"
}


#
# Update OS and ARCH variables with the current values.
#
detect_os() {

    OS=$(uname -s | tr "[A-Z]" "[a-z]")

    if [ "${OS%mingw*}" = "" ]; then

        OS='windows'
        ARCH='x86'

    elif [ "${OS}" = "sunos" ]; then

        ARCH=$(isainfo -n)
        os_version_raw=$(uname -r | cut -d'.' -f2)
        check_os_version Solaris 10 "$os_version_raw" os_version_chevah

        OS="solaris${os_version_chevah}"

    elif [ "${OS}" = "aix" ]; then

        ARCH="ppc$(getconf HARDWARE_BITMODE)"
        os_version_raw=$(oslevel)
        check_os_version AIX 5.3 "$os_version_raw" os_version_chevah

        OS="aix${os_version_chevah}"

    elif [ "${OS}" = "hp-ux" ]; then

        ARCH=$(uname -m)
        os_version_raw=$(uname -r | cut -d'.' -f2-)
        check_os_version HP-UX 11.31 "$os_version_raw" os_version_chevah

        OS="hpux${os_version_chevah}"

    elif [ "${OS}" = "linux" ]; then

        ARCH=$(uname -m)

        if [ -f /etc/redhat-release ]; then
            # Avoid getting confused by Red Hat derivatives such as Fedora.
            egrep 'Red\ Hat|CentOS|Scientific' /etc/redhat-release > /dev/null
            if [ $? -eq 0 ]; then
                os_version_raw=$(\
                    cat /etc/redhat-release | sed s/.*release// | cut -d' ' -f2)
                check_os_version "Red Hat Enterprise Linux" 4 \
                    "$os_version_raw" os_version_chevah
                OS="rhel${os_version_chevah}"
            fi
        elif [ -f /etc/SuSE-release ]; then
            # Avoid getting confused by SUSE derivatives such as OpenSUSE.
            if [ $(head -n1 /etc/SuSE-release | cut -d' ' -f1) = 'SUSE' ]; then
                os_version_raw=$(\
                    grep VERSION /etc/SuSE-release | cut -d' ' -f3)
                check_os_version "SUSE Linux Enterprise Server" 11 \
                    "$os_version_raw" os_version_chevah
                OS="sles${os_version_chevah}"
            fi
        elif [ $(command -v lsb_release) ]; then
            lsb_release_id=$(lsb_release -is)
            os_version_raw=$(lsb_release -rs)
            if [ $lsb_release_id = Ubuntu ]; then
                check_os_version "Ubuntu Long-term Support" 10.04 \
                    "$os_version_raw" os_version_chevah
                # Only Long-term Support versions are oficially endorsed, thus
                # $os_version_chevah should end in 04 and the first two digits
                # should represent an even year.
                if [ ${os_version_chevah%%04} != ${os_version_chevah} -a \
                    $(( ${os_version_chevah%%04} % 2 )) -eq 0 ]; then
                    OS="ubuntu${os_version_chevah}"
                fi
            fi
        fi

    elif [ "${OS}" = "darwin" ]; then
        ARCH=$(uname -m)

        os_version_raw=$(sw_vers -productVersion)
        check_os_version "Mac OS X" 10.4 "$os_version_raw" os_version_chevah

        # For now, no matter the actual OS X version returned, we use '108'.
        OS="osx108"

    else
        echo 'Unsupported operating system:' $OS
        exit 14
    fi

    # Fix arch names.
    if [ "$ARCH" = "i686" -o "$ARCH" = "i386" ]; then
        ARCH='x86'
    elif [ "$ARCH" = "x86_64" -o "$ARCH" = "amd64" ]; then
        ARCH='x64'
    elif [ "$ARCH" = "sparcv9" ]; then
        ARCH='sparc64'
    elif [ "$ARCH" = "ppc64" ]; then
        # Python has not been fully tested on AIX when compiled as a 64 bit
        # application and has math rounding error problems (at least with XL C).
        ARCH='ppc'
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH='arm64'
    fi
}

detect_os
_update_path_variables

if [ "$COMMAND" = "clean" ] ; then
    clean_build
    exit 0
fi

if [ "$COMMAND" = "detect_os" ] ; then
    show_detected_os
    exit 0
fi

if [ "$COMMAND" = "get_python" ] ; then
    get_python_distribution $2
    exit 0
fi

if [ "$COMMAND" = "virtualenv" ] ; then
    BUILD_DIR=$2
    _update_path_variables
    copy_python
    exit 0
fi

copy_python

# For required command install the dependencies before calling the main task.
for task_name in $RUN_DEPENDENCIES_FOR_COMMANDS; do
    if [ "$COMMAND" == "$task_name" ] ; then
        echo "Running before_dependencies hook"
        before_dependencies
    fi
done

after_done "$@"
