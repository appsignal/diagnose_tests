require 'logger'
require 'timeout'

class Runner
  include Enumerable

  def initialize
    @read, @write = IO.pipe
  end

  def run(arguments = nil)
    Dir.chdir(directory)
    `#{setup_command}`
    @pid = spawn({"APPSIGNAL_PUSH_API_KEY" => "test"}, [run_command, arguments].compact.join(" "), out: @write)
  end

  def readline
    line = Timeout::timeout(1) { @read.readline }

    logger.debug(line)

    if ignored?(line)
      readline
    else
      line
    end
  end

  def each(&block)
    begin
      block.call(readline)
    rescue Timeout::Error
    else
      each(&block)
    end
  end

  def ignored?(line)
    ignored_lines.any? do |pattern|
      pattern.match? line
    end
  end

  def stop
    Process.kill(3, @pid)
  end

  def logger
    Logger.new(STDOUT)
  end

  def prepare
  end

  def appsignal_log
    <<~LOG
    # Logfile created on 2021-06-14 13:44:22 +0200 by logger.rb/v1.4.2
    [2021-06-14T13:44:22 (process) #49713][INFO] Starting AppSignal diagnose
    [2021-06-14T13:50:02 (process) #51074][INFO] Starting AppSignal diagnose
    [2021-06-14T13:51:54 (process) #51823][INFO] Starting AppSignal diagnose
    [2021-06-14T13:52:07 (process) #52200][INFO] Starting AppSignal diagnose
    [2021-06-14T13:53:03 (process) #52625][INFO] Starting AppSignal diagnose
    [2021-06-14T13:55:20 (process) #53396][INFO] Starting AppSignal diagnose
    [2021-06-14T13:59:10 (process) #53880][INFO] Starting AppSignal diagnose
    [2021-06-14T14:05:53 (process) #54792][INFO] Starting AppSignal diagnose
    [2021-06-14T14:11:37 (process) #55323][INFO] Starting AppSignal diagnose
    LOG
  end
end

class Runner::Ruby < Runner
  def directory
    File.join(__dir__, "../ruby")
  end

  def setup_command
    ":"
  end

  def run_command
    "echo 'n' | BUNDLE_GEMFILE=#{File.join(__dir__, "../ruby/Gemfile")} bundle exec appsignal diagnose --environment=test"
  end

  def ignored_lines
    [
      %r(Implementation: ruby),
      %r(Flags: {}),
      %r(Dependencies: {}),
      %r(appsignal: Unable to log to )
    ]
  end

  def type
    :ruby
  end

  def language_name
    'Ruby'
  end

  def prepare
    File.write(File.join(__dir__, "../../../../ext/install.report"), install_report)
    File.write("/tmp/appsignal.log", appsignal_log)
  end

  def install_report
    %(---
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
      dependencies: {})
  end
end

class Runner::Elixir < Runner
  def directory
    File.join(__dir__, "../elixir")
  end

  def setup_command
    "mix do deps.get, deps.compile, compile"
  end

  def run_command
    "mix appsignal.diagnose"
  end

  def ignored_lines
    [
      %r(==> appsignal),
      %r(AppSignal extension installation successful),
      %r(OTP version: \"\d+\"),
      %r(Download time:),
    ]
  end

  def type
    :elixir
  end

  def language_name
    'Elixir'
  end
end

class Runner::Nodejs < Runner
  def directory
    File.join(__dir__, "../nodejs")
  end

  def setup_command
    "npm install"
  end

  def run_command
    "echo 'n' | APPSIGNAL_APP_ENV=test ../../../../packages/nodejs/bin/diagnose"
  end

  def ignored_lines
    [
      %r(WARNING: Error when reading appsignal config, appsignal \(as \d+/\d+\) not starting: Required environment variable '_APPSIGNAL_PUSH_API_KEY' not present),
      %r(Dependencies: {})
    ]
  end

  def type
    :nodejs
  end

  def language_name
    'Node.js'
  end

  def prepare
    File.write("/tmp/appsignal-install-report.json", install_report)
    File.write("/tmp/appsignal.log", appsignal_log)
  end

  def install_report
    %{{
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
    }}
  end
end

RSpec.describe "Running the diagnose command without any arguments" do
  before(:all) do
    language = ENV['LANGUAGE'] || 'ruby'
    @runner = {
      'ruby' => Runner::Ruby.new(),
      'elixir' => Runner::Elixir.new(),
      'nodejs' => Runner::Nodejs.new()
    }[language]

    @runner.prepare()
    @runner.run()
  end

  it "prints the diagnose header" do
    expect_output([
      %r(AppSignal diagnose),
      %r(================================================================================),
      %r(Use this information to debug your configuration.),
      %r(More information is available on the documentation site.),
      %r(https://docs.appsignal.com/),
      %r(Send this output to support@appsignal.com if you need help.),
      %r(================================================================================)
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the library section" do
    expect_output([
      %r(AppSignal library),
      %r(  Language: #{@runner.language_name}),
      %r(  (Gem|Package) version: #{VERSION_PATTERN}),
      %r(  Agent version: #{REVISION_PATTERN}),
      %r(  (Extension|Nif) loaded: true)
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the extension installation section" do
    expect_output([
      %r(Extension installation report),
      %r(  Installation result),
      %r(    Status: success),
      %r(  Language details),
      %r(    #{@runner.language_name} version: #{VERSION_PATTERN}),
      %r(  Download details),
      %r(    Download URL: https://appsignal-agent-releases.global.ssl.fastly.net/#{REVISION_PATTERN}/#{TAR_FILENAME_PATTERN}),
      %r(    Checksum: verified),
      %r(  Build details),
      %r(    Install time: #{DATETIME_PATTERN}),
      %r(    Architecture: #{ARCH_PATTERN}),
      %r(    Target: #{TARGET_PATTERN}),
      %r(    Musl override: #{TRUE_OR_FALSE_PATTERN}),
      %r(    Linux ARM override: false),
      %r(    Library type: #{LIBRARY_TYPE_PATTERN}),
      %r(  Host details),
      %r(    Root user: #{TRUE_OR_FALSE_PATTERN}),
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the host information section" do
    expect_output([
      %r(Host information),
      %r(  Architecture: #{ARCH_PATTERN}),
      %r(  Operating System: #{TARGET_PATTERN}),
      %r(  #{@runner.language_name} version: #{VERSION_PATTERN}),
      %r(  Root user: #{TRUE_OR_FALSE_PATTERN}),
      %r(  Running in container: #{TRUE_OR_FALSE_PATTERN}),
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the agent diagnostics section" do
    skip if @runner.class == Runner::Nodejs

    expect_output([
      %r(Agent diagnostics),
      %r(  Extension tests),
      %r(    Configuration: valid),
      %r(  Agent tests),
      %r(    Started: started),
      %r(    Process user id: \d+),
      %r(    Process user group id: \d+),
      %r(    Configuration: valid),
      %r(    Logger: started),
      %r(    Working directory user id: \d+),
      %r(    Working directory user group id: \d+),
      %r(    Working directory permissions: \d+),
      %r(    Lock path: writable)
    ])
  end

  it "prints a newline" do
    skip if @runner.class == Runner::Nodejs

    expect_newline
  end

  it "prints the configuration section" do
    expect_output([
      %r(Configuration),
      %r(  Environment: #{quoted("test")}),
      %r(  debug: false),
      %r(  log: #{quoted("file")}),
    ])

    case @runner.type
    when :ruby
      expect_output([
        %r(  ignore_actions: \[\]),
        %r(  ignore_errors: \[\]),
        %r(  ignore_namespaces: \[\]),
        %r(  filter_parameters: \[\]),
        %r(  filter_session_data: \[\]),
        %r(  send_environment_metadata: true),
        %r(  send_params: true),
        %r(  request_headers: \["HTTP_ACCEPT", "HTTP_ACCEPT_CHARSET", "HTTP_ACCEPT_ENCODING", "HTTP_ACCEPT_LANGUAGE", "HTTP_CACHE_CONTROL", "HTTP_CONNECTION", "CONTENT_LENGTH", "PATH_INFO", "HTTP_RANGE", "REQUEST_METHOD", "REQUEST_URI", "SERVER_NAME", "SERVER_PORT", "SERVER_PROTOCOL"\]),
        %r(  endpoint: "https://push.appsignal.com"),
        %r(  instrument_net_http: true),
        %r(  instrument_redis: true),
        %r(  instrument_sequel: true),
        %r(  skip_session_data: false),
        %r(  enable_allocation_tracking: true),
        %r(  enable_gc_instrumentation: false),
        %r(  enable_host_metrics: true),
        %r(  enable_minutely_probes: true),
        %r(  ca_file_path: ".+\/appsignal-ruby\/resources\/cacert.pem"),
        %r(  dns_servers: \[\]),
        %r(  files_world_accessible: true),
        %r(  transaction_debug_mode: false),
        %r(  active: true \(Loaded from: system\)),
        %r(  push_api_key: "test" \(Loaded from: env\))
      ])
    when :nodejs
      expect_output([
        %r(  log_path: #{quoted("/tmp")}),
        %r(  ca_file_path: #{quoted(".+/cacert.pem")}),
        %r(  endpoint: #{quoted("https://push.appsignal.com")}),
        %r(  push_api_key: #{quoted("test")}),
        %r(  active: true),
        %r(  log_file_path: #{quoted("/tmp/appsignal.log")})
      ])
    else
      raise "No clause for runner #{@runner}"
    end

    expect_newline

    expect_output([
      %r(Read more about how the diagnose config output is rendered),
      %(https://docs.appsignal.com/#{@runner.type}/command-line/diagnose.html)
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the validation section" do
    expect_output([%(Validation)])

    case @runner.type
    when :ruby
      expect(@runner.readline).to eq("  Validating Push API key: \e[31minvalid\e[0m\n")
    when :nodejs
      expect(@runner.readline).to eq("  Validating Push API key: \e[32mvalid\e[0m\n")
    end
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the paths section" do
    expect_output([%(Paths)])

    if @runner.type == :ruby
      expect_output([
        %(  AppSignal gem path),
        %r(    Path: #{quoted(PATH_PATTERN)}),
        %r(    Writable\?: #{TRUE_OR_FALSE_PATTERN}),
        %r(    Ownership\?: true \(file: \w+:\d+, process: \w+:\d+\))
      ])
      expect_newline
    end

    expect_output([
      %(  Current working directory),
      %r(    Path: #{quoted(PATH_PATTERN)}),
    ])

    if @runner.type == :ruby
      expect_output([
        %r(    Writable\?: #{TRUE_OR_FALSE_PATTERN}),
        %r(    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\))
      ])
    end
    expect_newline

    if @runner.type == :ruby
      expect_output([
        %(  Root path),
        %r(    Path: #{quoted(PATH_PATTERN)}),
        %r(    Writable\?: #{TRUE_OR_FALSE_PATTERN}),
        %r(    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\))
      ])
      expect_newline
    end

    expect_output([
      %(  Log directory),
      %r(    Path: #{quoted(PATH_PATTERN)}),
    ])

    if @runner.type == :ruby
      expect_output([
        %r(    Writable\?: #{TRUE_OR_FALSE_PATTERN}),
        %r(    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\))
      ])
    end
    expect_newline

    if @runner.type == :ruby
      expect_output([
        %(  Makefile install log),
        %r(    Path: #{quoted(PATH_PATTERN)}),
        %r(    Exists\?: #{TRUE_OR_FALSE_PATTERN}),
      ])
    end

    expect_output([
      %(  AppSignal log\n),
      %r(    Path: #{quoted(PATH_PATTERN)}),
    ])

    if @runner.type == :ruby
      expect_output([
        %r(    Writable\?: #{TRUE_OR_FALSE_PATTERN}),
        %r(    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: \w+:\d+, process: \w+:\d+\)),
      ])
    end

    case @runner.type
    when :ruby
      expect_output([
        %r(    Contents \(last 10 lines\):),
      ] + 10.times.map { LOG_LINE_PATTERN })
    when :nodejs
      expect_output([
        %r(    Contents \(last 9 lines\):),
      ] + 9.times.map { LOG_LINE_PATTERN })
    end
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
      %(  with your support token.),
    ])
  end

  it "prints a newline" do
    expect_newline
  end

  it "prints the send-dignostics line" do
    expect_output([
      %(  Send diagnostics report to AppSignal? (Y/n):   Not sending diagnostics information to AppSignal.\n)
    ])
  end

  after(:all) do
    @runner.stop
  end

  VERSION_PATTERN = %r(\d+\.\d+\.\d+(-[a-z0-9]+)?).freeze
  REVISION_PATTERN = %r([a-z0-9]{7}).freeze
  ARCH_PATTERN=%r((x(86_)?64|i686)).freeze
  TARGET_PATTERN=%r((darwin|linux(-musl)?|freebsd)).freeze
  LIBRARY_TYPE_PATTERN=%r(static|dynamic).freeze
  TAR_FILENAME_PATTERN = %r(appsignal-#{ARCH_PATTERN}-#{TARGET_PATTERN}-all-#{LIBRARY_TYPE_PATTERN}.tar.gz).freeze
  DATETIME_PATTERN = %r(\d{4}-\d{2}-\d{2}[ |T]\d{2}:\d{2}:\d{2}( ?UTC|.\d+Z)?).freeze
  TRUE_OR_FALSE_PATTERN = %r(true|false).freeze
  PATH_PATTERN = /[\/\w\.-]+/.freeze
  LOG_LINE_PATTERN = %r(^(#.+|\[#{DATETIME_PATTERN} \(\w+\) \#\d+\]\[\w+\])).freeze

  def expect_output(expected)
    expected.each do |line|
      expect(@runner.readline).to match(line)
    end
  end

  def expect_newline
    expect(@runner.readline).to match(/^\n/)
  end

  def quoted(string)
    quote = "['\"]"
    %(#{quote}#{string}#{quote})
  end
end

RSpec.describe "Running the diagnose command with the --no-send-report option" do
  before do
    language = ENV['LANGUAGE'] || 'ruby'
    @runner = {
      'ruby' => Runner::Ruby.new(),
      'elixir' => Runner::Elixir.new(),
      'nodejs' => Runner::Nodejs.new()
    }[language]

    @runner.prepare()
    @runner.run("--no-send-report")
  end

  it "does not ask to send the report" do
    expect(
      @runner.any? do |line|
        %r(Send diagnostics report to AppSignal\?).match? line
      end
    ).to be(false)
  end

  it "does not send the report" do
      expect(
        @runner.any? do |line|
          line == %(  Not sending report. (Specified with the --no-send-report option.)\n)
        end
      ).to be(true)
  end
end
