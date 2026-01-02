# Conditional Execution

JobFlow provides conditional execution features to selectively execute tasks based on runtime state.

## Basic Conditional Execution

### condition: Option

Execute task only if condition returns true.

```ruby
class UserNotificationJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user, "User"
  argument :notification_type, "String"
  
  task :load_user_preferences, output: { preferences: "Hash" } do |ctx|
    user = ctx.arguments.user
    { preferences: user.notification_preferences }
  end
  
  # Execute only for premium users
  task :send_premium_notification,
       depends_on: [:load_user_preferences],
       condition: ->(ctx) { ctx.arguments.user.premium? } do |ctx|
    user = ctx.arguments.user
    notification_type = ctx.arguments.notification_type
    PremiumNotificationService.send(user, notification_type)
  end
  
  # Send simple notification to standard users
  task :send_standard_notification,
       depends_on: [:load_user_preferences],
       condition: ->(ctx) { !ctx.arguments.user.premium? } do |ctx|
    user = ctx.arguments.user
    notification_type = ctx.arguments.notification_type
    StandardNotificationService.send(user, notification_type)
  end
end
```

## Complex Conditions

You can use any Ruby expression in the condition lambda.

```ruby
class DataSyncJob < ApplicationJob
  include JobFlow::DSL
  
  argument :force_sync, "TrueClass | FalseClass", default: false
  argument :last_sync_at, "Time", default: nil
  
  # Execute only if more than 1 hour since last sync
  task :sync_data,
       condition: ->(ctx) { 
         return true if ctx.arguments.force_sync  # Always execute if force_sync is true
         last_sync = ctx.arguments.last_sync_at
         !last_sync || last_sync <= 1.hour.ago
       },
       output: { sync_time: "Time" } do |ctx|
    SyncService.perform
    { sync_time: Time.current }
  end
end
```
