# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

# Load support files
Rails.root.glob("spec/support/**/*.rb").each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]

  # Disable transactional fixtures globally for job tests
  # External SolidQueue workers cannot see uncommitted transactions
  config.use_transactional_fixtures = false

  config.filter_rails_from_backtrace!

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Clean up databases after each test
  config.after do
    # Clean SolidQueue tables
    SolidQueueHelper.clean_database if defined?(SolidQueueHelper)
  end
end
