#!/usr/bin/env bash

set -e

if [ -z "$PATHS" ]; then
  echo "PATHS is not set. Quitting."
  exit 1
fi
echo "PATHS: $PATHS"

if [ -z "$CHARTMUSEUM_URL" ]; then
  echo "CHARTMUSEUM_URL is not set. Quitting."
  exit 1
fi
echo "CHARTMUSEUM_URL: $CHARTMUSEUM_URL"

if [ -z "$FORCE" ]; then
  FORCE=""
elif [ "$FORCE" == "1" ] || [ "$FORCE" == "True" ] || [ "$FORCE" == "TRUE" ]; then
  FORCE="-f"
fi
echo "FORCE: $FORCE"


# Store the original working directory
orig_dir=$(pwd)

#extract base domain from CHARTMUSEUM_URL
CHARTMUSEUM_BASE_DOMAIN=$(echo $CHARTMUSEUM_URL | awk -F'/' '{print $1}')
echo "CHARTMUSEUM_BASE_DOMAIN: $CHARTMUSEUM_BASE_DOMAIN"

#extract path from CHARTMUSEUM_URL. If doesn't exist, set to empty string
CHARTMUSEUM_PATH=$(echo $CHARTMUSEUM_URL | awk -F'/' '{print $2}')
if [[ -z $CHARTMUSEUM_PATH ]]; then
  CHARTMUSEUM_PATH=""
fi

# Save ca.crt, cert.key, and cert.crt to $GITHUB_WORKSPACE
if [[ $CHARTMUSEUM_CA_CERT ]]; then
  echo "CA_CRT is set. Saving to $GITHUB_WORKSPACE/ca.crt"
  echo $CHARTMUSEUM_CA_CERT | base64 -d > $GITHUB_WORKSPACE/ca.crt
fi

if [[ $CHARTMUSEUM_KEY ]]; then
  echo "KEY is set. Saving to $GITHUB_WORKSPACE/cert.key"
  echo $CHARTMUSEUM_KEY | base64 -d > $GITHUB_WORKSPACE/cert.key
fi

if [[ $CHARTMUSEUM_CERT ]]; then
  echo "CERT is set. Saving to $GITHUB_WORKSPACE/cert.crt"
  echo $CHARTMUSEUM_CERT | base64 -d > $GITHUB_WORKSPACE/cert.crt
fi

if [[ $CHARTMUSEUM_ALIAS && $CHARTMUSEUM_BASE_DOMAIN ]]; then
  echo "CHARTMUSEUM_ALIAS is set. Adding $CHARTMUSEUM_ALIAS to /etc/hosts"
  CHARTMUSEUM_IP=$(dig +short $CHARTMUSEUM_BASE_DOMAIN)
  echo "$CHARTMUSEUM_IP $CHARTMUSEUM_ALIAS" >> /etc/hosts
fi

for CHART_PATH in $PATHS; do
  cd $CHART_PATH

  helm version -c

  helm inspect chart .

  CHART_VERSION_ARG=""

  #If VERSION env var is set, set chart version to VERSION
  if [[ $VERSION ]]; then
    echo "VERSION is set. Setting chart version to ${VERSION}"
    CHART_VERSION_ARG="--version ${VERSION}"
  fi

  #If DEV env var is set, get chart version from chart.yaml and append -dev
  if [[ $DEV ]]; then
    CHART_VERSION=$(grep "^version:" Chart.yaml | awk '{print $2}')
    CHART_VERSION="${CHART_VERSION}-dev"
    CHART_VERSION_ARG="--version ${CHART_VERSION}"
  fi

  if [[ $CHARTMUSEUM_REPO_NAME ]]; then
    echo "Adding Repo ${CHARTMUSEUM_REPO_NAME} https://${CHARTMUSEUM_ALIAS}/${CHARTMUSEUM_PATH}"
    helm repo add ${CHARTMUSEUM_REPO_NAME} https://${CHARTMUSEUM_ALIAS}/${CHARTMUSEUM_PATH} --ca-file $GITHUB_WORKSPACE/ca.crt --cert-file $GITHUB_WORKSPACE/cert.crt --key-file $GITHUB_WORKSPACE/cert.key
  fi

  helm dependency update .

  helm package .

  CHART_FOLDER=$(basename "$CHART_PATH")

  # If There is a chartmuseum path, set --context-path flag env var
  CONTEXT_PATH=""
  if [[ $CHARTMUSEUM_PATH ]]; then
    echo "CHARTMUSEUM_PATH is set. Setting --context-path to ${CHARTMUSEUM_PATH}"
    CONTEXT_PATH="--context-path /${CHARTMUSEUM_PATH}"
  fi

  echo "Pushing ${CHART_FOLDER}-* to https://${CHARTMUSEUM_ALIAS}/${CHARTMUSEUM_PATH} ${FORCE} ${CONTEXT_PATH}"
  helm cm-push ${CHART_FOLDER}-* https://${CHARTMUSEUM_ALIAS}/${CHARTMUSEUM_PATH} ${FORCE} ${CONTEXT_PATH} --ca-file $GITHUB_WORKSPACE/ca.crt --cert-file $GITHUB_WORKSPACE/cert.crt --key-file $GITHUB_WORKSPACE/cert.key ${CHART_VERSION_ARG}

  # Return to the original working directory at the end of each loop iteration
  cd $orig_dir
done
