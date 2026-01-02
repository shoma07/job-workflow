# Troubleshooting

This section covers common issues encountered during JobFlow operation and their solutions.

## Common Issues

### CircularDependencyError

**Symptom**: Workflow crashes with `JobFlow::CircularDependencyError`

```ruby
# ❌ Circular dependency
task :a, depends_on: [:b] do |ctx|
  # ...
end

task :b, depends_on: [:a] do |ctx|
  # ...
end
```

**Solution**: Review and remove circular dependency

```ruby
# ✅ Correct dependency
task :a do |ctx|
  # ...
end

task :b, depends_on: [:a] do |ctx|
  # ...
end
```

### UnknownTaskError

**Symptom**: `JobFlow::UnknownTaskError: Unknown task: :typo_task`

```ruby
# ❌ Depending on non-existent task
task :process, depends_on: [:typo_task] do |ctx|
  # ...
end
```

**Solution**: Fix task name typo

```ruby
# ✅ Correct task name
task :process, depends_on: [:correct_task] do |ctx|
  # ...
end
```
