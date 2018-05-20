require "cfndsl"
require "dotenv"
require "aws-sdk"

require_relative "tasks"

class String
  def cfnize
    return self if self !~ /_/ && self =~ /[A-Z]+.*/
    split(/[_, -]/).map{ |e| e.capitalize }.join
  end

  def cfnize!
    replace self.cfnize
  end
end

# Load ENV vars
Dotenv.load(".env")
Dotenv.load(".env.private")

# Set defaults
ENV["AWS_REGION"] ||= "eu-west-1"
ENV["HOSTED_ZONE_NAME"] ||= "example.com"

raise "PROJECT_NAME not set." unless ENV["PROJECT_NAME"]
raise "AWS_ACCESS_KEY_ID not set." unless ENV["AWS_ACCESS_KEY_ID"]
raise "AWS_SECRET_ACCESS_KEY not set." unless ENV["AWS_SECRET_ACCESS_KEY"]

ENV["PROJECT_NAME"] = ENV["PROJECT_NAME"].cfnize

# Create an initialisation stack with immutable dependencies
template = CloudFormation do
  AWSTemplateFormatVersion("2010-09-09")

  Parameter("DomainName") do
    Description "Domain name for the hosted zone"
    Type "String"
    Default ENV["HOSTED_ZONE_NAME"]
  end

  Parameter("ProjectName") do
    Description "Name of your project, e.g. cfnflip"
    Type "String"
    Default ENV["PROJECT_NAME"]
  end

  Resource("CloudformationBucket") do
    Type("AWS::S3::Bucket")
  end

  Resource("LambdaFunctionRole") do
    Type "AWS::IAM::Role"
    Property(:Path, "/")
    Property(:AssumeRolePolicyDocument,
      {
        Version: "2012-10-17",
        Statement: [
          {
            Effect: :Allow,
            Principal: {
              Service: "lambda.amazonaws.com"
            },
            Action: [
              "sts:AssumeRole"
            ]
          }
        ]
      }
    )
    Property(
      :Policies,
      [
        {
          PolicyDocument: {
            Version: "2012-10-17",
            Statement: [
              {
                Action: %w(
                  logs:CreateLogGroup
                  logs:CreateLogStream
                  logs:PutLogEvents
                ),
                Effect: :Allow,
                Resource: "arn:aws:logs:*:*:*"
              },
              {
                Action: [
                  "route53domains:UpdateDomainNameservers"
                ],
                Effect: :Allow,
                Resource: "*"
              },
            ]
          },
          PolicyName: "Route53LambdaUpdateRole"
        }
      ]
    )
  end

  Resource("UpdateRoute53") do
    DependsOn %i(LambdaFunction HostedZone)
    Type "Custom::UpdateRoute53"
    Property(:HostedZone, Ref("DomainName"))
    Property(:Nameservers, FnGetAtt("HostedZone", "NameServers"))
    Property(:ServiceToken, FnGetAtt("LambdaFunction", "Arn"))
  end

  Resource("LambdaFunction") do
    Type "AWS::Lambda::Function"
    DependsOn :LambdaFunctionRole
    Property(:Handler, "index.handler")
    Property(:Role, FnGetAtt("LambdaFunctionRole", "Arn"))
    Property(:Code, ZipFile: FnJoin(
      "\n",
      [
        "var AWS = require('aws-sdk');",
        "AWS.config.update({region: 'us-east-1'});",
        "var response = require('cfn-response');",
        "exports.handler = function(event, context) {",
        "    var nameservers = event.ResourceProperties.Nameservers;",
        "    var domainname  = event.ResourceProperties.HostedZone;",
        "",
        "    console.log(nameservers);",
        "    console.log(domainname);",
        "    if (event.RequestType == 'Delete') {",
        "        var responseData = { Value: 'Go ahead.' };",
        "        response.send(event, context, response.SUCCESS, responseData);",
        "    }",
        "    else",
        "    {",
        "",
        "        var route53domains = new AWS.Route53Domains();",
        "        var ServerList = [];",
        "        nameservers.forEach(function(server){",
        "          ServerList.push({",
        "            Name: server",
        "          })",
        "        });",
        "        route53domains.updateDomainNameservers(",
        "            {",
        "                DomainName: domainname,",
        "                Nameservers: ServerList",
        "            }, function(err, data) {",
        "                if (err) console.log(err, err.stack);",
        "                else     console.log(data);",
        "                var responseData = { Value: 'Hurray!' };",
        "                response.send(event, context, response.SUCCESS, responseData);",
        "            }",
        "        )",
        "    }",
        "};"
      ])
    )
    Property(:Runtime, "nodejs6.10")
    Property(:MemorySize, "128")
    Property(:Timeout, "25")
  end

  Resource("HostedZone") do
    Type("AWS::Route53::HostedZone")
    Property(:HostedZoneConfig, {
      Comment: FnJoin("",
        [
          "HostedZone for ",
          Ref("DomainName")
        ]
      )
    })
    Property(:Name, Ref("DomainName"))
  end

  Output(:HostedZoneId) do
    Value Ref("HostedZone")
    Export FnJoin("",
      [
        Ref("ProjectName"),
        "HostedZoneId"
      ]
    )
  end

  Output(:HostedZoneName) do
    Value Ref("DomainName")
    Export FnJoin("",
      [
        Ref("ProjectName"),
        "HostedZoneName"
      ]
    )
  end

  Output(:CloudformationBucket) do
    Value Ref("CloudformationBucket")
    Export FnJoin("",
      [
        Ref("ProjectName"),
        "CloudformationBucket"
      ]
    )
  end
end

Aws.config.update({
  region: ENV["AWS_REGION"],
  credentials: Aws::Credentials.new(
    ENV["AWS_ACCESS_KEY_ID"], ENV["AWS_SECRET_ACCESS_KEY"]
  )
})

@deploy_stack = false if @deploy_stack == true &&
                         stack_exists(
                           "#{ENV["PROJECT_NAME"].downcase}-dependency-stack"
                         )
@deploy_stack ||= false

create_stack(
  template.to_json,
  "#{ENV["PROJECT_NAME"].downcase}-dependency-stack",
  @deploy_stack,
  5
)
