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
    read, write = IO.pipe
    pid = spawn(
      { "APPSIGNAL_PUSH_API_KEY" => "test" },
      [run_command, arguments].compact.join(" "),
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
      File.join(__dir__, "../ruby")
    end

    def setup_commands
      []
    end

    def run_command
      "echo 'n' | BUNDLE_GEMFILE=#{File.join(__dir__, "../ruby/Gemfile")} " \
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
      File.write(File.join(__dir__, "../../../../ext/install.report"), install_report)
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
      File.join(__dir__, "../elixir")
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
      File.join(__dir__, "../nodejs")
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
      package_path = "#{File.expand_path("../../../../../", __dir__)}/"
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

VERSION_PATTERN = /\d+\.\d+\.\d+(-[a-z0-9]+)?/.freeze
REVISION_PATTERN = /[a-z0-9]{7}/.freeze
ARCH_PATTERN = /(x(86_)?64|i686)/.freeze
TARGET_PATTERN = /(darwin|linux(-musl)?|freebsd)/.freeze
LIBRARY_TYPE_PATTERN = /static|dynamic/.freeze
TAR_FILENAME_PATTERN =
  /appsignal-#{ARCH_PATTERN}-#{TARGET_PATTERN}-all-#{LIBRARY_TYPE_PATTERN}.tar.gz/.freeze
DATETIME_PATTERN = /\d{4}-\d{2}-\d{2}[ |T]\d{2}:\d{2}:\d{2}( ?UTC|.\d+Z)?/.freeze
TRUE_OR_FALSE_PATTERN = /true|false/.freeze
PATH_PATTERN = %r{[/\w.-]+}.freeze
LOG_LINE_PATTERN = /^(#.+|\[#{DATETIME_PATTERN} \(\w+\) \#\d+\]\[\w+\])/.freeze

RSpec.describe "Running the diagnose command without any arguments" do
  before(:all) do
    language = ENV["LANGUAGE"] || "ruby"
    @runner = {
      "ruby" => Runner::Ruby.new,
      "elixir" => Runner::Elixir.new,
      "nodejs" => Runner::Nodejs.new
    }[language]
    @runner.run
  end

  it "prints the diagnose header" do
    expect_output([
      /AppSignal diagnose/,
      /================================================================================/,
      /Use this information to debug your configuration./,
      /More information is available on the documentation site./,
      %r{https://docs.appsignal.com/},
      /Send this output to support@appsignal.com if you need help./,
      /================================================================================/
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the library section" do
    expect_output([
      /AppSignal library/,
      /  Language: #{@runner.language_name}/,
      /  (Gem|Package) version: #{VERSION_PATTERN}/,
      /  Agent version: #{REVISION_PATTERN}/,
      /  (Extension|Nif) loaded: true/
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the extension installation section" do
    expect_output([
      /Extension installation report/,
      /  Installation result/,
      /    Status: success/,
      /  Language details/,
      /    #{@runner.language_name} version: #{VERSION_PATTERN}/,
      /  Download details/,
      %r{    Download URL: https://appsignal-agent-releases.global.ssl.fastly.net/#{REVISION_PATTERN}/#{TAR_FILENAME_PATTERN}},
      /    Checksum: verified/,
      /  Build details/,
      /    Install time: #{DATETIME_PATTERN}/,
      /    Architecture: #{ARCH_PATTERN}/,
      /    Target: #{TARGET_PATTERN}/,
      /    Musl override: #{TRUE_OR_FALSE_PATTERN}/,
      /    Linux ARM override: false/,
      /    Library type: #{LIBRARY_TYPE_PATTERN}/,
      /  Host details/,
      /    Root user: #{TRUE_OR_FALSE_PATTERN}/
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the host information section" do
    expect_output([
      /Host information/,
      /  Architecture: #{ARCH_PATTERN}/,
      /  Operating System: #{TARGET_PATTERN}/,
      /  #{@runner.language_name} version: #{VERSION_PATTERN}/,
      /  Root user: #{TRUE_OR_FALSE_PATTERN}/,
      /  Running in container: #{TRUE_OR_FALSE_PATTERN}/
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the agent diagnostics section" do
    skip if @runner.instance_of?(Runner::Nodejs)

    expect_output([
      /Agent diagnostics/,
      /  Extension tests/,
      /    Configuration: valid/,
      /  Agent tests/,
      /    Started: started/,
      /    Process user id: \d+/,
      /    Process user group id: \d+/,
      /    Configuration: valid/,
      /    Logger: started/,
      /    Working directory user id: \d+/,
      /    Working directory user group id: \d+/,
      /    Working directory permissions: \d+/,
      /    Lock path: writable/
    ])
  end

  it "prints a newline" do
    skip if @runner.instance_of?(Runner::Nodejs)

    expect_newline
  end

  it "prints the configuration section" do
    expect_output([
      /Configuration/,
      /  Environment: #{quoted("test")}/,
      /  debug: false/,
      /  log: #{quoted("file")}/
    ])

    case @runner.type
    when :ruby
      expect_output([
        /  ignore_actions: \[\]/,
        /  ignore_errors: \[\]/,
        /  ignore_namespaces: \[\]/,
        /  filter_parameters: \[\]/,
        /  filter_session_data: \[\]/,
        /  send_environment_metadata: true/,
        /  send_params: true/,
        /  request_headers: \["HTTP_ACCEPT", "HTTP_ACCEPT_CHARSET", "HTTP_ACCEPT_ENCODING", "HTTP_ACCEPT_LANGUAGE", "HTTP_CACHE_CONTROL", "HTTP_CONNECTION", "CONTENT_LENGTH", "PATH_INFO", "HTTP_RANGE", "REQUEST_METHOD", "REQUEST_URI", "SERVER_NAME", "SERVER_PORT", "SERVER_PROTOCOL"\]/, # rubocop:disable Layout/LineLength
        %r{  endpoint: "https://push.appsignal.com"},
        /  instrument_net_http: true/,
        /  instrument_redis: true/,
        /  instrument_sequel: true/,
        /  skip_session_data: false/,
        /  enable_allocation_tracking: true/,
        /  enable_gc_instrumentation: false/,
        /  enable_host_metrics: true/,
        /  enable_minutely_probes: true/,
        /  enable_statsd: true/,
        %r{  ca_file_path: ".+/appsignal-ruby/resources/cacert.pem"},
        /  dns_servers: \[\]/,
        /  files_world_accessible: true/,
        /  transaction_debug_mode: false/,
        /  active: true \(Loaded from: system\)/,
        /  push_api_key: "test" \(Loaded from: env\)/
      ])
    when :nodejs
      expect_output([
        /  endpoint: #{quoted("https://push.appsignal.com")}/,
        /  ca_file_path: #{quoted(".+/cacert.pem")}/,
        /  active: true/,
        /  push_api_key: #{quoted("test")}/
      ])
    else
      raise "No clause for runner #{@runner}"
    end

    expect_newline

    expect_output([
      /Read more about how the diagnose config output is rendered/,
      %(https://docs.appsignal.com/#{@runner.type}/command-line/diagnose.html)
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the validation section" do
    expect_output([%(Validation)])

    expect(@runner.readline).to eq("  Validating Push API key: \e[31minvalid\e[0m\n")
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the paths section" do
    expect_output([%(Paths)])

    if @runner.type == :ruby
      expect_output([
        %(  AppSignal gem path),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: true \(file: \w+:\d+, process: \w+:\d+\)/
      ])
      expect_newline
    end

    expect_output([
      %(  Current working directory),
      /    Path: #{quoted(PATH_PATTERN)}/
    ])

    if @runner.type == :ruby
      expect_output([
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\)/
      ])
    end
    expect_newline

    if @runner.type == :ruby
      expect_output([
        %(  Root path),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\)/
      ])
      expect_newline
    end

    expect_output([
      %(  Log directory),
      /    Path: #{quoted(PATH_PATTERN)}/
    ])

    if @runner.type == :ruby
      expect_output([
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\)/
      ])
    end
    expect_newline

    if @runner.type == :ruby
      expect_output([
        %(  Makefile install log),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Exists\?: #{TRUE_OR_FALSE_PATTERN}/
      ])
    end

    expect_output([
      %(  AppSignal log\n),
      /    Path: #{quoted(PATH_PATTERN)}/
    ])

    if @runner.type == :ruby
      expect_output([
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\)/
      ])
    end

    expect_output([
      /    Contents \(last 10 lines\):/
    ] + Array.new(10).map { LOG_LINE_PATTERN })
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the diagnostics report section" do
    expect_output([
      %(Diagnostics report),
      %(  Do you want to send this diagnostics report to AppSignal?),
      %(  If you share this report you will be given a link to),
      %(  AppSignal.com to validate the report.),
      %(  You can also contact us at support@appsignal.com),
      %(  with your support token.)
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the send-dignostics line" do
    expect_output([
      "  Send diagnostics report to AppSignal? (Y/n):   " \
        "Not sending diagnostics information to AppSignal.\n"
    ])
  end

  def expect_output(expected)
    expected.each do |expected_line|
      line = @runner.readline
      expect(line).to match(expected_line), @runner.output.to_s
    end
  end

  def expect_newline
    expect(@runner.readline).to match(/^\n/), @runner.output.to_s
  end

  def quoted(string)
    quote = "['\"]"
    %(#{quote}#{string}#{quote})
  end
end

RSpec.describe "Running the diagnose command with the --no-send-report option" do
  before do
    language = ENV["LANGUAGE"] || "ruby"
    @runner = {
      "ruby" => Runner::Ruby.new,
      "elixir" => Runner::Elixir.new,
      "nodejs" => Runner::Nodejs.new
    }[language]

    @runner.run("--no-send-report")
  end

  it "does not ask to send the report" do
    expect(
      @runner.output.any? do |line|
        /Send diagnostics report to AppSignal\?/.match? line
      end
    ).to be(false)
  end

  it "does not send the report" do
    expect(
      @runner.output.any? do |line|
        line == %(  Not sending report. (Specified with the --no-send-report option.)\n)
      end
    ).to be(true)
  end
end
