require "cfndsl"
require "json"
require "dotenv"
require "aws-sdk"

# Load ENV vars
Dotenv.load(".env")
Dotenv.load(".env.application")
Dotenv.load(".env.backend")
Dotenv.load(".env.cfn2dsl")
Dotenv.load(".env.private")

# Set defaults
ENV["AWS_REGION"] ||= "eu-west-1"
ENV["HOSTED_ZONE_NAME"] ||= "example.com"

raise "AWS_ACCESS_KEY_ID not set." unless ENV["AWS_ACCESS_KEY_ID"]
raise "AWS_SECRET_ACCESS_KEY not set." unless ENV["AWS_SECRET_ACCESS_KEY"]

template = CloudFormation do
  Description("cfnflip.com application stack")
  AWSTemplateFormatVersion("2010-09-09")

  ## Common resources
  Resource("IamRoleLambdaExecution") do
    Type("AWS::IAM::Role")
    Property(
      :AssumeRolePolicyDocument,
      {
        Statement: [
          {
            Action: [
              "sts:AssumeRole"
            ],
            Effect: "Allow",
            Principal: {
              Service: [
                "lambda.amazonaws.com"
              ]
            }
          }
        ],
        Version: "2012-10-17"
      }
    )
    Property(
      :Policies,
      [
        {
          PolicyDocument: {
            Statement: [
              {
                Action: [
                  "logs:CreateLogStream"
                ],
                Effect: "Allow",
                Resource: [
                  FnSub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:" \
                        "log-group:/aws/lambda/cfnflip:*"),
                  FnSub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:" \
                        "log-group:/aws/lambda/pyflip:*"),
                  FnSub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:" \
                        "log-group:/aws/lambda/cfn2dsl:*")
                ]
              },
              {
                Action: [
                  "logs:PutLogEvents"
                ],
                Effect: "Allow",
                Resource: [
                  FnSub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:" \
                        "log-group:/aws/lambda/cfnflip:*:*"),
                  FnSub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:" \
                        "log-group:/aws/lambda/pyflip:*:*"),
                  FnSub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:" \
                        "log-group:/aws/lambda/cfn2dsl:*:*")
                ]
              }
            ],
            Version: "2012-10-17"
          },
          PolicyName: FnJoin("-", %w(cfnflip lambda))
        }
      ]
    )
    Property(:Path, "/")
    Property(:RoleName, FnJoin("-", %w(cfnflip eu-west-1 lambdaRole)))
  end

  Resource(:ApiGatewayRestApi) do
    Type("AWS::ApiGateway::RestApi")
    Property(:Name, "cfnflip")
  end

  Resource("ApiGatewayDeployment#{Date.today.to_time.to_i}") do
    Type("AWS::ApiGateway::Deployment")
    DependsOn(
      %w(ApiGatewayMethodGet ApiGatewayMethodPythonPost)
    )
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
    Property(:StageName, "production")
  end

  Resource("APIGatewayCustomDomainName") do
    Type("AWS::ApiGateway::DomainName")
    Property(:CertificateArn, ENV["ACM_CERTIFICATE_ARN"])
    Property(:DomainName, FnImportValue("CfnFlipHostedZoneName"))
  end

  Resource("APIGatewayCustomDomainNameMapping") do
    DependsOn(
      %w(APIGatewayCustomDomainName)
    )
    Type("AWS::ApiGateway::BasePathMapping")
    Property(:DomainName, FnImportValue("CfnFlipHostedZoneName"))
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
    Property(:Stage, "production")
  end

  Resource("APIGatewayRoute53CloudFrontAlias") do
    Type("AWS::Route53::RecordSetGroup")
    Property(:HostedZoneId, FnImportValue("CfnFlipHostedZoneId"))
    Property(
      :RecordSets,
      [
        {
          Name: FnImportValue("CfnFlipHostedZoneName"),
          Type: "A",
          AliasTarget: {
            HostedZoneId: "Z2FDTNDATAQYW2",
            DNSName: FnGetAtt(
              "APIGatewayCustomDomainName", "DistributionDomainName"
            )
          }
        }
      ]
    )
  end

  Output(:ServiceEndpoint) do
    Description("APIGateway URL")
    Value(
      FnJoin("", [
        "https://",
        Ref("ApiGatewayRestApi"),
        ".execute-api.eu-west-1.amazonaws.com/production"
      ])
    )
  end

  ## Cfn2Dsl Ruby implementation
  Resource("CfnFlipRubyLogGroup") do
    Type("AWS::Logs::LogGroup")
    Property(:RetentionInDays, 7)
    Property(:LogGroupName, "/aws/lambda/cfn2dsl")
  end

  Resource("CfnFlipRubyLambdaFunction") do
    Type("AWS::Lambda::Function")
    DependsOn(
      %w(IamRoleLambdaExecution CfnFlipRubyLogGroup)
    )
    Property(
      :Code,
      {
        S3Bucket: FnImportValue(:CfnFlipCloudformationBucket),
        S3Key: "cfn2dsl#{ENV["LATEST_VERSION_CFN2DSL"]}.zip"
      }
    )
    Property(:Handler, "ruby.handler")
    Property(:FunctionName, "cfn2dsl")
    Property(:MemorySize, 256)
    Property(:Role, FnGetAtt("IamRoleLambdaExecution", "Arn"))
    Property(:Runtime, "nodejs6.10")
    Property(:Timeout, 10)
  end

  Resource("ApiGatewayResourceRuby") do
    Type("AWS::ApiGateway::Resource")
    Property(:ParentId, FnGetAtt("ApiGatewayRestApi", "RootResourceId"))
    Property(:PathPart, "cfn2dsl")
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
  end

  Resource("ApiGatewayMethodRubyOptions") do
    Type("AWS::ApiGateway::Method")
    Property(:AuthorizationType, "NONE")
    Property(:HttpMethod, "OPTIONS")
    Property(
      :MethodResponses,
      [
        {
          ResponseModels: {},
          ResponseParameters: {
            "method.response.header.Access-Control-Allow-Credentials" => true,
            "method.response.header.Access-Control-Allow-Headers" => true,
            "method.response.header.Access-Control-Allow-Methods" => true,
            "method.response.header.Access-Control-Allow-Origin" => true
          },
          StatusCode: "200"
        }
      ]
    )
    Property(:RequestParameters, {})
    Property(
      :Integration,
      {
        IntegrationResponses: [
          {
            ResponseParameters: {
              "method.response.header.Access-Control-Allow-Credentials" => "'false'",
              "method.response.header.Access-Control-Allow-Headers" => "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
              "method.response.header.Access-Control-Allow-Methods" => "'OPTIONS,POST'",
              "method.response.header.Access-Control-Allow-Origin" => "'*'"
            },
            ResponseTemplates: {
              "application/json" => ""
            },
            StatusCode: "200"
          }
        ],
        RequestTemplates: {
          "application/json" => "{statusCode:200}"
        },
        Type: "MOCK"
      }
    )
    Property(:ResourceId, Ref("ApiGatewayResourceRuby"))
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
  end

  Resource("ApiGatewayMethodRubyPost") do
    Type("AWS::ApiGateway::Method")
    Property(:HttpMethod, "POST")
    Property(:RequestParameters, {})
    Property(:ResourceId, Ref("ApiGatewayResourceRuby"))
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
    Property(:AuthorizationType, "NONE")
    Property(
      :Integration,
      {
        RequestTemplates: {
          "application/x-www-form-urlencoded":
            "#set($allParams = $input.params())\n{\n  \"params\" : {\n    #foreach($type in $allParams.keySet())\n    #set($params = $allParams.get($type))\n    \"$type\" : {\n      #foreach($paramName in $params.keySet())\n      \"$paramName\" : \"$util.escapeJavaScript($params.get($paramName))\"\n      #if($foreach.hasNext),#end\n      #end\n    }\n    #if($foreach.hasNext),#end\n    #end\n  }\n}\n"
        },
        IntegrationHttpMethod: "POST",
        Type: "AWS_PROXY",
        Uri: FnJoin("", [
          "arn:aws:apigateway:",
          Ref("AWS::Region"),
          ":lambda:path/2015-03-31/functions/",
          FnGetAtt("CfnFlipRubyLambdaFunction", "Arn"),
          "/invocations"
        ])
      }
    )
    Property(:MethodResponses, [])
  end

  Resource("CfnFlipRubyLambdaPermissionApiGateway") do
    Type("AWS::Lambda::Permission")
    Property(:FunctionName, FnGetAtt("CfnFlipRubyLambdaFunction", "Arn"))
    Property(:Action, "lambda:InvokeFunction")
    Property(:Principal, "apigateway.amazonaws.com")
    Property(:SourceArn, FnJoin("", [
      "arn:aws:execute-api:",
      Ref("AWS::Region"),
      ":",
      Ref("AWS::AccountId"),
      ":",
      Ref("ApiGatewayRestApi"),
      "/*/*"
    ]))
  end
  ## End of Cfn2Dsl Ruby implementation

  ## Lander page Lambda function implementation
  Resource("CfnFlipLogGroup") do
    Type("AWS::Logs::LogGroup")
    Property(:RetentionInDays, 7)
    Property(:LogGroupName, "/aws/lambda/cfnflip")
  end

  Resource("CfnFlipLambdaFunction") do
    Type("AWS::Lambda::Function")
    DependsOn(
      %w(IamRoleLambdaExecution CfnFlipLogGroup)
    )
    Property(
      :Code,
      {
        S3Bucket: FnImportValue(:CfnFlipCloudformationBucket),
        S3Key: "application#{ENV["LATEST_VERSION_APPLICATION"]}.zip"
      }
    )
    Property(:FunctionName, "cfnflip")
    Property(:Handler, "handler.frontPage")
    Property(:MemorySize, 128)
    Property(:Role, FnGetAtt("IamRoleLambdaExecution", "Arn"))
    Property(:Runtime, "nodejs6.10")
    Property(:Timeout, 6)
  end

  Resource("ApiGatewayMethodOptions") do
    Type("AWS::ApiGateway::Method")
    Property(:AuthorizationType, "NONE")
    Property(:HttpMethod, "OPTIONS")
    Property(
      :MethodResponses,
      [
        {
          ResponseModels: {},
          ResponseParameters: {
            "method.response.header.Access-Control-Allow-Credentials" => true,
            "method.response.header.Access-Control-Allow-Headers" => true,
            "method.response.header.Access-Control-Allow-Methods" => true,
            "method.response.header.Access-Control-Allow-Origin" => true
          },
          StatusCode: "200"
        }
      ]
    )
    Property(:RequestParameters, {})
    Property(
      :Integration,
      {
        IntegrationResponses: [
          {
            ResponseParameters: {
              "method.response.header.Access-Control-Allow-Credentials" => "'false'",
              "method.response.header.Access-Control-Allow-Headers" => "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
              "method.response.header.Access-Control-Allow-Methods" => "'OPTIONS,GET'",
              "method.response.header.Access-Control-Allow-Origin" => "'*'"
            },
            ResponseTemplates: {
              "application/json" => ""
            },
            StatusCode: "200"
          }
        ],
        RequestTemplates: {
          "application/json" => "{statusCode:200}"
        },
        Type: "MOCK"
      }
    )
    Property(:ResourceId, FnGetAtt("ApiGatewayRestApi", "RootResourceId"))
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
  end

  Resource("ApiGatewayMethodGet") do
    Type("AWS::ApiGateway::Method")
    Property(:HttpMethod, "GET")
    Property(:RequestParameters, {})
    Property(:ResourceId, FnGetAtt("ApiGatewayRestApi", "RootResourceId"))
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
    Property(:AuthorizationType, "NONE")
    Property(
      :Integration,
      {
        PassthroughBehavior: "WHEN_NO_MATCH",
        IntegrationHttpMethod: "POST",
        Type: "AWS_PROXY",
        Uri: FnJoin("", [
          "arn:aws:apigateway:",
          Ref("AWS::Region"),
          ":lambda:path/2015-03-31/functions/",
          FnGetAtt("CfnFlipLambdaFunction", "Arn"),
          "/invocations"
        ])
      }
    )
    Property(:MethodResponses, [])
  end

  Resource("CfnFlipLambdaPermissionApiGateway") do
    Type("AWS::Lambda::Permission")
    Property(:FunctionName, FnGetAtt("CfnFlipLambdaFunction", "Arn"))
    Property(:Action, "lambda:InvokeFunction")
    Property(:Principal, "apigateway.amazonaws.com")
    Property(:SourceArn, FnJoin("", [
      "arn:aws:execute-api:",
      Ref("AWS::Region"),
      ":",
      Ref("AWS::AccountId"),
      ":",
      Ref("ApiGatewayRestApi"),
      "/*/*"
    ]))
  end

  ## End of lander implementation

  ## cfnflip Python lambda endpoint implementation
  Resource("CfnFlipPythonLogGroup") do
    Type("AWS::Logs::LogGroup")
    Property(:RetentionInDays, 7)
    Property(:LogGroupName, "/aws/lambda/pyflip")
  end

  Resource("CfnFlipPythonLambdaFunction") do
    Type("AWS::Lambda::Function")
    DependsOn(
      %w(IamRoleLambdaExecution CfnFlipPythonLogGroup)
    )
    Property(
      :Code,
      {
        S3Bucket: FnImportValue(:CfnFlipCloudformationBucket),
        S3Key: "backend#{ENV["LATEST_VERSION_BACKEND"]}.zip"
      }
    )
    Property(:Handler, "lambda_function.lambda_handler")
    Property(:FunctionName, "pyflip")
    Property(:MemorySize, 128)
    Property(:Role, FnGetAtt("IamRoleLambdaExecution", "Arn"))
    Property(:Runtime, "python2.7")
    Property(:Timeout, 20)
  end

  Resource("ApiGatewayResourcePython") do
    Type("AWS::ApiGateway::Resource")
    Property(:ParentId, FnGetAtt("ApiGatewayRestApi", "RootResourceId"))
    Property(:PathPart, "flip")
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
  end

  Resource("ApiGatewayMethodPythonOptions") do
    Type("AWS::ApiGateway::Method")
    Property(:AuthorizationType, "NONE")
    Property(:HttpMethod, "OPTIONS")
    Property(
      :MethodResponses,
      [
        {
          ResponseModels: {},
          ResponseParameters: {
            "method.response.header.Access-Control-Allow-Credentials" => true,
            "method.response.header.Access-Control-Allow-Headers" => true,
            "method.response.header.Access-Control-Allow-Methods" => true,
            "method.response.header.Access-Control-Allow-Origin" => true
          },
          StatusCode: "200"
        }
      ]
    )
    Property(:RequestParameters, {})
    Property(
      :Integration,
      {
        IntegrationResponses: [
          {
            ResponseParameters: {
              "method.response.header.Access-Control-Allow-Credentials" => "'false'",
              "method.response.header.Access-Control-Allow-Headers" => "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
              "method.response.header.Access-Control-Allow-Methods" => "'OPTIONS,POST'",
              "method.response.header.Access-Control-Allow-Origin" => "'*'"
            },
            ResponseTemplates: {
              "application/json" => ""
            },
            StatusCode: "200"
          }
        ],
        RequestTemplates: {
          "application/json" => "{statusCode:200}"
        },
        Type: "MOCK"
      }
    )
    Property(:ResourceId, Ref("ApiGatewayResourcePython"))
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
  end



  Resource("ApiGatewayMethodPythonPost") do
    Type("AWS::ApiGateway::Method")
    Property(:HttpMethod, "POST")
    Property(:RequestParameters, {})
    Property(:ResourceId, Ref("ApiGatewayResourcePython"))
    Property(:RestApiId, Ref("ApiGatewayRestApi"))
    Property(:AuthorizationType, "NONE")
    Property(
      :Integration,
      {
        RequestTemplates: {
          "application/x-www-form-urlencoded" => "#set($allParams = $input.params())\n{\n  \"params\" : {\n    #foreach($type in $allParams.keySet())\n    #set($params = $allParams.get($type))\n    \"$type\" : {\n      #foreach($paramName in $params.keySet())\n      \"$paramName\" : \"$util.escapeJavaScript($params.get($paramName))\"\n      #if($foreach.hasNext),#end\n      #end\n    }\n    #if($foreach.hasNext),#end\n    #end\n  }\n}\n"
        },
        IntegrationHttpMethod: "POST",
        Type: "AWS_PROXY",
        Uri: FnJoin("", [
          "arn:aws:apigateway:",
          Ref("AWS::Region"),
          ":lambda:path/2015-03-31/functions/",
          FnGetAtt("CfnFlipPythonLambdaFunction", "Arn"),
          "/invocations"
        ])
      }
    )
    Property(:MethodResponses, [])
  end

  Resource("CfnFlipPythonLambdaPermissionApiGateway") do
    Type("AWS::Lambda::Permission")
    Property(:FunctionName, FnGetAtt("CfnFlipPythonLambdaFunction", "Arn"))
    Property(:Action, "lambda:InvokeFunction")
    Property(:Principal, "apigateway.amazonaws.com")
    Property(
      :SourceArn,
      FnJoin("", [
        "arn:aws:execute-api:",
        Ref("AWS::Region"),
        ":",
        Ref("AWS::AccountId"),
        ":",
        Ref("ApiGatewayRestApi"),
        "/*/*"
      ])
    )
  end
  ## End of cfnflip Python lambda endpoint implementation

end

create_stack(
  template.to_json,
  "#{ENV["PROJECT_NAME"].downcase}-application-stack",
  @deploy_stack,
  60
)
