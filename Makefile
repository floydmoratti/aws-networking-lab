PROFILE = aws-dev
REGION = us-east-1

.PHONY: login validate deploy status delete list-stacks outputs ssm

login:
	aws sso login --profile $(PROFILE)

verify:
	aws sts get-caller-identity --profile $(PROFILE)

validate:
	aws cloudformation validate-template \
		--template-body file://cloudformation/$(STACK).yaml \
		--profile $(PROFILE) \
		--region $(REGION) \
		--no-cli-pager

deploy:
	aws cloudformation deploy \
		--template-file cloudformation/$(STACK).yaml \
		--stack-name networking-lab-$(STACK) \
		--capabilities CAPABILITY_NAMED_IAM \
		--profile $(PROFILE) \
		--region $(REGION) \
		--parameter-overrides EnableNatGateway=$(NAT)

status:
	aws cloudformation describe-stacks \
		--stack-name networking-lab-$(STACK) \
		--profile $(PROFILE) \
		--region $(REGION) \
        --query "Stacks[0].StackStatus" \
        --output text

delete:
	aws cloudformation delete-stack \
		--stack-name networking-lab-$(STACK) \
		--profile $(PROFILE) \
		--region $(REGION)

list-stacks:
	aws cloudformation list-stacks \
		--profile $(PROFILE) \
		--region $(REGION)

outputs:
	aws cloudformation describe-stacks \
		--stack-name networking-lab-$(STACK) \
		--profile $(PROFILE) \
		--region $(REGION) \
        --query "Stacks[0].Outputs" \
        --output table

ssm:
	aws ssm start-session \
		--target $(TARGET) \
		--profile $(PROFILE) \
		--region $(REGION)