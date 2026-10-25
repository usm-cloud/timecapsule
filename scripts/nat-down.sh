#!/usr/bin/env bash
# Removes what nat-up.sh created: the route, the NAT Gateway and its Elastic IP.
set -euo pipefail

export AWS_REGION=eu-central-1
ROUTE_TABLE_ID=rtb-0a0d1b6e91c763125    # timecapsule-dev-private-rt
STATE_FILE="$(dirname "$0")/.nat-state"

if [[ ! -e $STATE_FILE ]]; then
  echo "$STATE_FILE not found: nothing to remove." >&2
  exit 1
fi
ALLOC_ID="" NAT_ID="" ROUTE=""
source "$STATE_FILE"

if [[ -n $ROUTE ]]; then
  aws ec2 delete-route --route-table-id "$ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0
  echo "Route 0.0.0.0/0 removed from $ROUTE_TABLE_ID"
fi

if [[ -n $NAT_ID ]]; then
  aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" > /dev/null
  echo "NAT Gateway $NAT_ID: deleting, waiting for Deleted..."
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"
fi

# The gateway lets go of its address a little after it reaches Deleted, so retry.
for attempt in 1 2 3 4 5 6; do
  if aws ec2 release-address --allocation-id "$ALLOC_ID"; then
    rm "$STATE_FILE"
    echo "Elastic IP $ALLOC_ID released. NAT is down."
    exit 0
  fi
  echo "Attempt $attempt: address still in use, retry in 20 s"
  sleep 20
done

echo "Could not release $ALLOC_ID. Release it in the console: EC2 -> Elastic IPs." >&2
exit 1
