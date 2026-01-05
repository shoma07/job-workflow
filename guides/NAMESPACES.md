# Namespaces

Logically grouping tasks improves readability and maintainability of complex workflows. JobWorkflow provides namespace functionality.

## Basic Namespaces

### namespace DSL

Group related tasks.

```ruby
class ECommerceOrderJob < ApplicationJob
  include JobWorkflow::DSL
  
  argument :order, "Order"
  
  # Payment-related tasks
  namespace :payment do
    task :validate do |ctx|
      order = ctx.arguments.order
      PaymentValidator.validate(order)
    end
    
    task :charge, depends_on: [:"payment:validate"], output: { payment_result: "Hash" } do |ctx|
      order = ctx.arguments.order
      { payment_result: PaymentProcessor.charge(order) }
    end
    
    task :send_receipt, depends_on: [:"payment:charge"] do |ctx|
      order = ctx.arguments.order
      payment_result = ctx.output[:"payment:charge"].first.payment_result
      ReceiptMailer.send(order, payment_result)
    end
  end
  
  # Inventory-related tasks
  namespace :inventory do
    task :check_availability do |ctx|
      order = ctx.arguments.order
      InventoryService.check(order.items)
    end
    
    task :reserve, depends_on: [:"inventory:check_availability"], output: { reserved: "Boolean" } do |ctx|
      order = ctx.arguments.order
      { reserved: InventoryService.reserve(order.items) }
    end
  end
  
  # Shipping-related tasks
  namespace :shipping do
    task :calculate_cost, output: { shipping_cost: "Float" } do |ctx|
      order = ctx.arguments.order
      { shipping_cost: ShippingCalculator.calculate(order) }
    end
    
    task :create_label, depends_on: [:"shipping:calculate_cost"], output: { shipping_label: "String" } do |ctx|
      order = ctx.arguments.order
      { shipping_label: ShippingService.create_label(order) }
    end
  end
end
```

Tasks in namespaces are identified as `:namespace:task_name` at runtime:

```ruby
# Executed tasks:
# - :payment:validate
# - :payment:charge
# - :payment:send_receipt
# - :inventory:check_availability
# - :inventory:reserve
# - :shipping:calculate_cost
# - :shipping:create_label
```
