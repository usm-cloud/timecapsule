#!/usr/bin/env bash
# Creates a temporary NAT Gateway so db-server can download packages.
# Remove it with nat-down.sh the same day: it is billed by the hour.
set -euo pipefail

export AWS_REGION=eu-central-1
SUBNET_ID=subnet-088d881233a4bc4e7      # timecapsule-dev-public-a
ROUTE_TABLE_ID=rtb-0a0d1b6e91c763125    # timecapsule-dev-private-rt
OWNER=semion
STATE_FILE="$(dirname "$0")/.nat-state"

tags() {
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value=$OWNER},{Key=Lab,Value=lab3}]"
}

if [[ -e $STATE_FILE ]]; then
  echo "$STATE_FILE exists: a NAT Gateway may still be up. Run nat-down.sh first." >&2
  exit 1
fi

ALLOC_ID=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications "$(tags elastic-ip timecapsule-dev-nat-a-eip)" \
  --query AllocationId --output text)
# Saved after each step, so nat-down.sh can clean up even if a later step fails.
echo "ALLOC_ID=$ALLOC_ID" > "$STATE_FILE"
echo "Elastic IP: $ALLOC_ID"

NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$SUBNET_ID" --allocation-id "$ALLOC_ID" \
  --tag-specifications "$(tags natgateway timecapsule-dev-nat-a)" \
  --query NatGateway.NatGatewayId --output text)
echo "NAT_ID=$NAT_ID" >> "$STATE_FILE"
echo "NAT Gateway: $NAT_ID, waiting for Available..."

aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

aws ec2 create-route --route-table-id "$ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" > /dev/null
echo "ROUTE=yes" >> "$STATE_FILE"
echo "Route 0.0.0.0/0 -> $NAT_ID added to $ROUTE_TABLE_ID. NAT is up."
