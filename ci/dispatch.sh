#!/usr/bin/env bash
# Generic private-source build adapter. No account, source, branch or product metadata stored here.
set -Eeuo pipefail
set +x
umask 077
: "${SOURCE_ACCESS_TOKEN:?private token secret missing}"
: "${ANDROID_SDK_ROOT:?Android SDK required}"
: "${CONFIDENTIAL_OUTPUT_DIR:?restricted build output required}"
export PRIVATE_SOURCE_DIR="$RUNNER_TEMP/private-source"
# Token scope should grant access to exactly one intended private source repository.
# Any ambiguity fails closed, rather than guessing a repository to build.
source_repo=$(python3 - <<'PY'
import json,os,urllib.request
req=urllib.request.Request(
 "https://api.github.com/user/repos?per_page=100&visibility=private&affiliation=owner",
 headers={"Authorization":"Bearer "+os.environ["SOURCE_ACCESS_TOKEN"],"Accept":"application/vnd.github+json","X-GitHub-Api-Version":"2022-11-28"})
with urllib.request.urlopen(req,timeout=25) as r:
 rows=json.load(r)
candidates=[x["full_name"] for x in rows if x.get("private") and x.get("permissions",{}).get("pull",True)]
if len(candidates)!=1: raise SystemExit("Source token must authorize exactly one private owner repository")
print(candidates[0])
PY
)
# Git auth goes exclusively through ephemeral environment configuration, never git URLs or logs.
basic=$(printf 'x-access-token:%s' "$SOURCE_ACCESS_TOKEN" | base64 -w0)
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
export GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $basic"
git clone --quiet --depth=1 "https://github.com/$source_repo.git" "$STFU_PRIVATE_DIR"
test -s "$STFU_PRIVATE_DIR/ci-private/run.sh"
exec bash "$STFU_PRIVATE_DIR/ci-private/run.sh"
