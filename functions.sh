#!/usr/bin/env bash
#
# Shared code for all binary-dist scripts.
#


# Define global variables
COMMAND=""
OS=""
INSTALL_FOLDER=""

# Check if debugging environment variable is set and initialize with 0 if not.
if [ -z "$DEBUG" ] ; then
    DEBUG=0
fi


help_text_help=\
"Show help for a command."
command_help() {
    local command=$1
    local help_command="help_$command"
    # Test to see if we have a valid help method, otherwise call
    # the general help.
    type $help_command &> /dev/null
    if [ $? -eq 0 ]; then
        $help_command
    else
        echo "Commands are:"
        for help_text in `compgen -A variable help_text_`
        do
            command_name=${help_text#help_text_}
            echo -e "  $command_name\t\t${!help_text}"
        done
    fi
}

#
# Main command selection.
#
# Select fuctions which are made public.
#
select_command() {
    local command=$1
    shift
    case $command in
        "")
            command_help
            exit 1
            ;;
        *)
            # Test to see if we have a valid command, otherwise call
            # the general help.

            call_command="command_$command"
            type $call_command &> /dev/null
            if [ $? -eq 0 ]; then
                $call_command $@
            else
                command_help
                echo ""
                echo "Unknown command: ${command}."
                exit 1
            fi
        ;;
    esac
}


#
# Chevah Build Script command selection.
#
select_chevahbs_command() {
    if [ $DEBUG -ne 0 ]; then
        echo "select_chevahbs_command:" $@
    fi
    COMMAND=$1
    OS=$2
    PYTHON_VERSION=$3
    INSTALL_FOLDER=$4
    # Shift the standard arguments, and the rest will be passed to all
    # commands.
    shift 3

    chevahbs_command="chevahbs_$COMMAND"
    type $chevahbs_command &> /dev/null
    if [ $? -eq 0 ]; then
        $chevahbs_command $@
    else
        echo "Don't know what to do with command: ${COMMAND}."
        exit 1
    fi
}


#
# Internal function for calling build script on each source.
#
chevahbs_build() {
    echo "Getting source..."
    chevahbs_get $@
    echo "Patching source..."
    chevahbs_patch $@
    echo "Configuring..."
    chevahbs_configure $@
    echo "Compiling..."
    chevahbs_compile $@
    echo "Installing..."
    chevahbs_install $@
}


exit_on_error() {
    exit_code=$1
    if [ $exit_code -ne 0 ]; then
        exit 1
    fi
}


execute() {
    if [ $DEBUG -ne 0 ]; then
        echo "Executing:" $@
    fi

    #Make sure $@ is called in quotes as otherwise it will not work.
    "$@"
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "PWD :" `pwd`
        echo "Fail:" $@
        exit 1
    fi
}


build() {
    project_name=$1
    project_version=$2
    target_folder=$3

    install_folder=$PWD/${BUILD_FOLDER}/${target_folder}
    execute mkdir -p ${install_folder}

    build_folder=${BUILD_FOLDER}/${project_name}
    execute rm -rf ${build_folder}
    echo "Copying build scripts ${build_folder}..."
    execute cp -r rules/${project_name} ${build_folder}
    execute cp 'functions.sh' ${build_folder}/

    execute pushd ${build_folder}
        execute ./chevahbs.sh build $OS ${project_version} ${install_folder}
        if [ -e "Makefile" ]; then
            lib_config_folder="${install_folder}/lib/config"
            makefile_name="Makefile.${OS}.${project_version}"
            execute mkdir -p ${lib_config_folder}
            execute cp 'Makefile' ${lib_config_folder}/${makefile_name}
        fi
    execute popd
}


#
# Create the distributable archive designed to be uploaded to the buildmaster.
#
# Args:
#  * version = full version number, ex 2.7.8.c3
#  * target_folder = name of the folder to be archived.
#
make_dist(){
    version=$1
    target_folder=$2

    target_tar=../dist/${version}/${target_folder}.tar
    target_tar_gz=${target_tar}.gz

    # Create a clean dist folder.
    execute rm -rf ${DIST_FOLDER}
    execute mkdir -p ${DIST_FOLDER}/${version}

    # Create tar.tz from build folder to dist folder.
    execute pushd ${BUILD_FOLDER}
        echo "Creating $target_tar_gz from $target_folder."
        execute tar -cf $target_tar $target_folder
        execute gzip $target_tar
    execute popd
}

# Move source to target, making sure mv will not fail if a folder
# already exists.
#
# The move is done by merging the folders.
safe_move() {
    source=$1
    target=$2
    execute cp -r $source $target
    execute rm -rf $source
}


