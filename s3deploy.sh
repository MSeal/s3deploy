 #!/bin/bash
# Copyright (c) OpenGov 2014
############################
# Simple script that tarballs the build directory and puts it to s3. The script
# assumes that it is being run under a Travis CI environment.
# The deploy will only happen on a merge, that is when MASTER_REPO_SLUG and
# TRAVIS_REPO_SLUG are the same string. It will also git tag the current deploy
# and push it upstream if the TRAVIS_BRANCH matches the TAG_ON.
#
# When tarballing the build, it is expected that the current working directory
# be inside the build directory
#
# It expects the followin            g environment variables to be set:
#   TARBALL_TARGET_PATH   : The target path for the tarball to be created
#   GIT_TAG_NAME          : The name of the git tag you want to create
#   TAG_ON                                             : On what branch should a git tag be made. Use bash regex syntax
#
#   AWS_S3_BUCKET         : The S3 bucket
#   AWS_S3_OBJECT_PATH    : The object path to the tarball you want to upload, in the form of <path>/<to>/<tarball name>
#   AWS_DEFAULT_REGION    : The S3 region to upload your tarball.
#   AWS_ACCESS_KEY_ID     : The aws access key id
#   AWS_SECRET_ACCESS_KEY : The aws secret access key
#
#   TRAVIS_BRANCH         : The name of the branch currently being built.
#   TRAVIS_COMMIT         : The commit that the current build is testing.
#   TRAVIS_PULL_REQUEST   : The pull request number if the current job is a pull request, "false" if it's not a pull request.
#   TRAVIS_BUILD_NUMBER   : The number of the current build (for example, "4").
#   TRAVIS_REPO_SLUG      : The slug (in form: owner_name/repo_name) of the repository currently being built.
#   TRAVIS_BUILD_DIR      : The absolute path to the directory where the repository

# Enable to exit on any failure
set -e -x

if [[ $TRAVIS_PULL_REQUEST == "false" ]]; then
    # Check if required environment variables are set
    if [ -z $GIT_REPO_NAME ]; then export GIT_REPO_NAME=`basename $TRAVIS_REPO_SLUG`; fi
    if [ -z $TARBALL_TARGET_PATH ]; then export TARBALL_TARGET_PATH=/tmp/$GIT_REPO_NAME.tar.gz; fi
    if [ -z $GIT_TAG_NAME ]; then export GIT_TAG_NAME=$TRAVIS_BRANCH-`date -u +%Y-%m-%d-%H-%M`; fi
    if [ -z $TAG_ON ]; then export TAG_ON=^production$ ; fi
    if [ -z $AWS_S3_BUCKET ]; then export AWS_S3_BUCKET=og-deployments; fi
    if [ -z $AWS_S3_OBJECT_PATH ]; then export AWS_S3_OBJECT_PATH=$GIT_REPO_NAME/$TRAVIS_BRANCH/`date -u +%Y/%m`/$TRAVIS_COMMIT.tar.gz; fi
    if [ -z $AWS_DEFAULT_REGION ]; then export AWS_DEFAULT_REGION=us-east-1; fi
    if [ -z $AWS_ACCESS_KEY_ID ]; then echo "AWS_ACCESS_KEY_ID not set"; exit 1; fi

    # we don't want to spew the secrets
    set +x
    if [ -z $AWS_SECRET_ACCESS_KEY ]; then echo "AWS_SECRET_ACCESS_KEY not set"; exit 1; fi
    set -x

    # Tar the build directory while excluding version control file
    cd $TRAVIS_BUILD_DIR
    tar --exclude-vcs -c -z -f $TARBALL_TARGET_PATH .

    # Get sha256 checksum  # Converts the md5sum hex string output to raw bytes and converts that to base64
    TARBALL_CHECKSUM=$(cat $TARBALL_TARGET_PATH | sha256sum | cut -b 1-64) # | sed 's/\([0-9A-F]\{2\}\)/\\\\\\x\1/gI' | xargs printf | base64)

    # Official AWS CLI is used for uploading the tarball to S3
    sudo pip install --download-cache $HOME/.pip-cache awscli
    TARBALL_ETAG=`ruby -e "require 'json'; resp = JSON.parse(%x[aws s3api put-object --acl private --bucket $AWS_S3_BUCKET --key $AWS_S3_OBJECT_PATH --body $TARBALL_TARGET_PATH]); puts resp['ETag'][1..-2]"`
    
    # Upadate latest tarball
    aws s3 cp s3://$AWS_S3_BUCKET/$AWS_S3_OBJECT_PATH s3://$AWS_S3_BUCKET/$GIT_REPO_NAME/$TRAVIS_BRANCH/latest.tar.gz

    # Only create tag on specified branch and when not a pull request
    if [[ $TRAVIS_BRANCH =~ $TAG_ON ]]; then
	git config --global user.email "alerts+travis@opengov.com"
	git config --global user.name "og-travis"
	git tag -a $GIT_TAG_NAME -m "Pull request: $TRAVIS_PULL_REQUEST -- Travis build number: $TRAVIS_BUILD_NUMBER"
	git push origin $GIT_TAG_NAME;
    fi
fi
