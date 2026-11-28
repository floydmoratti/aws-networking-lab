
#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO_FILE="$PROJECT_DIR/scenarios/scenarios.txt"

AWS_PROFILE="${AWS_PROFILE:-aws-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
NETWORK_STACK="networking-lab-network"

if [[ ! -f "$SCENARIO_FILE" ]]; then
    echo "Error: Unable to load the scenario catalogue."
    exit 1
fi

MODE="${1:-random}"

# List available scenario IDs
if [[ "$MODE" == "list" ]]; then
    echo ""
    echo "Available troubleshooting scenarios"
    echo "-------------------------------------"

    awk -F'|' '
        !/^#/ && NF == 3 {
            printf "Scenario %s\n", $1
        }
    ' "$SCENARIO_FILE"

    echo ""
    exit 0
fi

# Select a randomly chosen implemented scenario
SCENARIO="${1:-random}"

if [[ "$SCENARIO" == "random" ]]; then
    SELECTED=$(awk -F'|' '
        !/^#/ && NF == 3 {
            entries[++count] = $0
        }

        END {
            srand()
            selection = int(rand() * count) + 1
            print entries[selection]
        }
    ' "$SCENARIO_FILE")
else
    SELECTED=$(awk -F'|' -v id="$(printf "%02d" "$SCENARIO")" '
        !/^#/ && NF == 3 && $1 == id {
            print
            exit
        }
    ' "$SCENARIO_FILE")
fi

if [[ -z "$SELECTED" ]]; then
    echo "Error: Invalid scenario number."
    exit 1
fi

IFS='|' read -r ID PROBLEM PROBLEM_REPORT <<< "$SELECTED"

# AWS CLI wrapper: suppress all command output
aws_cli() {
    aws --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --no-cli-pager "$@"
#        >/dev/null 2>&1
}

# Scenarios
inject_01() {
    ROUTE_TABLE_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "$NETWORK_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='PublicRouteTableId'].OutputValue | [0]" \
        --output text)

    aws_cli ec2 delete-route \
        --route-table-id "$ROUTE_TABLE_ID" \
        --destination-cidr-block 0.0.0.0/0
}

inject_02() {
    ROUTE_TABLE_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "$NETWORK_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='PrivateRouteTableId'].OutputValue | [0]" \
        --output text)

    aws_cli ec2 delete-route \
        --route-table-id "$ROUTE_TABLE_ID" \
        --destination-cidr-block 0.0.0.0/0
}

inject_03() {
    SUBNET_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "$NETWORK_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetAId'].OutputValue | [0]" \
        --output text)

    ASSOCIATION_ID=$(aws_cli ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
        --query "RouteTables[0].Associations[?SubnetId=='$SUBNET_ID'].RouteTableAssociationId | [0]" \
        --output text)

    aws_cli ec2 disassociate-route-table \
        --association-id "$ASSOCIATION_ID"
}

inject_04() {
    NAT_GATEWAY_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "$NETWORK_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='NatGatewayId'].OutputValue | [0]" \
        --output text)

    aws_cli ec2 delete-nat-gateway \
        --nat-gateway-id "$NAT_GATEWAY_ID"
}

inject_05() {
    ALB_SG_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-security" \
        --query "Stacks[0].Outputs[?OutputKey=='ALBSecurityGroupId'].OutputValue | [0]" \
        --output text)

    aws_cli ec2 revoke-security-group-ingress \
        --group-id "$ALB_SG_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0

    aws_cli ec2 revoke-security-group-ingress \
        --group-id "$ALB_SG_ID" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
}

inject_06() {
    WEB_SG_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-security" \
        --query "Stacks[0].Outputs[?OutputKey=='WebServerSecurityGroupId'].OutputValue | [0]" \
        --output text)

    ALB_SG_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-security" \
        --query "Stacks[0].Outputs[?OutputKey=='ALBSecurityGroupId'].OutputValue | [0]" \
        --output text)

    aws_cli ec2 revoke-security-group-ingress \
        --group-id "$WEB_SG_ID" \
        --protocol tcp \
        --port 80 \
        --source-group "$ALB_SG_ID"
}

inject_07() {
    WEB_SG_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-security" \
        --query "Stacks[0].Outputs[?OutputKey=='WebServerSecurityGroupId'].OutputValue | [0]" \
        --output text)

    ALB_SG_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-security" \
        --query "Stacks[0].Outputs[?OutputKey=='ALBSecurityGroupId'].OutputValue | [0]" \
        --output text)

    VPC_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "$NETWORK_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue | [0]" \
        --output text)

    DEFAULT_SG_ID=$(aws_cli ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
        --query "SecurityGroups[0].GroupId" \
        --output text)

    aws_cli ec2 revoke-security-group-ingress \
        --group-id "$WEB_SG_ID" \
        --protocol tcp \
        --port 80 \
        --source-group "$ALB_SG_ID"

    aws_cli ec2 authorize-security-group-ingress \
        --group-id "$WEB_SG_ID" \
        --protocol tcp \
        --port 80 \
        --source-group "$DEFAULT_SG_ID"
}

inject_08() {
    ROLE_ARN=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-security" \
        --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue | [0]" \
        --output text)

    ROLE_NAME="${ROLE_ARN##*/}"

    aws_cli iam detach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
}

inject_09() {
    INSTANCE_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-compute" \
        --query "Stacks[0].Outputs[?OutputKey=='WebserverInstanceId'].OutputValue | [0]" \
        --output text)

    aws_cli ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["systemctl stop apache2"]' \
        --comment "Troubleshooting scenario injection"
}

inject_10() {
    INSTANCE_ID=$(aws_cli cloudformation describe-stacks \
        --stack-name "networking-lab-compute" \
        --query "Stacks[0].Outputs[?OutputKey=='WebserverInstanceId'].OutputValue | [0]" \
        --output text)

    aws_cli ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sed -i \"s/Listen 80/Listen 8080/\" /etc/apache2/ports.conf", "systemctl restart apache2"]' \
        --comment "Troubleshooting scenario injection"
}


# Inject selected scenario
echo ""
echo "========================================"
echo "       AWS TROUBLESHOOTING LAB"
echo "========================================"
echo ""
echo "Preparing a new troubleshooting scenario..."


if declare -f "inject_$ID" > /dev/null; then
    "inject_$ID"
else
    echo "Error: Scenario not implemented."
    exit 1
fi


# Display customer report
echo ""
echo "Scenario successfully deployed."
echo ""
echo "Scenario: $ID"
echo ""
echo "CUSTOMER REPORT"
echo "----------------------------------------"
echo "$PROBLEM_REPORT"
echo "----------------------------------------"
echo ""
echo "Investigate the problem, identify the root cause,"
echo "restore service and document your findings."
echo ""
