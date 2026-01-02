# Type Definitions Guide

JobFlow uses rbs-inline to build type-safe workflows.

## rbs-inline Basics

### Three Type Definition Methods

JobFlow uses the following priority for type definitions:

1. **rbs-inline (`: syntax`)** - Highest priority
2. **rbs-inline (`@rbs`)** - When `: syntax` is insufficient
3. **RBS files (`sig/`)** - For complex definitions only

### Using `: syntax`

Specify types in comments before method definitions.

```ruby
class UserService
  # Create a user
  #: (String email, String password) -> User
  def create_user(email, password)
    User.create!(email: email, password: password)
  end
  
  # Find a user
  #: (Integer id) -> User?
  def find_user(id)
    User.find_by(id: id)
  end
  
  # Get user list
  #: (Integer limit) -> Array[User]
  def list_users(limit = 10)
    User.limit(limit).to_a
  end
end
```
