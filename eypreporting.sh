#!/bin/bash

GITHUB_USERNAME=${GITHUB_USERNAME:-NTTCom-MS}
REPOBASEDIR=${REPOBASEDIR:-/var/eyprepos}
REPO_PATTERN=${REPO_PATTERN:-eyp-}

API_URL_REPOLIST="https://api.github.com/users/${GITHUB_USERNAME}/repos?per_page=100"
API_URL_REPOINFO_BASE="https://api.github.com/repos/${GITHUB_USERNAME}"

function update_doc()
{
  curl -u admin:admin -X PUT -H 'Content-Type: application/json' -d'{"id":"3604482","type":"page",
"title":"new page","space":{"key":"TST"},"body":{"storage":{"value":
"<p>This is the updated text for the new page</p>","representation":"storage"}},
"version":{"number":2}}' http://localhost:8080/confluence/rest/api/content/3604482 | python -mjson.tool

}

function paginar()
{
  REPO_LIST_HEADERS=$(curl -I "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null)

  echo "${REPO_LIST_HEADERS}" | grep "HTTP/1.1 403 Forbidden"
  if [ $? -eq 0 ];
  then
    RESET_RATE_LIMIT=$(echo "${REPO_LIST_HEADERS}" | grep "^X-RateLimit-Reset" | awk '{ print $NF }' | grep -Eo "[0-9]*")
    CURRENT_TS=$(date +%s)

    if [ "${RESET_RATE_LIMIT}" -ge "${CURRENT_TS}" ];
    then
      let SLEEP_RATE_LIMIT=RESET_RATE_LIMIT-CURRENT_TS
    else
      SLEEP_RATE_LIMIT=10
    fi

    RANDOM_EXTRA_SLEEP=$(echo $RANDOM | grep -Eo "^[0-9]{2}")
    let SLEEP_RATE_LIMIT=SLEEP_RATE_LIMIT+RANDOM_EXTRA_SLEEP

    echo "rate limited, sleep: ${SLEEP_RATE_LIMIT}"
    sleep "${SLEEP_RATE_LIMIT}"
  fi

  REPOLIST_LINKS=$(echo "${REPO_LIST_HEADERS}" | grep "^Link" | head -n1)
  REPOLIST_NEXT=$(echo "${REPOLIST_LINKS}" | awk '{ print $2 }')
  REPOLIST_LAST=$(echo "${REPOLIST_LINKS}" | awk '{ print $4 }')
}

function report()
{
  REPO_URL=$1

  REPO_NAME=${REPO_URL##*/}
  REPO_NAME=${REPO_NAME%.*}

  echo ${REPO_NAME}
  cd ${REPOBASEDIR}

  if [ -d "${REPO_NAME}" ];
  then
    rm -fr "${REPOBASEDIR}/${REPO_NAME}"
  fi

  git clone ${REPO_URL}
  cd ${REPO_NAME}

  MODULE_VERSION=$(cat metadata.json  | grep '"version"' | awk '{ print $NF }' | cut -f2 -d\")

  echo "| ${REPO_NAME} | ${MODULE_VERSION} | [!https://travis-ci.org/${GITHUB_USERNAME}/${REPO_NAME}.png?branch=master!|https://travis-ci.org/${GITHUB_USERNAME}/${REPO_NAME}] | [Documentation|https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/blob/master/README.md] \\\\ [CHANGELOG|https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/blob/master/CHANGELOG.md] |"

  cd -
}

function getrepolist()
{
  # curl -I https://api.github.com/users/NTTCom-MS/repos?per_page=100 2>/dev/null| grep ^Link:

  PAGENUM=1

  REPOLIST=$(curl "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null | grep "ssh_url" | cut -f4 -d\" | grep -E "/${REPO_PATTERN}")

  paginar

  while [ "${REPOLIST_NEXT}" != "${REPOLIST_LAST}" ];
  do
    let PAGENUM=PAGENUM+1
    REPOLIST=$(echo -e "${REPOLIST}\n$(curl "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null | grep "ssh_url" | cut -f4 -d\" | grep -E "/${REPO_PATTERN}")")

    paginar
  done

  let PAGENUM=PAGENUM+1
  REPOLIST=$(echo -e "${REPOLIST}\n$(curl "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null | grep "ssh_url" | cut -f4 -d\" | grep -E "/${REPO_PATTERN}")")
}

PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"

BASEDIR=$(dirname $0)
BASENAME=$(basename $0)

if [ ! -z "$1" ] && [ -f "$1" ];
then
  . $1 2>/dev/null
else
  if [[ -s "$BASEDIR/${BASENAME%%.*}.config" ]];
  then
    . $BASEDIR/${BASENAME%%.*}.config 2>/dev/null
  else
    echo "config file missing"
    exit 1
  fi
fi

mkdir -p ${REPOBASEDIR}

getrepolist

REPORT_REPOS="$(echo "|| Module name || Version || Travis status || Links ||")"

echo "start: $(date)"
for REPO_URL in $(echo "${REPOLIST}" | head -n1); #DEBUG
do
  REPORT_REPOS="${REPORT_REPOS}\n$(report "${REPO_URL}")"
  # sleep 10 DEBUG
done
echo "end: $(date)"

# postejar
# echo -e ${REPORT_REPOS}

curl -u "${DOC_USER}:${DOC_PASSWORD}" -X PUT -H 'Content-Type: application/json' -d"{\"id\":\"3604482\",\"type\":\"page\",\"title\":\"Module TOC\",\"space\":{\"key\":\"TST\"},\"body\":{\"storage\":{\"value\":\"${REPORT_REPOS}\",\"representation\":\"storage\"}},\"version\":{\"number\":2}}" "${DOC_URL_REST}/content/${DOC_ID}"

exit 0
