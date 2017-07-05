#!/bin/bash -x

# Prelude -------------------------------------------------------------------
#
# Enable inofficial Bash strict mode.
#
#   See: http://redsymbol.net/articles/unofficial-bash-strict-mode/
#
set -euo pipefail
IFS=$'\n\t'

# Constants
ZFIN_BASE_URL=http://zfin.org/downloads
OWNER=holtgrewe
PROJECT=zebrafish-phenotype-ontology
GIT_URL=git@github.com:$OWNER/$PROJECT.git
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
DATE=$(echo $TIMESTAMP | cut -d _ -f 1)
TIME=$(echo $TIMESTAMP | cut -d _ -f 2 | sed 's/-/:/g')


# Clone artifacts branch from repository to temporary directory.  Ensure that
# this directory is automatically cleaned up.
export TMPDIR=$(mktemp -d)
#trap "rm -rf $TMPDIR" EXIT

# Get path to new directory.
NEW_DIR=$TMPDIR/$PROJECT/$TIMESTAMP


# Step 0: Build zpgen JAR Using Maven ---------------------------------------
#mvn -f zpgen/ clean install package


# Step 1: Obtain Previous ZPO OWL File --------------------------------------
#
# This is required for keeping existing IDs intact.

pushd $TMPDIR && \
git clone --depth 1 --branch artifacts $GIT_URL $PROJECT && \
popd

ls $TMPDIR/$PROJECT/* | sort | tail -1
OLD_DIR=$(
    find $TMPDIR/$PROJECT -maxdepth 1 -type d -not -path '*/\.*' \
    | sort | tail -1)
OLD_OWL=$OLD_DIR/zp.owl
mkdir $NEW_DIR


# Step 2: Download Required ZFIN Data ---------------------------------------
#
# Create helper function for this, ensure to keep the logs.

download()
{
    set -ex

    pushd $NEW_DIR && \
    wget -N $ZFIN_BASE_URL/$1 -o $1.log && \
    popd
}

for fname in phenoGeneCleanData_fish.txt phenotype_fish.txt; do
    # Download file.
    download $fname

    # Check that the old and new files actually changed.
    if [[ -e $OLD_DIR/$fname ]] && [[ $(cmp -s $OLD_DIR/$fname $NEW_DIR/$fname) ]]; then
        >&2 echo "Files $OLD_DIR/$fname and $NEW_DIR/$fname are equal."
        >&2 echo
        >&2 echo "There is no reason to go on."
        exit 0  # exit without failure
    fi
done


# Step 3: Build ZPO OWL -----------------------------------------------------
#
# Use the JAR file we just created.

2>&1 java \
    -jar zpgen/target/zp-0.1-SNAPSHOT-jar-with-dependencies.jar \
    --zfin-pheno-txt-input-file $NEW_DIR/phenoGeneCleanData_fish.txt \
    --zfin-phenotype-txt-input-file $NEW_DIR/phenotype_fish.txt \
    -p $OLD_OWL \
    -o $NEW_DIR/zp.owl \
    -a $NEW_DIR/ \
    --add-source-information \
    -s $NEW_DIR/zp.annot_sourceinfo \
    --keep-ids \
| tee $NEW_DIR/zp.owl.log


# Postprocessing ------------------------------------------------------------
#
# Compress downloaded file to save space.

gzip $NEW_DIR/phenoGeneCleanData_fish.txt
gzip $NEW_DIR/phenotype_fish.txt


# Deployment ----------------------------------------------------------------
#
# Add tag and push the resulting change to the remote.

pushd $TMPDIR/$PROJECT
git add $TIMESTAMP
git commit $TIMESTAMP \
    -m "Adding rebuilt ZPO artifacts at $DATE $TIME"
git tag release/$DATE
git push origin artifacts --tags
