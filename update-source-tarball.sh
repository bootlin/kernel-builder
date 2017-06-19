#!/bin/bash

# Kindly borrowed from https://github.com/kernelci/kernelci-build-staging/

set -x

if ! [ $# -eq 2 ]; then
    echo "Usage: $0 tree branch"
    exit 2
fi

ROOT_DIR="$(pwd)"
STORAGE=${ROOT_DIR}/storage/sources
WORKSPACE=${ROOT_DIR}/workspace
TREE_BRANCH="$1#$2"

test -d $WORKSPACE ||mkdir -p $WORKSPACE
test -d $STORAGE ||mkdir -p $STORAGE
rm -f ${WORKSPACE}/*.properties

declare -A trees
trees=(
    [mainline]="http://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
    [next]="http://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git"
)

OFS=${IFS}
IFS='#'
arr=($TREE_BRANCH)
IFS=${OFS}

cd $WORKSPACE

tree_name=${arr[0]}
tree_url=${trees[$tree_name]}
branch=${arr[1]}
if [[ -z ${branch} ]]; then
  branch="master"
fi

echo "Looking for new commits in ${tree_url} (${tree_name}/${branch})"

LAST_COMMIT=`cat ${STORAGE}/${tree_name}/${branch}/last.commit`

COMMIT_ID=`git ls-remote ${tree_url} refs/heads/${branch} | awk '{printf($1)}'`
if [ -z $COMMIT_ID ]
then
  echo "ERROR: branch $branch doesn't exist"
  exit 0
fi

if [ "x$COMMIT_ID" == "x$LAST_COMMIT" ]
then
  echo "Nothing new in $tree_name/$branch.  Skipping"
  exit 0
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
  exit 1
fi

timeout --preserve-status -k 10s 5m git fetch origin ${REFSPEC}

git remote update
git checkout -f origin/$branch
if [ $? != 0 ]; then
  echo "ERROR: branch $branch doesn't exist"
  exit 0
fi

# Ensure abbrev SHA1s are 12 chars
git config --global core.abbrev 12

# Only use v3.x tags in arm-soc tree
GIT_DESCRIBE=$(eval git describe $describe_args)
GIT_DESCRIBE=${GIT_DESCRIBE//\//_}  # replace any '/' with '_'
GIT_DESCRIBE_VERBOSE=$(eval git describe --match=v[34]\*)

if [ -z $GIT_DESCRIBE ]; then
  echo "Unable to determine a git describe, exiting"
  exit 1
fi

cd $WORKSPACE
tar -czf linux-src.tar.gz --exclude=.git -C ${WORKSPACE}/${tree_name} .
if [ $? != 0 ]; then
  echo "Failed to create source tarball"
  exit 1
fi

test -d ${STORAGE}/${tree_name}/${branch} ||mkdir -p ${STORAGE}/${tree_name}/${branch}
cp linux-src.tar.gz ${STORAGE}/${tree_name}/${branch}/linux-src.tar.gz
if [ $? != 0 ]; then
  echo "Error moving file to storage"
  rm linux-src.tar.gz
  exit 1
fi

echo $COMMIT_ID > last.commit
cp last.commit ${STORAGE}/${tree_name}/${branch}/last.commit
if [ $? != 0 ]; then
  echo "Error pushing last commit update, not updating current commit"
  rm linux-src.tar.gz
  rm last.commit
  exit 1
fi
echo "${GIT_DESCRIBE}" > ${STORAGE}/${tree_name}/${branch}/last.git_describe
rm last.commit
rm linux-src.tar.gz


cat << EOF > ${WORKSPACE}/${TREE_BRANCH}-build.properties
TREE=$tree_url
SRC_TARBALL=${STORAGE}/${tree_name}/${branch}/${GIT_DESCRIBE}/linux-src.tar.gz
TREE_NAME=$tree_name
BRANCH=$branch
COMMIT_ID=$COMMIT_ID
GIT_DESCRIBE=${GIT_DESCRIBE}
GIT_DESCRIBE_VERBOSE=${GIT_DESCRIBE_VERBOSE}
PUBLISH=true
EOF

cat ${WORKSPACE}/${TREE_BRANCH}-build.properties
