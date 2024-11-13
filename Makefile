include Makefile.mk

USERNAME=xebia
NAME=cfn-mysql-user-provider

AWS_REGION=eu-central-1
AWS_ACCOUNT=$(shell aws sts get-caller-identity --query Account --output text)
REGISTRY_HOST=$(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com
IMAGE=$(REGISTRY_HOST)/$(USERNAME)/$(NAME)
TAG_WITH_LATEST=never
DOCKER_BUILD_ARGS=--platform linux/x86_64


requirements.txt test-requirements.txt: Pipfile.lock
	pipenv requirements > requirements.txt
	pipenv requirements --dev-only > test-requirements.txt

Pipfile.lock: Pipfile
	pipenv update

test: Pipfile.lock
	for n in ./cloudformation/*.yaml ; do aws cloudformation validate-template --template-body file://$$n ; done
	PYTHONPATH=$(PWD)/src pipenv run pytest ./tests/test*.py

pre-build: requirements.txt


fmt:
	black src/*.py tests/*.py

deploy-provider:  ## deploy the provider to the current account
	sed -i '' -e 's^$(NAME):[0-9]*\.[0-9]*\.[0-9]*[^\.]*^$(NAME):$(VERSION)^' cloudformation/cfn-resource-provider.yaml
	aws cloudformation deploy \
                --stack-name $(NAME) \
                --capabilities CAPABILITY_IAM \
                --template-file ./cloudformation/cfn-resource-provider.yaml \
		--parameter-overrides \
			VPC=$(shell bin/get-default-vpc) \
			Subnets=$(shell bin/get-private-subnets) \
			SecurityGroup=$(shell bin/get-default-security-group)

delete-provider:   ## delete provider from the current account
	aws cloudformation delete-stack --stack-name $(NAME)
	aws cloudformation wait stack-delete-complete  --stack-name $(NAME)



deploy-pipeline:   ## deploy the CI/CD pipeline
	aws cloudformation deploy \
                --stack-name $(NAME)-pipeline \
                --capabilities CAPABILITY_IAM \
                --template-file ./cloudformation/cicd-pipeline.yaml \
		--parameter-overrides Name=$(NAME)

delete-pipeline:   ## delete the CI/CD pipeline
	aws cloudformation delete-stack --stack-name $(NAME)-pipeline
	aws cloudformation wait stack-delete-complete  --stack-name $(NAME)-pipeline

demo:		   ## deploy the demo
	aws cloudformation deploy \
		--stack-name $(NAME)-demo \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file ./cloudformation/demo-stack.yaml \
		--parameter-overrides \
			VPC=$(shell bin/get-default-vpc) \
			Subnets=$(shell bin/get-private-subnets) \
			SecurityGroup=$(shell bin/get-default-security-group)

delete-demo:	   ## delete the demo
	aws cloudformation delete-stack --stack-name $(NAME)-demo
	aws cloudformation wait stack-delete-complete  --stack-name $(NAME)-demo

ecr-login:	   ## login to the ECR repository
	aws ecr get-login-password --region $(AWS_REGION) | \
	docker login --username AWS --password-stdin $(REGISTRY_HOST)

deploy-private-subnets:  ## deploy private subnets in the default VPC
	aws cloudformation deploy \
                --stack-name $(NAME)-demo-private-subnets \
                --capabilities CAPABILITY_IAM \
                --template-file ./cloudformation/private-subnets-for-default-vpc.yaml \
		--parameter-overrides \
			VPC=$(shell bin/get-default-vpc) \
			Subnets=$(shell bin/get-public-subnets)

delete-private-subnets:  ## delete private subnets from the default VPC
	aws cloudformation delete-stack \
                --stack-name $(NAME)-demo-private-subnets
	aws cloudformation wait stack-delete-complete  --stack-name $(NAME)-demo-private-subnets

