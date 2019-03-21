#!/bin/bash

set -euvx

REPO_NAME="example-get-started"
REPO_PATH="../$REPO_NAME"

if [ -d "$REPO_PATH" ]; then
    echo "Repo $REPO_NAME already exists, remove it first or update the version (ver file)"
    exit 1
fi

mkdir $REPO_PATH
pushd $REPO_PATH

git init

virtualenv -p python3 .env
export VIRTUAL_ENV_DISABLE_PROMPT=true
source .env/bin/activate
echo '.env/' >> .gitignore

git add .
git commit -a -m  "initialize Git"

pip install dvc[s3]

dvc init
git commit -m "initialize DVC"

dvc remote add -d s3 s3://dvc-storage   
git commit -a -m "add default S3 remote"

mkdir data
wget https://dvc.org/s3/get-started/data.xml -O data/data.xml
dvc add data/data.xml
git add .gitignore data/data.xml.dvc
git commit -m "add source data to DVC"
dvc push

mkdir src
wget https://dvc.org/s3/get-started/code.zip -O src/code.zip
unzip src/code.zip -d src
rm -f src/code.zip
mv src/requirements.txt .
git add .
git commit -m 'add source code'

pip install -U -r requirements.txt

dvc run -f prepare.dvc --wdir data \
        -d ../src/prepare.py -d data.xml \
        -o data.tsv -o data-test.tsv \
        python ../src/prepare.py data.xml
git add .gitignore prepare.dvc
git commit -m "add data preparation stage"
dvc push

dvc run -f featurize.dvc \
        -d src/featurization.py -d data/data.tsv -d data/data-test.tsv \
        -o data/matrix.pkl -o data/matrix-test.pkl \
        python src/featurization.py data/data.tsv data/matrix.pkl \
               data/data-test.tsv data/matrix-test.pkl
git add .gitignore featurize.dvc
git commit -m "add featurization stage"
dvc push

dvc run -f train.dvc \
        -d src/train.py -d data/matrix.pkl \
        -o model.pkl \
        python src/train.py data/matrix.pkl model.pkl
git add .gitignore train.dvc
git commit -m "add train stage"
dvc push

dvc run -f evaluate.dvc \
        -d src/evaluate.py -d model.pkl -d data/matrix-test.pkl \
        -M auc.metric \
        python src/evaluate.py model.pkl data/matrix-test.pkl auc.metric
git add .gitignore evaluate.dvc auc.metric
git commit -m "add evaluation stage"
git tag -a "baseline" -m "baseline experiment"
dvc push

sed -e s/max_features=5000\)/max_features=6000\,\ ngram_range=\(1\,\ 2\)\)/ -i "" \
    src/featurization.py

dvc repro evaluate.dvc
git commit -a -m "try using bigrams"
git tag -a "bigrams" -m "bigrams experiment"

hub create iterative/example-get-started -d "Get started DVC project" -h "https://dvc.org/doc/get-started" 
git push -u origin master

popd

