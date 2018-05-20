require "digest"
require "dotenv"
require "aws-sdk"
require "FileUtils"

require_relative "zipper"
require_relative "tasks"

Dotenv.load(".env")
Dotenv.load(".env.private")
Dotenv.load(".env.application")
Dotenv.load(".env.backend")
Dotenv.load(".env.cfn2dsl")

# Monkey patch String class to add the cfnize method to camelcase strings.
class String
  def cfnize
    return self if self !~ /_/ && self =~ /[A-Z]+.*/
    split(/[_, -]/).map{ |e| e.capitalize }.join
  end

  def cfnize!
    replace self.cfnize
  end
end

ENV["PROJECT_NAME"] = ENV["PROJECT_NAME"].cfnize
ENV["AWS_REGION"] ||= ENV["AWS_DEFAULT_REGION"]

stack_name = "#{ENV["PROJECT_NAME"].downcase}-dependency-stack"
Aws.config.update(
  region: "#{ENV["AWS_REGION"]}",
  credentials: Aws::Credentials.new(
    ENV["AWS_ACCESS_KEY_ID"], ENV["AWS_SECRET_ACCESS_KEY"]
  )
)

cfn = Aws::CloudFormation::Client.new
begin
  stacks = cfn.describe_stacks(
      stack_name: stack_name
  )
  bucket = stacks.stacks[0].outputs.map do |output|
    if output.output_key == "CloudformationBucket"
      output.output_value
    end
  end.reject(&:nil?).first
rescue => exception
  raise exception
end

archives = {
  application: "src/cfnflip.com",
  backend: "src/cfnflip-python-lambda",
}

archives.each do |k, v|
  ENV["LATEST_VERSION_#{k.upcase}"] = nil
  Dotenv.load(".env.#{k}")
  source_files = Dir[ File.join("#{v}", '**', '*') ].reject { |p| File.directory? p }
  checksum = Digest::MD5.hexdigest(source_files.map { |file| Digest::MD5.file(file).hexdigest }.join(""))

  begin
    FileUtils.rm("artifacts/#{k}.zip")
  rescue
  end

  ZipFileGenerator.new("#{v}/", "artifacts/#{k}.zip").write()

  unless checksum == ENV["LATEST_VERSION_#{k.upcase}"]
    puts "Uploading file to s3://#{bucket}"
    s3 = Aws::S3::Resource.new
    s3.bucket(bucket).object("#{k}#{checksum}.zip").upload_file("artifacts/#{k}.zip")
    File.write(".env.#{k}", "LATEST_VERSION_#{k.upcase}=#{checksum}\n")
  end
end

# RubyZip creates temp files that it puts into the archive, messing up the
# required permissions. We default to 'zip' here and repeat code :(

source_files = Dir[ File.join("src/cfn2dsl-ruby-lambda", '**', '*') ].reject { |p| File.directory? p }
checksum = Digest::MD5.hexdigest(source_files.map { |file| Digest::MD5.file(file).hexdigest }.join(""))
begin
  FileUtils.rm("artifacts/cfn2dsl.zip")
rescue
  puts "Cannot remove 'artifacts/cfn2dsl.zip'"
end

# Create the cfn2dsl deployment package
puts `cd src/cfn2dsl-ruby-lambda/ && zip -r ../../artifacts/cfn2dsl.zip ./ && cd ../..`

unless checksum == ENV["LATEST_VERSION_CFN2DSL"]
  puts "Uploading cfn2dsl to s3://#{bucket}"
  s3 = Aws::S3::Resource.new
  s3.bucket(bucket).object("cfn2dsl#{checksum}.zip").upload_file("artifacts/cfn2dsl.zip")
  File.write(".env.cfn2dsl", "LATEST_VERSION_CFN2DSL=#{checksum}\n")
end
