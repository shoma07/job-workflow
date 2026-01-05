# Testing Strategy

This section covers effective testing methods for workflows built with JobWorkflow.

## Unit Testing

### Testing Individual Tasks

Test each task as a unit.

```ruby
# spec/jobs/user_registration_job_spec.rb
RSpec.describe UserRegistrationJob do
  describe 'task: validate_email' do
    it 'validates correct email format' do
      job = described_class.new
      arguments = JobWorkflow::Arguments.new(email: 'user@example.com')
      ctx = JobWorkflow::Context.new(arguments: arguments)
      
      task = described_class._workflow_tasks[:validate_email]
      expect { job.instance_exec(ctx, &task[:block]) }.not_to raise_error
    end
    
    it 'raises error for invalid email' do
      job = described_class.new
      arguments = JobWorkflow::Arguments.new(email: 'invalid')
      ctx = JobWorkflow::Context.new(arguments: arguments)
      
      task = described_class._workflow_tasks[:validate_email]
      expect { job.instance_exec(ctx, &task[:block]) }.to raise_error(/Invalid email/)
    end
  end
  
  describe 'task: create_user' do
    it 'creates a new user' do
      job = described_class.new
      arguments = JobWorkflow::Arguments.new(
        email: 'user@example.com',
        password: 'password123'
      )
      ctx = JobWorkflow::Context.new(arguments: arguments)
      
      task = described_class._workflow_tasks[:create_user]
      
      expect {
        job.instance_exec(ctx, &task[:block])
      }.to change(User, :count).by(1)
      
      # Verify output
      output = ctx.output[:create_user].first
      expect(output.user).to be_a(User)
      expect(output.user.email).to eq('user@example.com')
    end
  end
end
```
