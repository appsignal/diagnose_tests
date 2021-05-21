require 'logger'
require 'timeout'

class Runner
  def initialize
    @read, @write = IO.pipe
  end

  def run
    Dir.chdir(directory)
    `#{setup_command}`
    @pid = spawn(run_command, out: @write)
  end

  def readline
    line = Timeout::timeout(30) { @read.readline }

    logger.debug(line)

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

  def stop
    Process.kill(3, @pid)
  end

  def logger
    Logger.new(STDOUT)
  end

  def prepare
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
    "BUNDLE_GEMFILE=#{File.join(__dir__, "../ruby/Gemfile")} bundle exec appsignal diagnose"
  end

  def ignored_lines
    [
      %r(Implementation: ruby),
      %r(Flags: {}),
      %r(Dependencies: {}),
      %r(appsignal: Unable to log to )
    ]
  end

  def language_name
    'Ruby'
  end

  def prepare
    File.write(File.join(__dir__, "../../../../ext/install.report"), install_report)
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
    "../../../../packages/nodejs/bin/diagnose"
  end

  def ignored_lines
    [
      %r(WARNING: Error when reading appsignal config, appsignal \(as \d+/\d+\) not starting: Required environment variable '_APPSIGNAL_PUSH_API_KEY' not present),
      %r(Dependencies: {})
    ]
  end

  def language_name
    'Node.js'
  end

  def prepare
    File.write("/tmp/appsignal-install-report.json", install_report)
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
        "library_type": "static"
      },
      "host": {
        "root_user": false,
        "dependencies": {}
      }
    }}
  end
end

RSpec.describe "Diagnose" do
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

  after(:all) do
    @runner.stop
  end

  VERSION_PATTERN = %r(\d+\.\d+\.\d+(-[a-z0-9]+)?).freeze
  REVISION_PATTERN = %r([a-z0-9]{7}).freeze
  ARCH_PATTERN=%r((x(86_)?64|i686)).freeze
  TARGET_PATTERN=%r((darwin|linux(-musl)?|freebsd)).freeze
  LIBRARY_TYPE_PATTERN=%r(static|dynamic).freeze
  TAR_FILENAME_PATTERN = %r(appsignal-#{ARCH_PATTERN}-#{TARGET_PATTERN}-all-#{LIBRARY_TYPE_PATTERN}.tar.gz).freeze
  DATETIME_PATTERN = %r(\d{4}-\d{2}-\d{2}[ |T]\d{2}:\d{2}:\d{2}( ?UTC|.\d+Z)).freeze
  TRUE_OR_FALSE_PATTERN = %r(true|false).freeze

  def expect_output(expected)
    expected.each do |line|
      expect(@runner.readline).to match(line)
    end
  end

  def expect_newline
    expect(@runner.readline).to match("\n")
  end
end
