#!/bin/bash

# Kindly borrowed from https://github.com/kernelci/kernelci-build-staging/

# This script is kinda dirty and should clearly get rewritten with a more
# appropriate language. Bash is not made to deal with relational data
# structures!

if ! [ $# -ge 1 ]; then
    echo "Usage: $0 tree branch"
    echo "   or: $0 all"
    exit 2
fi

ROOT_DIR="$(pwd)"
STORAGE=${HOME}/storage/sources
WORKSPACE=${ROOT_DIR}/workspace/sources

test -d $WORKSPACE ||mkdir -p $WORKSPACE
test -d $STORAGE ||mkdir -p $STORAGE
rm -f ${WORKSPACE}/*.properties

declare -A trees
trees=(
    [mainline]="http://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
    [next]="http://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git"
    [linux4sam]="https://github.com/linux4sam/linux-at91.git"
    [mvebu-backports]="https://github.com/MISL-EBU-System-SW/mainline-public.git"
)

trees_to_build=$(cat - <<EOF
mainline>master
next>master
linux4sam>master
mvebu-backports>backport-4.14
mvebu-backports>devel-4.14/all
EOF
)

function build {
    cd $WORKSPACE

    TREE_BRANCH="$1#$2"
OFS=${IFS}
    IFS='#'
    arr=($TREE_BRANCH)
    IFS=${OFS}

    tree_name=${arr[0]}
    tree_url=${trees[$tree_name]}
    branch=${arr[1]}
    branch_fs=$(sed "s/\//_/g" <<<"${arr[1]}")
    if [[ -z ${branch} ]]; then
      branch="master"
    fi

    echo "Looking for new commits in ${tree_url} (${tree_name}/${branch_fs})"

    LAST_COMMIT=`cat ${STORAGE}/${tree_name}/${branch_fs}/last.commit`

    COMMIT_ID=`git ls-remote ${tree_url} refs/heads/${branch} | awk '{printf($1)}'`
    if [ -z $COMMIT_ID ]
    then
      echo "ERROR: branch $branch doesn't exist"
      return 0
    fi

    if [ "x$COMMIT_ID" == "x$LAST_COMMIT" ]
    then
      echo "Nothing new in $tree_name/$branch_fs.  Skipping"
      return 0
    fi

    echo "There was a new commit, time to fetch the tree"

    REFSPEC=+refs/heads/${branch}:refs/remotes/origin/${branch}
    if [ -e ${tree_name} ]; then
      cd ${tree_name} && \
      timeout --preserve-status -k 10s 5m git fetch --tags linus && \
      timeout --preserve-status -k 10s 5m git fetch --tags ${tree_url} ${REFSPEC}
    else
      git clone -o linus http://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git ${tree_name}
      cd ${tree_name} && \
      git remote add origin ${tree_url} && \
      timeout --preserve-status -k 10s 5m git fetch origin
    fi
    if [ $? != 0 ]; then
      return 1
    fi

    timeout --preserve-status -k 10s 5m git fetch origin ${REFSPEC}

    git remote update
    git checkout -f origin/$branch
    if [ $? != 0 ]; then
      echo "ERROR: branch $branch doesn't exist"
      return 0
    fi

    # Ensure abbrev SHA1s are 12 chars
    git config --global core.abbrev 12

    # Only use v3.x tags in arm-soc tree
    GIT_DESCRIBE=$(eval git describe $describe_args)
    GIT_DESCRIBE=${GIT_DESCRIBE//\//_}  # replace any '/' with '_'
    GIT_DESCRIBE_VERBOSE=$(eval git describe --match=v[34]\*)

    if [ -z $GIT_DESCRIBE ]; then
      echo "Unable to determine a git describe, exiting"
      return 1
    fi

    cd $WORKSPACE
    tar -czf linux-src.tar.gz --exclude=.git -C ${WORKSPACE}/${tree_name} .
    if [ $? != 0 ]; then
      echo "Failed to create source tarball"
      return 1
    fi

    test -d ${STORAGE}/${tree_name}/${branch_fs} ||mkdir -p ${STORAGE}/${tree_name}/${branch_fs}
    cp linux-src.tar.gz ${STORAGE}/${tree_name}/${branch_fs}/linux-src.tar.gz
    if [ $? != 0 ]; then
      echo "Error moving file to storage"
      rm linux-src.tar.gz
      return 1
    fi

    echo $COMMIT_ID > last.commit
    cp last.commit ${STORAGE}/${tree_name}/${branch_fs}/last.commit
    if [ $? != 0 ]; then
      echo "Error pushing last commit update, not updating current commit"
      rm linux-src.tar.gz
      rm last.commit
      return 1
    fi
    echo "${GIT_DESCRIBE}" > ${STORAGE}/${tree_name}/${branch_fs}/last.git_describe
    rm last.commit
    rm linux-src.tar.gz


    cat << EOF > ${WORKSPACE}/${tree_name}-${branch_fs}-build.properties
TREE=$tree_url
SRC_TARBALL=${STORAGE}/${tree_name}/${branch_fs}/${GIT_DESCRIBE}/linux-src.tar.gz
TREE_NAME=$tree_name
BRANCH=$branch
COMMIT_ID=$COMMIT_ID
GIT_DESCRIBE=${GIT_DESCRIBE}
GIT_DESCRIBE_VERBOSE=${GIT_DESCRIBE_VERBOSE}
PUBLISH=true
EOF

    cat ${WORKSPACE}/${tree_name}-${branch_fs}-build.properties
    cd ${ROOT_DIR}
}

if [ "$1" == "all" ]; then
    echo "Building all"
    for i in ${trees_to_build}; do
        t=$(cut -d '>' -f 1 <<<$i)
        b=$(cut -d '>' -f 2 <<<$i)
        if ! build $t $b; then
            echo "Tree $t failed"
        fi
    done
else
    build $1 $2
fi
