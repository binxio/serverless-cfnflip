# CFN Flip

This codebase holds the code to deploy a serverless version of the
cfn-flip tool with, capable of converting CloudFormation between JSON
and YAML and the ability to convert JSON to Ruby CfnDsl.

A demo is available at: https://cfnflip.com/

## Requirements

- Modern Ruby version with the bundler gem installed
- Copy .env.private.sample to .env.private and set your credentials

## Installing gems

Type `bundle` to install all dependencies. If you don't have bundle installed
you can install it with `gem install bundler`.

## CloudFormation templates

Type `rake` to compile the CfnDsl code into CloudFormation templates.
The templates are stored in the build/ directory in json format.

It compiles a dependency stack for the Route53 HostedZone, domain name, and
artifact bucket, and an application stack with the Lambda-backed API Gateway
resources.

## Dependency stack

The dependency stack is created with the `rake prepare` command. This stack
creates a Route53 Hosted Zone, and configures the Route 53 domain name with
a Lambda-backed Custom Resource with the correct DNS servers. In addition,
it creates an artifact bucket. This is used for storing the Lambda
deployment packages. The dependency stack is required by the application
stack.

## Lambda

Type `rake build` to compile the deployment packages. A MD5 hash of the
collection of files in each deployment package is used as the latest
version.

## Deploying everything

Type `rake build && rake compile && rake apply` to deploy the latest code.
