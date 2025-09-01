#!/bin/bash
# -------------------------------------------------------------------------------------
# Copyright (c) 2025 WSO2 LLC. (https://www.wso2.com) All Rights Reserved.
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# --------------------------------------------------------------------------------------

set -o xtrace

TESTGRID_DIR=/opt/testgrid/workspace
INFRA_JSON='infra.json'

#PRODUCT_REPOSITORY=$1
#PRODUCT_REPOSITORY_BRANCH=$2
TEST_REPOSITORY=$1
TEST_REPOSITORY_BRANCH=$2
PRODUCT_NAME="wso2$3"
PRODUCT_VERSION=$4

GIT_USER=$5
GIT_PASS=$6
TEST_MODE=$7
TEST_GROUP=$8
TEST_REPOSITORY_NAME=$(echo $PRODUCT_REPOSITORY | rev | cut -d'/' -f1 | rev | cut -d'.' -f1)
TEST_REPOSITORY_PACK_DIR="$TESTGRID_DIR/$TEST_REPOSITORY_NAME"

# CloudFormation properties
CFN_PROP_FILE="${TESTGRID_DIR}/cfn-props.properties"
TEST_RUN_COMMAND="${TEST_RUN_COMMAND:-npm run test}"


JDK_TYPE=$(grep -w "JDK_TYPE" ${CFN_PROP_FILE} | cut -d"=" -f2)
DB_TYPE=$(grep -w "CF_DBMS_NAME" ${CFN_PROP_FILE} | cut -d"=" -f2)
PRODUCT_PACK_NAME=$(grep -w "REMOTE_PACK_NAME" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DBMS_VERSION=$(grep -w "CF_DBMS_VERSION" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_PASSWORD=$(grep -w "CF_DB_PASSWORD" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_USERNAME=$(grep -w "CF_DB_USERNAME" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_HOST=$(grep -w "CF_DB_HOST" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_PORT=$(grep -w "CF_DB_PORT" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_NAME=$(grep -w "SID" ${CFN_PROP_FILE} | cut -d"=" -f2)
PRODUCT_PACK_LOCATION=$(grep -w "PRODUCT_PACK_LOCATION" ${CFN_PROP_FILE} | cut -d"=" -f2)

function log_info(){
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
}

function log_error(){
    echo "[ERROR][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
    exit 1
}

function install_jdk11(){
    jdk11="ADOPT_OPEN_JDK11"
    mkdir -p /opt/${jdk11}
    jdk_file2=$(jq -r '.jdk[] | select ( .name == '\"${jdk11}\"') | .file_name' ${INFRA_JSON})
    wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdk/$jdk_file2.tar.gz
    tar -xzf "$jdk_file2.tar.gz" -C /opt/${jdk11} --strip-component=1

    export JAVA_HOME=/opt/${jdk11}
}

function install_jdks(){
    mkdir -p /opt/${jdk_name}
    jdk_file=$(jq -r '.jdk[] | select ( .name == '\"${jdk_name}\"') | .file_name' ${INFRA_JSON})
    wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdk/$jdk_file.tar.gz
    tar -xzf "$jdk_file.tar.gz" -C /opt/${jdk_name} --strip-component=1

    export JAVA_HOME=/opt/${jdk_name}
    echo $JAVA_HOME
}

function set_jdk(){
    jdk_name=$1
    #When running Integration tests for JDK 17 or 21, JDK 11 is also required for compilation.
    if [[ "$jdk_name" == "ADOPT_OPEN_JDK17" ]] || [[ "$jdk_name" == "ADOPT_OPEN_JDK21" ]]; then
        echo "Installing " + $jdk_name
        install_jdks
        echo $JAVA_HOME
        #setting JAVA_HOME to JDK 11 to compile
        install_jdk11
        echo $JAVA_HOME 
    else
        echo "Installing " + $jdk_name
        install_jdks
        echo $JAVA_HOME
        
    fi
}

function export_db_params(){
    db_name=$1

    export WSO2SHARED_DB_DRIVER=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .driver' ${INFRA_JSON})
    export WSO2SHARED_DB_URL=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2SHARED_DB") | .url' ${INFRA_JSON})
    export WSO2SHARED_DB_USERNAME=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2SHARED_DB") | .username' ${INFRA_JSON})
    export WSO2SHARED_DB_PASSWORD=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2SHARED_DB") | .password' ${INFRA_JSON})
    export WSO2SHARED_DB_VALIDATION_QUERY=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .validation_query' ${INFRA_JSON})
    
    export WSO2IDENTITY_DB_DRIVER=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .driver' ${INFRA_JSON})
    export WSO2IDENTITY_DB_URL=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2IDENTITY_DB") | .url' ${INFRA_JSON})
    export WSO2IDENTITY_DB_USERNAME=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2IDENTITY_DB") | .username' ${INFRA_JSON})
    export WSO2IDENTITY_DB_PASSWORD=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2IDENTITY_DB") | .password' ${INFRA_JSON})
    export WSO2IDENTITY_DB_VALIDATION_QUERY=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .validation_query' ${INFRA_JSON})
    
}

source /etc/environment

log_info "Clone test repository"
if [ ! -d $TEST_REPOSITORY_NAME ];
then
    git clone https://${GIT_USER}:${GIT_PASS}@$TEST_REPOSITORY --branch $TEST_REPOSITORY_BRANCH --single-branch
fi

log_info "Exporting JDK"
set_jdk ${JDK_TYPE}

pwd

db_file=$(jq -r '.jdbc[] | select ( .name == '\"${DB_TYPE}\"') | .file_name' ${INFRA_JSON})
wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdbc/${db_file}.jar  -P $TESTGRID_DIR/${PRODUCT_PACK_NAME}/repository/components/lib

sed -i "s|DB_HOST|${CF_DB_HOST}|g" ${INFRA_JSON}
sed -i "s|DB_USERNAME|${CF_DB_USERNAME}|g" ${INFRA_JSON}
sed -i "s|DB_PASSWORD|${CF_DB_PASSWORD}|g" ${INFRA_JSON}
sed -i "s|DB_NAME|${DB_NAME}|g" ${INFRA_JSON}

export_db_params ${DB_TYPE}

# Delete if the folder is available
rm -rf $TEST_REPOSITORY_PACK_DIR
mkdir -p $TEST_REPOSITORY_PACK_DIR

log_info "Navigating to cypress test directory"
cd $TEST_REPOSITORY_PACK_DIR
ls $TEST_REPOSITORY_PACK_DIR

WSO2_HOME="${TESTGRID_DIR}/${PRODUCT_PACK_NAME}"
log_info "WSO2_HOME=${WSO2_HOME}"

# --- Update deployment.toml ---
DEPLOYMENT_TOML="$WSO2_HOME/repository/conf/deployment.toml"
echo "Updating DEPLOYMENT_TOML..."
cat >> "$DEPLOYMENT_TOML" <<'EOT'

#Invoke the OAuth Introspection Endpoint, To enable token validation using client credentials
[[resource.access_control]]
context="(.*)/oauth2/introspect(.*)"
http_method = "all"
secure = true
allowed_auth_handlers="BasicClientAuthentication"

# To Enable logonTime for a user
[identity_mgt.events.schemes.identityUserMetadataMgtHandler.properties]
enable=true
EOT

# Start IS pack
export JAVA_HOME=/opt/${jdk_name}
echo $JAVA_HOME


# Pick startup script (adjust if your pack uses a different script name)
START_SH="${WSO2_HOME}/bin/wso2server.sh"

# give permission if missing
chmod +x "${START_SH}"

# start the server in background
nohup ${START_SH} start > ${WSO2_HOME}/wso2server-start.log 2>&1 &

# ---------- Wait for HTTPS port 9443 ----------
log_info "Waiting for 9443 to be reachable"
for i in {1..60}; do
  if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/9443" 2>/dev/null; then
    log_info "WSO2 is up on 9443"
    break
  fi
  sleep 5
  if [ $i -eq 60 ]; then
    log_error "WSO2 did not start within expected time"
  fi
done

echo "Installing npm dependencies…"
# Avoid big/unnecessary downloads
export PUPPETEER_SKIP_DOWNLOAD=1
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

npm install 

# Ensure Cypress binary exists (prevents “Cypress executable not found”)
npx cypress install || true
npx cypress verify

echo "Running tests: $TEST_RUN_COMMAND"
export CHROME_BIN=$(command -v google-chrome || true)
$TEST_RUN_COMMAND

# -------------------- ARTIFACTS --------------------
echo "Grouping Cypress test results…"
rm -rf test-results || true
mkdir -p test-results

mv cypress/reports test-results/ || true
[[ -d cypress/screenshots ]] && mv cypress/screenshots test-results/
[[ -d cypress/videos      ]] && mv cypress/videos test-results/
[[ -d cypress/hars        ]] && mv cypress/hars test-results/
[[ -d cypress/logs        ]] && mv cypress/logs test-results/

