#!/bin/bash -l

set -e

export APPLICATION_HELMFILE=$(pwd)/${HELMFILE_PATH}/${HELMFILE}

mkdir -p /localhost/.aws

cat <<EOT > /localhost/.aws/config
[profile cicd]
region = ${AWS_REGION}
role_arn = ${BASE_ROLE}
credential_source = Ec2InstanceMetadata

[profile default]
region = ${AWS_REGION}
role_arn = ${CLUSTER_ROLE}
source_profile = cicd
EOT

source /etc/profile.d/aws.sh

# Login to Kubernetes Cluster.
assume-role default aws eks --region ${AWS_REGION} update-kubeconfig --name ${CLUSTER_NAME}

# Read platform specific configs/info
assume-role default chamber export platform/${CLUSTER_NAME}/${ENVIRONMENT} --format yaml | yq --exit-status --no-colors  eval '{"platform": .}' - > /tmp/platform.yaml

if [[ "${OPERATION}" == "deploy" ]]; then
	HELMFILE_OPERATION="apply"
elif [[ "${OPERATION}" == "destroy" ]]; then
	HELMFILE_OPERATION="destroy"
els
	HELMFILE_OPERATION="none"
fi

# Helm Deployment
OPERATION_COMMAND="helmfile --namespace ${NAMESPACE} --environment ${ENVIRONMENT} --file /deploy/helmfile.yaml ${HELMFILE_OPERATION}"
echo "Executing: ${OPERATION_COMMAND}"
${OPERATION_COMMAND}

if [[ "${OPERATION}" == "deploy" ]]; then
	RELEASES=$(helmfile --namespace ${NAMESPACE} --environment ${ENVIRONMENT} --file /deploy/helmfile.yaml list --output json | jq .[].name -r)
	for RELEASE in ${RELEASES}
  do
  	ENTRYPOINT=$(kubectl --namespace ${NAMESPACE} get -l release=${RELEASE} ingress --output=jsonpath='{.items[].metadata.annotations.outputs\.platform\.cloudposse\.com/webapp-url}')
  	echo "::set-output name=webapp-url::${ENTRYPOINT}"
  done
fi

RELEASES_COUNTS=$(helm --namespace ${NAMESPACE} list --output json | jq 'length')

if [[ "${RELEASES_COUNTS}" == "0" ]]; then
	kubectl delete ns ${NAMESPACE}
fi


