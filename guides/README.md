# JobWorkflow Guides

> ⚠️ **Early Stage (v0.1.2):** JobWorkflow is in active development. APIs and features may change. The following guides provide patterns and examples for building workflows, but be aware that implementations may need adjustment as the library evolves.

Welcome to the JobWorkflow documentation! This directory contains comprehensive guides to help you build robust workflows with JobWorkflow.

## 📚 Documentation Structure

### 🚀 Getting Started

Start here if you're new to JobWorkflow:

- **[GETTING_STARTED.md](GETTING_STARTED.md)** - Quick 5-minute introduction and detailed getting started guide
  - What is JobWorkflow and why use it
  - Installation and setup
  - Your first workflow
  - Core concepts (Workflow, Task, Arguments, Context, Outputs)

### 📖 Fundamentals

Core concepts and features you'll use in every workflow:

- **[DSL_BASICS.md](DSL_BASICS.md)** - Mastering the JobWorkflow DSL
  - Defining tasks
  - Working with arguments
  - Task dependencies
  - Task options (retry, condition, throttle, timeout)

- **[TASK_OUTPUTS.md](TASK_OUTPUTS.md)** - Understanding task outputs
  - Defining and accessing outputs
  - Using outputs with map tasks
  - Output persistence and design patterns

- **[PARALLEL_PROCESSING.md](PARALLEL_PROCESSING.md)** - Efficient parallel execution
  - Collection task basics
  - Fork-Join pattern
  - Controlling concurrency
  - Context isolation

### 🔧 Intermediate

Advanced workflow patterns and features:

- **[ERROR_HANDLING.md](ERROR_HANDLING.md)** - Robust error handling
  - Retry configuration (simple and advanced)
  - Retry strategies (linear, exponential, jitter)
  - Task-level and workflow-level retry settings
  - Combining multiple retry layers

- **[CONDITIONAL_EXECUTION.md](CONDITIONAL_EXECUTION.md)** - Dynamic workflow control
  - Basic conditional execution
  - Complex conditions
  - Best practices

- **[LIFECYCLE_HOOKS.md](LIFECYCLE_HOOKS.md)** - Extending task behavior
  - Hook types (before, after, around, on_error)
  - Hook scope (global vs task-specific)
  - Execution order and error handling

### 🎓 Advanced

Power features for complex workflows:

- **[DEPENDENCY_WAIT.md](DEPENDENCY_WAIT.md)** - Efficient dependency waiting
  - The thread occupation problem
  - Automatic job rescheduling
  - Configuration options (poll_timeout, poll_interval, reschedule_delay)
  - SolidQueue integration

- **[NAMESPACES.md](NAMESPACES.md)** - Organizing large workflows
  - Basic namespace usage
  - Nested namespaces
  - Cross-namespace dependencies

- **[THROTTLING.md](THROTTLING.md)** - Rate limiting and resource control
  - Task-level throttling
  - Runtime throttling
  - Sharing throttle keys across jobs

- **[WORKFLOW_COMPOSITION.md](WORKFLOW_COMPOSITION.md)** - Composing and reusing workflows
  - Invoking child workflows (sync/async)
  - Accessing child workflow outputs
  - Map tasks with child workflows
  - Best practices and limitations

- **[SCHEDULED_JOBS.md](SCHEDULED_JOBS.md)** - Cron-like job scheduling
  - Schedule DSL basics
  - Schedule expressions (cron and natural language)
  - Multiple schedules per job
  - SolidQueue integration

### 📊 Observability

Monitoring and debugging your workflows:

- **[STRUCTURED_LOGGING.md](STRUCTURED_LOGGING.md)** - JSON-based logging
  - Log event types
  - Customizing the logger
  - Querying and analyzing logs

- **[INSTRUMENTATION.md](INSTRUMENTATION.md)** - Event-driven observability
  - Architecture and event types
  - Custom instrumentation
  - Building custom subscribers

- **[OPENTELEMETRY_INTEGRATION.md](OPENTELEMETRY_INTEGRATION.md)** - Distributed tracing
  - Configuration and setup
  - Span attributes and naming
  - Viewing traces in your backend

### 🏭 Practical

Production deployment and operations:

- **[PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md)** - Running JobWorkflow in production
  - SolidQueue configuration
  - Worker optimization
  - Auto-scaling (AWS ECS)
  - SolidCache configuration

- **[QUEUE_MANAGEMENT.md](QUEUE_MANAGEMENT.md)** - Managing job queues
  - Queue operations (status, pause, resume, clear)
  - Finding workflows by queue
  - Production best practices

- **[CACHE_STORE_INTEGRATION.md](CACHE_STORE_INTEGRATION.md)** - Using cache store backends
  - Automatic cache detection (SolidCache, MemoryStore)
  - Cache operations and integration

- **[WORKFLOW_STATUS_QUERY.md](WORKFLOW_STATUS_QUERY.md)** - Monitoring workflow execution
  - Finding and inspecting workflows
  - Accessing arguments, outputs, and job status
  - Building dashboards and APIs

- **[TESTING_STRATEGY.md](TESTING_STRATEGY.md)** - Testing your workflows
  - Unit testing individual tasks
  - Integration testing workflows
  - Test best practices

- **[DRY_RUN.md](DRY_RUN.md)** - Dry-run mode for safe testing
  - Workflow-level and task-level dry-run
  - Dynamic dry-run with Proc
  - skip_in_dry_run for conditional execution
  - Instrumentation and logging

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
  - CircularDependencyError
  - UnknownTaskError
  - Debugging workflows

### 📘 Reference

Complete API documentation and best practices:

- **[API_REFERENCE.md](API_REFERENCE.md)** - Detailed API documentation
  - DSL method reference
  - Class documentation
  - Method signatures

- **[BEST_PRACTICES.md](BEST_PRACTICES.md)** - Design patterns and recommendations
  - Workflow design principles
  - Task granularity
  - Dependency management
  - Testing strategies

---

## 🤝 Contributing

Found an issue or have a suggestion? Please open an issue on the [GitHub repository](https://github.com/shoma07/job-workflow).

## 📄 License

JobWorkflow is released under the MIT License. See LICENSE file for details.
