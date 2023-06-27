# frozen_string_literal: true

module RunnerHelper
  LANGUAGE_RUNNERS = {
    "ruby" => Runner::Ruby,
    "elixir" => Runner::Elixir,
    "nodejs" => Runner::Nodejs,
    "python" => Runner::Python
  }.freeze

  def init_runner(options = {})
    language = ENV.fetch("LANGUAGE") { raise "No LANGUAGE environment variable is configured" }
    runner_class = LANGUAGE_RUNNERS.fetch(language) do
      raise "No runner found for language: `#{language}`"
    end
    runner_class.new(options)
  end
end
