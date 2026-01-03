# Cache Store Integration Guide

JobFlow is designed to use `ActiveSupport::Cache::Store` compatible backends. Currently, the cache store infrastructure is in place, but no features are actively using the cache yet. This guide documents the cache store abstraction layer and its planned usage patterns.

**Status**: Cache store detection and initialization are implemented. Feature implementations that utilize the cache (Workflow status persistence, Output storage, etc.) are planned for future releases.

## Overview

`JobFlow::CacheStoreAdapters` provides automatic cache store detection and a unified access interface. This allows JobFlow to transparently use available cache backends like SolidCache or memory-based caches.

## Automatic Detection

`JobFlow::CacheStoreAdapters.current` automatically detects and instantiates an appropriate cache store with the following priority:

1. **SolidCache**: If `ActiveSupport::Cache::SolidCacheStore` is defined, a new instance is created with JobFlow's namespace configuration
2. **Memory Store**: If neither is available, `ActiveSupport::Cache::MemoryStore` is used as the default fallback

All stores are automatically namespaced with `"job_flow"` to prevent key collisions with application-level caches.

### Example

```ruby
# Access the auto-detected cache store
cache = JobFlow::CacheStoreAdapters.current

# Write to cache
cache.write("my_key", { data: "value" }, expires_in: 24.hours)

# Read from cache
data = cache.read("my_key")

# Delete from cache
cache.delete("my_key")
```

## Supported Cache Backends

### SolidCache (Recommended for Rails 8+)

SolidCache is a database-backed cache store recommended for Rails 8 applications. JobFlow automatically uses SolidCache if available.

For detailed SolidCache setup instructions, see the [official SolidCache documentation](https://github.com/rails/solid_cache).

### Memory Store (Default)

In environments where SolidCache is not available (development, tests, or minimal deployments), JobFlow uses `ActiveSupport::Cache::MemoryStore`:

```ruby
ActiveSupport::Cache::MemoryStore.new
```

## Design Decision: No Direct Rails.cache Usage

JobFlow does NOT use `Rails.cache` directly. Instead, it creates dedicated cache store instances. This design choice provides:

- **Namespace Isolation**: JobFlow caches are namespaced with `"job_flow"` prefix to prevent key collisions with application-level caches
- **Explicit Configuration**: JobFlow's cache is independently configurable without affecting Rails application caching
- **Predictable Behavior**: No cache invalidations triggered by Rails application code

This ensures that JobFlow's internal caching behavior is isolated and predictable, even in complex Rails applications with sophisticated caching strategies.

## Test Environment

In test environments, JobFlow automatically uses `MemoryStore`. You can reset the cache between tests:

```ruby
# spec/spec_helper.rb is pre-configured with:
config.after do
  JobFlow::CacheStoreAdapters.reset!
end
```

To manually clear cache in tests:

```ruby
RSpec.configure do |config|
  config.before(:each) do
    JobFlow::CacheStoreAdapters.current.clear if JobFlow::CacheStoreAdapters.current.respond_to?(:clear)
  end
end
```

## Cache Key Format

JobFlow generates cache keys with the following format:

```
job_flow:<feature>:<workflow_id>:<identifier>
```

Examples:
- `job_flow:task_output:wf-123:task-1`
- `job_flow:dependency_wait:wf-456:dep-xyz`
- `job_flow:semaphore:wf-789:sem-lock`

## Performance Considerations

### Latency by Backend

| Backend | Read/Write Latency |
|---------|-------------------|
| MemoryStore | < 1ms |
| SolidCache (Database) | 5-50ms |
| Redis | 1-10ms |
| Memcached | 1-5ms |
## Troubleshooting

### Verify Current Cache Backend

```ruby
# Check which cache store is being used
puts JobFlow::CacheStoreAdapters.current.class
# => ActiveSupport::Cache::SolidCacheStore or ActiveSupport::Cache::MemoryStore
```

### Clear Cache

```ruby
# Clear all JobFlow caches
if JobFlow::CacheStoreAdapters.current.respond_to?(:clear)
  JobFlow::CacheStoreAdapters.current.clear
end
```

### Reset to Default Configuration

```ruby
# Reset to auto-detected cache store
JobFlow::CacheStoreAdapters.reset!
```

## Best Practices

1. **Production**: Use SolidCache for database-backed persistence
2. **Development**: Default MemoryStore is sufficient
3. **Testing**: MemoryStore is automatically used and cleared between tests
4. **Large Workflows**: Monitor cache size and choose appropriate backend (SolidCache for unlimited, MemoryStore for bounded)

## Out of Scope

The following are not supported or are intentionally excluded:

- Custom adapter implementations by users
- Automatic cache key prefixing (beyond JobFlow's internal namespace)
- AWS S3 or other external storage backends (planned for future LargeStorageAdapters)
