#!/usr/bin/env bash

appname=$(basename -s .git `git config --get remote.origin.url`)

source ./fierce-common/fierce-common.sh

txtund=$(tput sgr 0 1)          # Underline
txtbld=$(tput bold)             # Bold
grn=$(tput setaf 2)             # Green
red=$(tput setaf 1)             # Red
gold=$(tput setaf 3)            # Gold
bldgrn=${txtbld}$(tput setaf 2) # Bold Green
bldred=${txtbld}$(tput setaf 1) # Bold Red
txtrst=$(tput sgr0)             # Reset

usage()
{
cat << EOF
Project to manage $appname frontend infrastructure and code base
${txtbld}SYNOPSIS${txtrst}
${txtbld}DESCRIPTION${txtrst}
    ${txtbld}docker build${txtrst}
        Build docker image${txtrst}
    ${txtbld}docker run${txtrst}
        Build & run the docker image${txtrst}
    ${txtbld}docker deploy <environment>${txtrst}
        Build & deploy the docker image${txtrst}
    ${txtbld}test once${txtrst}
        Runs tests once${txtrst}
    ${txtbld}test refresh${txtrst}
        Runs tests on refresh${txtrst}
    ${txtbld}sync_submodule${txtrst}
        Clones submodules${txtrst}
EOF
exit 1
}

sync_submodule() {
      git submodule sync
      git submodule update --init
}

docker_build() {
    lein uberjar && \
    echo_message "Building docker image" && \
    docker build -t caleb-service-main .
}

docker_run() {
    docker_build && \
    echo_message "Running docker image" && \
    docker run -it -p 6001:6001 caleb-service-main
}

docker_deploy() {
    docker_build && \
    abort_on_error "Deployment not implemented"
}

run_ahpra() {
    echo_message "Running ahpra server locally"
    lein run
}

parse_docker() {
    local cmd=${1} && shift
    case ${cmd} in
        build)
            docker_build;;
        run)
            docker_run;;
        deploy)
            docker_deploy;;
        usage|*)
            usage
            exit 1;;
    esac
}

test_ahpra() {
    local cmd=${1} && shift
    case ${cmd} in
        once)
            echo_message "Running all tests once"
            lein test :all;;
        refresh)
            echo_message "Running unit tests on refresh"
            lein test-refresh;;
        usage|*)
            usage
            exit 1;;
    esac
}

parse() {
    local cmd=${1} && shift
    case ${cmd} in
        test)
            test_ahpra $@;;
        run)
            run_ahpra;;
        docker)
            parse_docker $@;;
        usage|*)
            usage
            exit 1;;
    esac
}

parse $@
abort_on_error
