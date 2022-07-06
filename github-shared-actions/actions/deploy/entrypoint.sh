#!/bin/bash -l

set -e

declare -A regions_full=(
	["ap-east-1"]="ae1"
	["ap-northeast-1"]="an1"
	["ap-northeast-2"]="an2"
	["ap-northeast-3"]="an3"
	["ap-south-1"]="as0"
	["ap-southeast-1"]="as1"
	["ap-southeast-2"]="as2"
	["ca-central-1"]="cc1"
	["eu-central-1"]="ec1"
	["eu-north-1"]="en1"
	["eu-south-1"]="es1"
	["eu-west-1"]="ew1"
	["eu-west-2"]="ew2"
	["eu-west-3"]="ew3"
	["af-south-1"]="fs1"
	["us-gov-east-1"]="ge1"
	["us-gov-west-1"]="gw1"
	["me-south-1"]="ms1"
	["cn-north-1"]="nn0"
	["cn-northwest-1"]="nn1"
	["sa-east-1"]="se1"
	["us-east-1"]="ue1"
	["us-east-2"]="ue2"
	["us-west-1"]="uw1"
	["us-west-2"]="uw2"
)

export APPLICATION_HELMFILE=$(pwd)/${HELMFILE_PATH}/${HELMFILE}

mkdir -p /localhost/.aws

AWS_REGION_SHORT=${regions_full[$AWS_REGION]}

CLUSTER_NAME=cplive-plat-ue2-dev-eks-blue-cluster
ROLE_TO_ASSUME=arn:aws:iam::068007702576:role/cplive-plat-gbl-dev-helm

cat <<EOT > /localhost/.aws/config
[profile cicd]
region = ${AWS_REGION}
role_arn = arn:aws:iam::555042905974:role/cplive-core-gbl-identity-cicd
credential_source = Ec2InstanceMetadata

[profile default]
region = ${AWS_REGION}
role_arn = ${ROLE_TO_ASSUME}
source_profile = cicd
EOT

source /etc/profile.d/aws.sh

# Login to Kubernetes Cluster.
assume-role default aws eks --region ${AWS_REGION} update-kubeconfig --name ${CLUSTER_NAME}

# Read platform specific configs/info
assume-role default chamber export platform/${CLUSTER_NAME}/${ENVIRONMENT} --format yaml | yq --exit-status --no-colors  eval '{"platform": .}' - > /tmp/platform.yaml

if [[ "${OPERATION}" == "deploy" ]]; then
	OPERATION="apply"
elif [[ "${OPERATION}" == "destroy" ]]; then
	OPERATION="destroy"
els
	OPERATION="none"
fi

# Helm Deployment
OPERATION_COMMAND="helmfile --namespace ${NAMESPACE} --environment ${ENVIRONMENT} --file /deploy/helmfile.yaml ${OPERATION}"
echo "Executing: ${OPERATION_COMMAND}"
${OPERATION_COMMAND}

RELEASES_COUNTS=$(helm --namespace ${NAMESPACE} list --output json | jq 'length')

if [[ "${RELEASES_COUNTS}" == "0" ]]; then
	kubectl delete ns ${NAMESPACE}
fi
