# frozen_string_literal: true

require "logger"
require "forwardable"
require "digest"

class Runner
  attr_reader :output

  class Output
    extend Forwardable

    attr_reader :index

    def_delegator :@lines, :any?

    def initialize(lines)
      @lines = lines
      @index = -1
    end

    def next
      @index += 1
      @lines[@index]
    end

    def any?(&block)
      @lines.any?(&block)
    end

    def to_s
      @lines.join
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

  def run(arguments = nil)
    Dir.chdir directory do
      before_setup
      setup_commands.each do |command|
        run_setup command
      end
      after_setup
    end

    # Run the command
    command = [run_command, arguments].compact.join(" ")
    read, write = IO.pipe
    pid = spawn(
      { "APPSIGNAL_PUSH_API_KEY" => "test" },
      command,
      { [:out, :err] => write, :chdir => directory }
    )
    _pid, status = Process.wait2 pid # Wait until command exits
    write.close

    # Collect command output
    output_lines = []
    begin
      while line = read.readline # rubocop:disable Lint/AssignmentInCondition
        output_lines << line
      end
    rescue EOFError
      # Nothing to read anymore. Reached of "file".
    end
    @output = Output.new(output_lines)

    raise CommandFailed.new(command, output.to_s) unless status.success?
  end

  def run_setup(command)
    output = `#{command}`
    raise "Command failed: #{command}\nOutput:\n#{output}" unless Process.last_status.success?
  end

  def readline
    line = @output.next
    if ignored?(line)
      readline
    else
      line
    end
  end

  def ignored?(line)
    ignored_lines.any? do |pattern|
      pattern.match? line
    end
  end

  def logger
    logger = Logger.new($stdout)
    logger.level = ENV["CI"] ? Logger::WARN : Logger::DEBUG
    logger
  end

  def before_setup
    # Placeholder
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

  class Ruby < Runner
    def directory
      File.join(__dir__, "../../ruby")
    end

    def setup_commands
      []
    end

    def run_command
      "echo 'n' | BUNDLE_GEMFILE=#{File.join(__dir__, "../../ruby/Gemfile")} " \
        "bundle exec appsignal diagnose --environment=test"
    end

    def ignored_lines
      [
        /Implementation: ruby/,
        /Flags: {}/,
        /Dependencies: {}/,
        /appsignal: Unable to log to /
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
      # Overwite created install report so we have a consistent test environment
      File.write(File.join(__dir__, "../../../../../ext/install.report"), install_report)
      File.write("/tmp/appsignal.log", appsignal_log)
    end

    def install_report
      <<~REPORT
        ---
        result:
          status: success
        language:
          implementation: ruby
          version: 2.7.0-p83
        download:
          download_url: https://appsignal-agent-releases.global.ssl.fastly.net/20f7d0d/appsignal-x86_64-darwin-all-static.tar.gz
          checksum: verified
        build:
          time: 2020-11-17 14:01:02.281856000 Z
          architecture: x86_64
          target: darwin
          musl_override: false
          linux_arm_override: false
          library_type: static
          dependencies: {}
          source: remote
          flags: {}
        host:
          root_user: false
          dependencies: {}
      REPORT
    end
  end

  class Elixir < Runner
    def directory
      File.join(__dir__, "../../elixir")
    end

    def setup_commands
      ["mix do deps.get, deps.compile, compile"]
    end

    def run_command
      "mix appsignal.diagnose"
    end

    def ignored_lines
      [
        /==> appsignal/,
        /AppSignal extension installation successful/,
        /OTP version: "\d+"/,
        /Download time:/
      ]
    end

    def type
      :elixir
    end

    def language_name
      "Elixir"
    end
  end

  class Nodejs < Runner
    def directory
      File.join(__dir__, "../../nodejs")
    end

    def setup_commands
      [
        "npm install",
        "npm link @appsignal/nodejs @appsignal/nodejs-ext"
      ]
    end

    def run_command
      "echo 'n' | APPSIGNAL_APP_ENV=test node_modules/.bin/appsignal-diagnose"
    end

    def ignored_lines
      [
        %r{WARNING: Error when reading appsignal config, appsignal \(as \d+/\d+\) not starting: Required environment variable '_APPSIGNAL_PUSH_API_KEY' not present}, # rubocop:disable Layout/LineLength
        /Dependencies: {}/
      ]
    end

    def type
      :nodejs
    end

    def language_name
      "Node.js"
    end

    def before_setup
      # Placeholder
    end

    def after_setup
      # Overwite created install report so we have a consistent test environment
      package_path = "#{File.expand_path("../../../../../../", __dir__)}/"
      report_path_digest = Digest::SHA256.hexdigest(package_path)

      File.write("/tmp/appsignal-#{report_path_digest}-install.report", install_report)
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
            "download_url": "https://appsignal-agent-releases.global.ssl.fastly.net/d08ae6c/appsignal-x86_64-darwin-all-static.tar.gz"
          },
          "build": {
            "time": "2021-05-19 15:47:39UTC",
            "architecture": "x64",
            "target": "darwin",
            "musl_override": false,
            "linux_arm_override": false,
            "library_type": "static"
          },
          "host": {
            "root_user": false,
            "dependencies": {}
          }
        }
      REPORT
    end
  end
end
