# frozen_string_literal: true

require "logger"
require "forwardable"
require "digest"
require "fileutils"
require "json"

class Runner
  attr_reader :output

  class Output
    attr_reader :index

    def initialize(lines, ignore: [])
      @lines = lines
      @ignored_lines = ignore
    end

    def sections
      @sections ||= parse_output
    end

    def section(key)
      raise "No section for `#{key}` found!\nOutput: #{self}" unless sections.key?(key)

      sections[key].join("\n")
    end

    def to_s
      @lines.join("\n")
    end

    private

    SECTIONS = {
      "AppSignal diagnose" => :header,
      "AppSignal library" => :library,
      "Extension installation report" => :installation,
      "Host information" => :host,
      "Agent diagnostics" => :agent,
      "Configuration" => :config,
      "Validation" => :validation,
      "Paths" => :paths,
      "Diagnostics report" => :send_report
    }.freeze

    def parse_output
      sections = Hash.new { |hash, key| hash[key] = [] }
      section_index = :other
      section_headings = SECTIONS.keys
      @lines.each do |line|
        next if ignored?(line)

        section_index = SECTIONS[line] if section_headings.include?(line)

        current_section = sections[section_index]
        current_section << line
      end
      sections
    end

    def ignored?(line)
      @ignored_lines.any? do |pattern|
        pattern.match? line
      end
    end
  end

  class CommandFailed < StandardError
    def initialize(command, output)
      @command = command
      @output = output
      super()
    end

    def message
      "The command has failed to run: #{@command}\nOutput:\n#{@output}"
    end
  end

  def initialize(options = {})
    @prompt = options.delete(:prompt)
    @arguments = options.delete(:args) { [] }
    @options = options
    @push_api_key = options.fetch(:push_api_key, "test")
  end

  def install_report?
    @options.fetch(:install_report, true)
  end

  def run_env
    {
      "APPSIGNAL_PUSH_API_KEY" => @push_api_key,
      "APPSIGNAL_PUSH_API_ENDPOINT" => ENV["APPSIGNAL_PUSH_API_ENDPOINT"],
      "APPSIGNAL_DIAGNOSE_ENDPOINT" => ENV["APPSIGNAL_DIAGNOSE_ENDPOINT"]
    }
  end

  def run_command(_arguments)
    raise NotImplementedError, "`Runner` subclasses must implement `run_command`"
  end

  def run # rubocop:disable Metrics/MethodLength
    Bundler.with_unbundled_env do
      Dir.chdir directory do
        before_setup
        setup_commands.each do |command|
          run_setup command
        end
        after_setup
      end
    end

    # Run the command
    prompt = @prompt ? %(echo "#{@prompt}" | ) : ""
    command = run_command(@arguments.dup)
    read, write = IO.pipe
    env = run_env
    pid =
      Bundler.with_unbundled_env do
        spawn(
          env,
          "#{prompt} #{command}",
          { [:out, :err] => write, :chdir => directory }
        )
      end
    _pid, status = Process.wait2 pid # Wait until command exits
    write.close

    # Collect command output
    output_lines = []
    begin
      while line = read.readline # rubocop:disable Lint/AssignmentInCondition
        output_lines << line.rstrip
      end
    rescue EOFError
      # Nothing to read anymore. Reached end of "file".
    end
    @output = Output.new(output_lines, :ignore => ignored_lines)

    raise CommandFailed.new(command, output.to_s) unless status.success?
  end

  def run_setup(command)
    output = `#{command}`
    raise "Command failed: #{command}\nOutput:\n#{output}" unless Process.last_status.success?
  end

  def logger
    logger = Logger.new($stdout)
    logger.level = ENV["CI"] ? Logger::WARN : Logger::DEBUG
    logger
  end

  def before_setup
    # Placeholder
  end

  def setup_commands
    []
  end

  def after_setup
    # Placeholder
  end

  def appsignal_log
    [ # rubocop:disable Style/StringConcatenation
      "# Logfile created on 2021-06-14 13:44:22 +0200 by logger.rb/v1.4.2",
      "[2021-06-14T13:44:22 (process) #49713][INFO] Starting AppSignal diagnose",
      "[2021-06-14T13:50:02 (process) #51074][INFO] Starting AppSignal diagnose",
      "[2021-06-14T13:51:54 (process) #51823][INFO] Starting AppSignal diagnose",
      "[2021-06-14T13:52:07 (process) #52200][INFO] Starting AppSignal diagnose",
      "[2021-06-14T13:53:03 (process) #52625][INFO] Starting AppSignal diagnose",
      "[2021-06-14T13:55:20 (process) #53396][INFO] Starting AppSignal diagnose",
      "[2021-06-14T13:59:10 (process) #53880][INFO] Starting AppSignal diagnose",
      "[2021-06-14T14:05:53 (process) #54792][INFO] Starting AppSignal diagnose",
      "[2021-06-14T14:11:37 (process) #55323][INFO] Starting AppSignal diagnose"
    ].join("\n") + "\n"
  end

  def project_path
    File.expand_path("../../", __dir__)
  end

  def integration_path
    integration_path_env = "#{type.to_s.upcase}_INTEGRATION_PATH"
    path = ENV.fetch(integration_path_env, "../../../")

    if File.absolute_path?(path)
      path
    else
      File.expand_path(path, project_path)
    end
  end

  class Ruby < Runner
    def directory
      File.join(project_path, "ruby")
    end

    def setup_commands
      [
        "bundle config set --local gemfile #{directory}/Gemfile",
        "bundle install"
      ]
    end

    def run_env
      super.merge({
        "BUNDLE_GEMFILE" => File.join(directory, "Gemfile")
      })
    end

    def run_command(arguments)
      arguments << "--environment=development"

      "bundle exec appsignal diagnose #{arguments.join(" ")}"
    end

    def ignored_lines
      [
        /appsignal: Unable to log to /,
        /Calling `DidYouMean::SPELL_CHECKERS/
      ]
    end

    def type
      :ruby
    end

    def language_name
      "Ruby"
    end

    def before_setup
      # Placeholder
    end

    def after_setup
      install_report_path = File.expand_path("ext/install.report", integration_path)
      if install_report?
        # Overwite created install report so we have a consistent test environment
        File.write(install_report_path, install_report)
      elsif File.exist?(install_report_path)
        File.delete(install_report_path)
      end
      File.write("/tmp/appsignal.log", appsignal_log)
    end

    def install_report
      <<~REPORT
        {
          "result": {
            "status": "success"
          },
          "language": {
            "name": "ruby",
            "implementation": "ruby",
            "version": "2.7.0-p83"
          },
          "download": {
            "download_url": "https://appsignal-agent-releases.global.ssl.fastly.net/0.0.1/appsignal-x86_64-darwin-all-static.tar.gz",
            "checksum": "verified"
          },
          "build": {
            "time": "2020-11-17 14:01:02 UTC",
            "architecture": "x86_64",
            "target": "darwin",
            "musl_override": false,
            "linux_arm_override": false,
            "library_type": "static",
            "dependencies": {
            },
            "source": "remote",
            "flags": {
            }
          },
          "host": {
            "root_user": false,
            "dependencies": {
            }
          }
        }
      REPORT
    end
  end

  class Elixir < Runner
    def directory
      File.join(project_path, "elixir")
    end

    def setup_commands
      [
        "mix deps.get",
        "mix release --overwrite"
      ]
    end

    def run_command(arguments)
      arguments = arguments.map { |a| %("#{a}") }.join(" ")
      "_build/dev/rel/elixir_diagnose/bin/elixir_diagnose " \
        "eval ':appsignal_tasks.diagnose([#{arguments}])'"
    end

    def ignored_lines
      [
        /==> appsignal/,
        /AppSignal extension installation successful/,
        /Download time:/
      ]
    end

    def type
      :elixir
    end

    def language_name
      "Elixir"
    end

    def before_setup
      # Delete previous versions of the AppSignal package so it doesn't get
      # confused later on, in which package to stub the install and download
      # reports
      package_dirs = Dir.glob(
        "_build/dev/rel/elixir_diagnose/lib/appsignal-*.*.*/",
        :base => directory
      )
      package_dirs.each do |dir|
        FileUtils.rm_rf(dir)
      end
    end

    def after_setup
      priv_dir = Dir.glob(
        "_build/dev/rel/elixir_diagnose/lib/appsignal-*.*.*/priv/",
        :base => directory
      ).first
      raise "No Elixir package priv dir found!" unless priv_dir

      download_report_path = File.join(priv_dir, "download.report")
      install_report_path = File.join(priv_dir, "install.report")
      if install_report?
        # Overwite created install report so we have a consistent test environment
        File.write(download_report_path, download_report)
        File.write(install_report_path, install_report)
      else
        FileUtils.rm_f(download_report_path)
        FileUtils.rm_f(install_report_path)
      end

      File.write("/tmp/appsignal.log", appsignal_log)
    end

    def download_report
      <<~REPORT
        {
          "download": {
            "architecture": "x86_64",
            "checksum": "verified",
            "download_url": "https://appsignal-agent-releases.global.ssl.fastly.net/0.0.1/appsignal-x86_64-darwin-all-static.tar.gz",
            "library_type": "static",
            "linux_arm_override": false,
            "musl_override": false,
            "target": "darwin",
            "time": "2021-10-19T08:35:03.854017Z"
          }
        }
      REPORT
    end

    def install_report
      <<~REPORT
        {
          "build": {
            "agent_version": "0.0.1",
            "architecture": "x86_64",
            "library_type": "static",
            "linux_arm_override": false,
            "musl_override": false,
            "package_path": "/appsignal-elixir/_build/dev/lib/appsignal/priv",
            "source": "remote",
            "target": "darwin",
            "time": "2021-10-19T08:35:03.854017Z",
            "dependencies": {},
            "flags": {}
          },
          "download": {
            "checksum": "verified",
            "download_url": "https://appsignal-agent-releases.global.ssl.fastly.net/0.0.1/appsignal-x86_64-darwin-all-static.tar.gz"
          },
          "host": {
            "dependencies": {},
            "root_user": false
          },
          "language": {
            "name": "elixir",
            "otp_version": "23",
            "version": "1.11.3"
          },
          "result": {
            "status": "success"
          }
        }
      REPORT
    end
  end

  class Nodejs < Runner
    def directory
      File.join(project_path, "nodejs")
    end

    def setup_commands
      ["npm link #{integration_path}"]
    end

    def run_env
      super.merge({
        "NODE_ENV" => "development",
        "APPSIGNAL_ENABLE_MINUTELY_PROBES" => "false",
        "APPSIGNAL_APP_NAME" => "DiagnoseTests",
        "APPSIGNAL_DIAGNOSE" => "true"
      })
    end

    def run_command(arguments)
      "node_modules/.bin/appsignal-diagnose #{arguments.join(" ")}"
    end

    def ignored_lines
      [
        %r{WARNING: Error when reading appsignal config, appsignal \(as \d+/\d+\) not starting: Required environment variable '_APPSIGNAL_PUSH_API_KEY' not present} # rubocop:disable Layout/LineLength
      ]
    end

    def type
      :nodejs
    end

    def language_name
      "Node.js"
    end

    def before_setup
      # Remove `package-lock.json` and `node_modules`, which may point or
      # symlink to the wrong directories
      FileUtils.rm_f(File.join(directory, "package-lock.json"))
      FileUtils.rm_rf(File.join(directory, "node_modules"), :secure => true)
    end

    def after_setup
      install_report_path = File.join(integration_path, "ext/install.report")
      if install_report?
        File.write(install_report_path, install_report)
      elsif File.exist?(install_report_path)
        File.delete(install_report_path)
      end
      File.write("/tmp/appsignal.log", appsignal_log)
    end

    def install_report
      <<~REPORT
        {
          "result": {
            "status": "success"
          },
          "language": {
            "name": "nodejs",
            "version": "16.4.0",
            "implementation": "nodejs"
          },
          "download": {
            "checksum": "verified",
            "download_url": "https://appsignal-agent-releases.global.ssl.fastly.net/0.0.1/appsignal-x86_64-darwin-all-static.tar.gz"
          },
          "build": {
            "time": "2021-05-19 15:47:39UTC",
            "architecture": "x64",
            "target": "darwin",
            "musl_override": false,
            "linux_arm_override": false,
            "library_type": "static",
            "flags": {},
            "dependencies": {},
            "source": "remote"
          },
          "host": {
            "root_user": false,
            "dependencies": {}
          }
        }
      REPORT
    end
  end

  class Python < Runner
    def directory
      File.join(project_path, "python")
    end

    def run_env
      super.merge({
        "APPSIGNAL_APP_NAME" => "DiagnoseTests",
        "APPSIGNAL_APP_ENV" => "development",
        "APPSIGNAL_ENABLE_MINUTELY_PROBES" => "false"
      })
    end

    def run_command(arguments)
      "hatch run appsignal diagnose #{arguments.join(" ")}"
    end

    def ignored_lines
      [
        /Creating environment: default/,
        /Installing project in development mode/,
        /Checking dependencies/,
        /Syncing dependencies/,
        /DEPRECATION: --no-python-version-warning is deprecated/
      ]
    end

    def type
      :python
    end

    def after_setup
      File.write("/tmp/appsignal.log", appsignal_log)
    end

    def language_name
      "Python"
    end
  end
end
