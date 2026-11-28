CONFIG_FILE := config.env

ifneq (,$(wildcard $(CONFIG_FILE)))
include $(CONFIG_FILE)
export
endif

AWS_PROFILE ?= aws-dev
AWS_REGION ?= us-east-1

.PHONY: login validate status delete delete-all list-stacks outputs ssm deploy-compute deploy-dns deploy-network deploy-security \
scenario scenario-list scenarios

login:
	aws sso login --profile $(AWS_PROFILE)

verify:
	aws sts get-caller-identity --profile $(AWS_PROFILE)

validate:
	@test -n "$(STACK)" || (echo "Error: STACK is missing"; exit 1)
	aws cloudformation validate-template \
		--template-body file://cloudformation/$(STACK).yaml \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

status:
	@test -n "$(STACK)" || (echo "Error: STACK is missing"; exit 1)
	aws cloudformation describe-stacks \
		--stack-name networking-lab-$(STACK) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
        --query "Stacks[0].StackStatus" \
        --output text \
		--no-cli-pager

delete:
	@test -n "$(STACK)" || (echo "Error: STACK is missing"; exit 1)
	aws cloudformation delete-stack \
		--stack-name networking-lab-$(STACK) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

list-stacks:
	aws cloudformation list-stacks \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

outputs:
	@test -n "$(STACK)" || (echo "Error: STACK is missing"; exit 1)
	aws cloudformation describe-stacks \
		--stack-name networking-lab-$(STACK) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
        --query "Stacks[0].Outputs" \
        --output table \
		--no-cli-pager

ssm:
	@test -n "$(SSM_TARGET)" || (echo "Error: SSM_TARGET is missing"; exit 1)
	aws ssm start-session \
		--target $(SSM_TARGET) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager


deploy-network:
	aws cloudformation deploy \
		--template-file cloudformation/network.yaml \
		--stack-name networking-lab-network \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--parameter-overrides EnableNatGateway=$(ENABLE_NAT) \
		--no-cli-pager

deploy-security:
	aws cloudformation deploy \
		--template-file cloudformation/security.yaml \
		--stack-name networking-lab-security \
		--capabilities CAPABILITY_NAMED_IAM \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

deploy-compute:
	@test -n "$(CERTIFICATE_ARN)" || (echo "Error: CERTIFICATE_ARN is missing"; exit 1)
	aws cloudformation deploy \
		--template-file cloudformation/compute.yaml \
		--stack-name networking-lab-compute \
		--capabilities CAPABILITY_NAMED_IAM \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--parameter-overrides CertificateArn=$(CERTIFICATE_ARN) \
		--no-cli-pager

deploy-dns:
	@test -n "$(DOMAIN_NAME)" || (echo "Error: DOMAIN_NAME is missing"; exit 1)
	@test -n "$(HOSTED_ZONE_ID)" || (echo "Error: HOSTED_ZONE_ID is missing"; exit 1)
	aws cloudformation deploy \
		--template-file cloudformation/dns.yaml \
		--stack-name networking-lab-dns \
		--capabilities CAPABILITY_NAMED_IAM \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--parameter-overrides DomainName=$(DOMAIN_NAME) HostedZoneId=$(HOSTED_ZONE_ID) \
		--no-cli-pager

delete-all:
	@echo "Deleting AWS Networking Lab stacks..."
	@echo ""

	aws cloudformation delete-stack \
		--stack-name networking-lab-dns \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

	aws cloudformation wait stack-delete-complete \
		--stack-name networking-lab-dns \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION)

	aws cloudformation delete-stack \
		--stack-name networking-lab-compute \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

	aws cloudformation wait stack-delete-complete \
		--stack-name networking-lab-compute \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION)

	aws cloudformation delete-stack \
		--stack-name networking-lab-security \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

	aws cloudformation wait stack-delete-complete \
		--stack-name networking-lab-security \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION)

	aws cloudformation delete-stack \
		--stack-name networking-lab-network \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--no-cli-pager

	aws cloudformation wait stack-delete-complete \
		--stack-name networking-lab-network \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION)

	@echo ""
	@echo "All AWS Networking Lab stacks deleted successfully."

# Troubleshooting scenarios
scenario:
	@bash scripts/scenario.sh $(or $(SCENARIO),random)

scenario-list scenarios:
	@bash scripts/scenario.sh list