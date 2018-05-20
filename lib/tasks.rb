require "aws-sdk"

Aws.config.update({
  region: ENV["AWS_REGION"],
  credentials: Aws::Credentials.new(
    ENV["AWS_ACCESS_KEY_ID"], ENV["AWS_SECRET_ACCESS_KEY"]
  )
})

def stack_exists(stack_name)
  cfn = Aws::CloudFormation::Client.new
  begin
    cfn.describe_stacks(
        stack_name: stack_name
    )
    true
  rescue
    false
  end
end

def create_stack(template, stack_name, deploy = true, timeout = 60)
  File.write("build/#{stack_name}.json", template)
  return unless deploy

  cfn = Aws::CloudFormation::Client.new

  created = false
  begin
    stacks = cfn.describe_stacks(
      stack_name: stack_name
    )
    status = stacks.stacks[0].stack_status
    created = true if status =~ /_COMPLETE/
  rescue => exception
    puts exception.inspect
  end

  created ||= false

  case created
  when true
    begin
      puts "Updating stack #{stack_name}..."
      cfn.update_stack(
        stack_name: stack_name,
        template_body: template,
        capabilities: %w(CAPABILITY_IAM CAPABILITY_NAMED_IAM)
      )
    rescue => exception
      puts "#{stack_name}: #{exception}"
      return
    end
  when false
    puts "Creating stack #{stack_name}..."
    cfn.create_stack(
      stack_name: stack_name,
      template_body: template,
      timeout_in_minutes: timeout,
      capabilities: %w(CAPABILITY_IAM CAPABILITY_NAMED_IAM),
      on_failure: "DO_NOTHING"
    )
  end

  loop do
    begin
      stacks = cfn.describe_stacks(
        stack_name: stack_name
      )
      status = stacks.stacks[0].stack_status
    rescue
      status = "WAITING_FOR_AWS"
    end
    puts "- #{status}"
    puts "* CREATE_COMPLETE" if status == "CREATE_COMPLETE"
    break if %w(
      CREATE_FAILED
      CREATE_COMPLETE
      ROLLBACK_COMPLETE
      DELETE_FAILED
      DELETE_COMPLETE
      UPDATE_COMPLETE
      UPDATE_ROLLBACK_FAILED
      UPDATE_ROLLBACK_COMPLETE
    ).include? status
    sleep(10)
  end
end
