require "rubygems"
require "bundler"
Bundler.setup

desc "Create CloudFormation S3 Bucket if it does not exist yet"
task :prepare do
  @deploy_stack = true
  require_relative "lib/prepare"
end

desc "Compile CloudFormation Template"
task :compile do
  require_relative "lib/prepare"
  require_relative "lib/main"
end

desc "Build our Lambda function"
task :build do
  require_relative "lib/build"
end

task :deploy_application do
  @deploy_stack = true
  require_relative "lib/main"
end

task apply: [:prepare, :build, :deploy_application]
task default: [:compile]
