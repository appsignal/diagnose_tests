# frozen_string_literal: true

VERSION_PATTERN = /\d+\.\d+\.\d+(-[a-z0-9]+)?/.freeze
REVISION_PATTERN = /[a-z0-9]{7}/.freeze
ARCH_PATTERN = /(x(86_)?64|i686)/.freeze
TARGET_PATTERN = /(darwin\d*|linux(-gnu|-musl)?|freebsd)/.freeze
LIBRARY_TYPE_PATTERN = /static|dynamic/.freeze
TAR_FILENAME_PATTERN =
  /appsignal-#{ARCH_PATTERN}-#{TARGET_PATTERN}-all-#{LIBRARY_TYPE_PATTERN}.tar.gz/.freeze
DATETIME_PATTERN = /\d{4}-\d{2}-\d{2}[ |T]\d{2}:\d{2}:\d{2}( ?UTC|.\d+Z)?/.freeze
TRUE_OR_FALSE_PATTERN = /true|false/.freeze
PATH_PATTERN = %r{[/\w.-]+}.freeze
LOG_LINE_PATTERN = /^(#.+|\[#{DATETIME_PATTERN} \(\w+\) \#\d+\]\[\w+\])/.freeze

RSpec.describe "Running the diagnose command without any arguments" do
  before(:all) do
    @runner = init_runner(:prompt => "n")
    @runner.run
  end

  it "prints all sections in the correct order" do
    section_keys =
      case @runner.type
      when :ruby, :elixir
        [
          :header,
          :library,
          :installation,
          :host,
          :agent,
          :config,
          :validation,
          :paths,
          :send_report
        ]
      when :nodejs
        [
          :header,
          :library,
          :installation,
          :host,
          # TODO: Add agent section for Node.js
          :config,
          :validation,
          :paths,
          :send_report
        ]
      else
        raise "Language `#{@runner.language}` not configured for this spec!"
      end
    expect(@runner.output.sections.keys).to eq(section_keys), @runner.output.to_s
  end

  it "prints no 'other' section" do
    # Any output that couldn't be categorized are part of the "other" category.
    # It should not exist.
    expect(section(:other)).to eq("") if @runner.output.sections.key?(:other)
  end

  it "prints the diagnose header" do
    expect(section(:header)).to eql(<<~OUTPUT)
      AppSignal diagnose
      ================================================================================
      Use this information to debug your configuration.
      More information is available on the documentation site.
      https://docs.appsignal.com/
      Send this output to support@appsignal.com if you need help.
      ================================================================================
    OUTPUT
  end

  it "prints the library section" do
    expect_section(
      :library,
      [
        /AppSignal library/,
        /  Language: #{@runner.language_name}/,
        /  (Gem|Package) version: #{quoted VERSION_PATTERN}/,
        /  Agent version: #{quoted REVISION_PATTERN}/,
        /  (Extension|Nif) loaded: true/
      ]
    )
  end

  it "prints the extension installation section" do
    matchers = [
      "Extension installation report",
      /  Installation result/,
      /    Status: success/,
      /  Language details/,
      /    #{@runner.language_name} version: #{quoted VERSION_PATTERN}/
    ]

    matchers << /    OTP version: #{quoted(/\d+/)}/ if @runner.type == :elixir

    matchers += [
      /  Download details/,
      /    Download URL: #{quoted %r{https://appsignal-agent-releases.global.ssl.fastly.net/#{REVISION_PATTERN}/#{TAR_FILENAME_PATTERN}}}/
    ]

    if @runner.type == :elixir
      matchers += [
        /    Architecture: #{quoted ARCH_PATTERN}/,
        /    Target: #{quoted TARGET_PATTERN}/,
        /    Musl override: #{TRUE_OR_FALSE_PATTERN}/,
        /    Linux ARM override: false/,
        /    Library type: #{quoted LIBRARY_TYPE_PATTERN}/
      ]
    end

    matchers += [
      /    Checksum: #{quoted "verified"}/,
      /  Build details/,
      /    Install time: #{quoted DATETIME_PATTERN}/
    ]

    if @runner.type == :elixir
      matchers += [
        /    Source: #{quoted "remote"}/,
        /    Agent version: #{quoted REVISION_PATTERN}/
      ]
    end

    matchers += [
      /    Architecture: #{quoted ARCH_PATTERN}/,
      /    Target: #{quoted TARGET_PATTERN}/,
      /    Musl override: #{TRUE_OR_FALSE_PATTERN}/,
      /    Linux ARM override: false/,
      /    Library type: #{quoted LIBRARY_TYPE_PATTERN}/,
      /  Host details/,
      /    Root user: #{TRUE_OR_FALSE_PATTERN}/
    ]
    expect_section(:installation, matchers)
  end

  it "prints the host information section" do
    architecture =
      if @runner.type == :elixir
        /#{ARCH_PATTERN}-.+/
      else
        ARCH_PATTERN
      end
    matchers = [
      /Host information/,
      /  Architecture: #{quoted architecture}/,
      /  Operating System: #{quoted TARGET_PATTERN}/,
      /  #{@runner.language_name} version: #{quoted VERSION_PATTERN}/
    ]
    matchers << /  OTP version: #{quoted(/\d+/)}/ if @runner.type == :elixir
    matchers += [
      /  Root user: #{TRUE_OR_FALSE_PATTERN}/,
      /  Running in container: #{TRUE_OR_FALSE_PATTERN}/
    ]
    expect_section(:host, matchers)
  end

  it "prints the agent diagnostics section" do
    skip if @runner.instance_of?(Runner::Nodejs)

    expect_section(
      :agent,
      [
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
      ]
    )
  end

  it "prints the configuration section" do
    matchers = ["Configuration"]

    case @runner.type
    when :ruby
      matchers += [
        /  Environment: #{quoted("test")}/,
        /  debug: false/,
        /  log: #{quoted("file")}/,
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
        %r{  ca_file_path: ".+/appsignal[-/]ruby/resources/cacert.pem"},
        /  dns_servers: \[\]/,
        /  files_world_accessible: true/,
        /  transaction_debug_mode: false/,
        /  active: true \(Loaded from: system\)/,
        /  push_api_key: "test" \(Loaded from: env\)/
      ]
    when :nodejs
      matchers += [
        /  Environment: #{quoted("test")}/,
        /  debug: false/,
        /  log: #{quoted("file")}/,
        /  endpoint: #{quoted "https://push.appsignal.com"}/,
        /  ca_file_path: #{quoted ".+\/cacert.pem"}/,
        /  active: true/,
        /  push_api_key: #{quoted "test"}/
      ]
    when :elixir
      matchers += [
        /  active: true/,
        /    Sources:/,
        /      default: false/,
        /      system:  true/,
        /  ca_file_path: #{quoted ".+/_build/dev/rel/elixir_diagnose/lib/appsignal-\\d+\\.\\d+\\.\\d+/priv/cacert.pem"}/, # rubocop:disable Layout/LineLength
        /  debug: false/,
        /  diagnose_endpoint: #{quoted "https://appsignal.com/diag"}/,
        /  dns_servers: \[\]/,
        /  enable_host_metrics: true/,
        /  enable_minutely_probes: true/,
        /  enable_statsd: false/,
        /  endpoint: #{quoted "https://push.appsignal.com"}/,
        /  env: "dev"/,
        /  files_world_accessible: true/,
        /  filter_data_keys: \[\]/,
        /  filter_parameters: \[\]/,
        /  filter_session_data: \[\]/,
        /  ignore_actions: \[\]/,
        /  ignore_errors: \[\]/,
        /  ignore_namespaces: \[\]/,
        /  log: "file"/,
        /  push_api_key: #{quoted "test"} \(Loaded from env\)/,
        /  request_headers: \["accept", "accept-charset", "accept-encoding", "accept-language", "cache-control", "connection", "content-length", "path-info", "range", "request-method", "request-uri", "server-name", "server-port", "server-protocol"\]/, # rubocop:disable Layout/LineLength
        /  send_params: true/,
        /  skip_session_data: false/,
        /  transaction_debug_mode: false/,
        /  valid: true/
      ]
    else
      raise "No clause for runner #{@runner}"
    end

    matchers += [
      "",
      "Read more about how the diagnose config output is rendered",
      "https://docs.appsignal.com/#{@runner.type}/command-line/diagnose.html"
    ]
    expect_section(:config, matchers)
  end

  it "prints the validation section" do
    expect_section(
      :validation,
      [
        "Validation",
        /  Validating Push API key: (\e\[31m)?invalid(\e\[0m)?/
      ]
    )
  end

  it "prints the paths section" do
    matchers = ["Paths"]

    if @runner.type == :ruby
      matchers += [
        %(  AppSignal gem path),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+\)/,
        ""
      ]
    end

    matchers += [
      %(  Current working directory),
      /    Path: #{quoted(PATH_PATTERN)}/
    ]

    if [:ruby, :elixir].include? @runner.type
      matchers += [
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+\)/
      ]
    end
    matchers += [""]

    if @runner.type == :ruby
      matchers += [
        %(  Root path),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+\)/,
        ""
      ]
    end

    matchers += [
      %(  Log directory),
      /    Path: #{quoted(PATH_PATTERN)}/
    ]

    if [:ruby, :elixir].include? @runner.type
      matchers += [
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+\)/
      ]
    end
    matchers += [""]

    if @runner.type == :ruby
      matchers += [
        %(  Makefile install log),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Exists\?: #{TRUE_OR_FALSE_PATTERN}/,
        ""
      ]
    end

    matchers += [
      %(  AppSignal log),
      /    Path: #{quoted(PATH_PATTERN)}/
    ]

    if [:ruby, :elixir].include? @runner.type
      matchers += [
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+\)/
      ]
    end

    matchers += ([
      /    Contents \(last 10 lines\):/
    ] + Array.new(10).map { LOG_LINE_PATTERN })

    expect_section(:paths, matchers)
  end

  it "prints the diagnostics report section" do
    expect_section(
      :send_report,
      [
        "Diagnostics report",
        "  Do you want to send this diagnostics report to AppSignal?",
        "  If you share this report you will be given a link to",
        "  AppSignal.com to validate the report.",
        "  You can also contact us at support@appsignal.com",
        "  with your support token.",
        "",
        "  Send diagnostics report to AppSignal? (Y/n):   " \
          "Not sending diagnostics information to AppSignal."
      ]
    )
  end
end

RSpec.describe "Running the diagnose command with the --no-send-report option" do
  before do
    @runner = init_runner(:args => ["--no-send-report"])
    @runner.run
  end

  it "does not ask to send the report" do
    send_report = section(:send_report)
    expect(send_report).to_not include("Send diagnostics report to AppSignal?")
    expect(send_report).to include(
      "Not sending report. (Specified with the --no-send-report option.)"
    )
  end
end

RSpec.describe "Running the diagnose command without install report file" do
  before do
    @runner = init_runner(:install_report => false, :prompt => "n")
    @runner.run
  end

  it "prints handled errors instead of the report" do
    matchers = ["Extension installation report"]
    case @runner.type
    when :ruby, :nodejs
      matchers += [
        "  Error found while parsing the report.",
        /^  Error: .* [nN]o such file or directory.*install\.report/
      ]
    when :elixir
      matchers += [
        "  Error found while parsing the download report.",
        "  Error: :enoent",
        "  Error found while parsing the installation report.",
        "  Error: :enoent"
      ]
    else
      raise "No match found for runner #{@runner.type}"
    end

    expect_section(:installation, matchers)
  end
end
