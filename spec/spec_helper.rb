# frozen_string_literal: true

require_relative "support/server"
require_relative "support/runner"
require_relative "support/runner_helper"
require_relative "support/output_helper"
require_relative "support/diagnose_report_helper"

RSpec.configure do |config|
  config.include OutputHelper
  config.include RunnerHelper
  config.include DiagnoseReportHelper

  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.before :suite do
    # Configure integrations to submit their report to a custom server
    port = 4005
    ENV["APPSIGNAL_DIAGNOSE_ENDPOINT"] = "http://localhost:#{port}/diag"
    # Boot mock diagnose report server
    Thread.new { DiagnoseServer.run!(port) }
    # Wait for Sinatra to boot if needed
    sleep 0.01 until DiagnoseServer.running?
  end

  config.after :context do
    DiagnoseServer.clear!
  end

  config.after :suite do
    DiagnoseServer.clear!
    DiagnoseServer.quit!
  end
end
