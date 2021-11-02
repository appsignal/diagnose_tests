# frozen_string_literal: true

VERSION_PATTERN = /\d+\.\d+\.\d+(-[a-z0-9]+)?/.freeze
REVISION_PATTERN = /[a-z0-9]{7}/.freeze
ARCH_PATTERN = /(x(86_)?64|i686)/.freeze
TARGET_PATTERN = /(darwin\d*|linux(-gnu|-musl)?|freebsd)/.freeze
LIBRARY_TYPE_PATTERN = /static|dynamic/.freeze
TAR_FILENAME_PATTERN =
  /appsignal-#{ARCH_PATTERN}-#{TARGET_PATTERN}-all-#{LIBRARY_TYPE_PATTERN}.tar.gz/.freeze
DOWNLOAD_URL = %r{https://appsignal-agent-releases.global.ssl.fastly.net/#{REVISION_PATTERN}/#{TAR_FILENAME_PATTERN}}.freeze
DATETIME_PATTERN = /\d{4}-\d{2}-\d{2}[ |T]\d{2}:\d{2}:\d{2}( ?UTC|.\d+Z)?/.freeze
TRUE_OR_FALSE_PATTERN = /true|false/.freeze
PATH_PATTERN = %r{[/\w.-]+}.freeze
LOG_LINE_PATTERN = /^(#.+|\[#{DATETIME_PATTERN} \(\w+\) \#\d+\]\[\w+\])/.freeze

RSpec.describe "Running the diagnose command without any arguments" do
  before(:all) do
    @runner = init_runner(:prompt => "y")
    @runner.run
    @received_report = DiagnoseServer.last_received_report
  end

  it "prints all sections in the correct order" do
    section_keys =
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
    expect(@runner.output.sections.keys).to eq(section_keys), @runner.output.to_s
  end

  it "submitted report contains all keys" do
    expect(@received_report.to_h.keys).to contain_exactly(
      "agent",
      "config",
      "host",
      "installation",
      "library",
      "paths",
      "process",
      "validation"
    )
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
    expect_output_for(
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

  it "submitted report contains library section" do
    expect_report_for(
      :library,
      "language" => @runner.type.to_s,
      "agent_version" => REVISION_PATTERN,
      "package_version" => VERSION_PATTERN,
      "extension_loaded" => true
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
      /    Download URL: #{quoted DOWNLOAD_URL}/
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
    expect_output_for(:installation, matchers)
  end

  it "submitted report contains extension installation section" do
    expect_report_for(
      :installation,
      "result" => { "status" => "success" },
      "language" => {
        "name" => @runner.type.to_s,
        "version" => VERSION_PATTERN,
        "implementation" => be_kind_of(String)
      },
      "download" => {
        "checksum" => "verified",
        "download_url" => DOWNLOAD_URL
      },
      "build" => {
        "time" => DATETIME_PATTERN,
        "architecture" => ARCH_PATTERN,
        "target" => TARGET_PATTERN,
        "musl_override" => false,
        "linux_arm_override" => false,
        "library_type" => "static",
        "source" => "remote",
        "dependencies" => {},
        "flags" => {}
      },
      "host" => {
        "dependencies" => {},
        "root_user" => false
      }
    )
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
    expect_output_for(:host, matchers)
  end

  it "submitted report contains host section" do
    expect_report_for(
      :host,
      "architecture" => ARCH_PATTERN,
      "heroku" => false,
      "language_version" => VERSION_PATTERN,
      "os" => TARGET_PATTERN,
      "root" => false,
      "running_in_container" => boolean
    )
  end

  it "prints the agent diagnostics section" do
    expect_output_for(
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

  it "submitted report contains agent diagnostics section" do
    expect_report_for(
      :agent,
      "agent" => {
        "boot" => {
          "started" => { "result" => true }
        },
        "config" => {
          "valid" => { "result" => true }
        },
        "host" => {
          "gid" => { "result" => kind_of(Numeric) },
          "uid" => { "result" => kind_of(Numeric) }
        },
        "lock_path" => {
          "created" => { "result" => true }
        },
        "logger" => {
          "started" => { "result" => true }
        },
        "working_directory_stat" => {
          "gid" => { "result" => kind_of(Numeric) },
          "mode" => { "result" => kind_of(Numeric) },
          "uid" => { "result" => kind_of(Numeric) }
        }
      },
      "extension" => {
        "config" => {
          "valid" => { "result" => true }
        }
      }
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
    expect_output_for(:config, matchers)
  end

  it "submitted report contains configuration section" do
    expected_report_section =
      case @runner.type
      when :ruby
        {
          "options" => {
            "active" => true,
            "ca_file_path" => matching(%r{.+/appsignal[-/]ruby/resources/cacert\.pem$}),
            "debug" => false,
            "dns_servers" => [],
            "enable_allocation_tracking" => true,
            "enable_gc_instrumentation" => false,
            "enable_host_metrics" => true,
            "enable_minutely_probes" => true,
            "enable_statsd" => true,
            "endpoint" => "https://push.appsignal.com",
            "env" => "test",
            "files_world_accessible" => true,
            "filter_parameters" => [],
            "filter_session_data" => [],
            "ignore_actions" => [],
            "ignore_errors" => [],
            "ignore_namespaces" => [],
            "instrument_net_http" => true,
            "instrument_redis" => true,
            "instrument_sequel" => true,
            "log" => "file",
            "push_api_key" => "test",
            "request_headers" => [
              "HTTP_ACCEPT",
              "HTTP_ACCEPT_CHARSET",
              "HTTP_ACCEPT_ENCODING",
              "HTTP_ACCEPT_LANGUAGE",
              "HTTP_CACHE_CONTROL",
              "HTTP_CONNECTION",
              "CONTENT_LENGTH",
              "PATH_INFO",
              "HTTP_RANGE",
              "REQUEST_METHOD",
              "REQUEST_URI",
              "SERVER_NAME",
              "SERVER_PORT",
              "SERVER_PROTOCOL"
            ],
            "send_environment_metadata" => true,
            "send_params" => true,
            "skip_session_data" => false,
            "transaction_debug_mode" => false
          },
          "sources" => kind_of(Hash) # TODO: make separate spec for this?
        }
      when :elixir
        # TODO
        raise "Report matchers missing"
      when :nodejs
        {
          "options" => {
            "active" => true,
            "ca_file_path" => ending_with("cert/cacert.pem"),
            "debug" => false,
            "endpoint" => "https://push.appsignal.com",
            "env" => "test",
            "log" => "file",
            "log_path" => "/tmp",
            "push_api_key" => "test",
            "undefined" => "/tmp/appsignal.log" # TODO: Fix in integration: https://github.com/appsignal/appsignal-nodejs/issues/472
          },
          "sources" => {} # TODO: Fix in integration: https://github.com/appsignal/appsignal-nodejs/issues/473
        }
      else
        raise "No clause for runner #{@runner}"
      end
    expect_report_for(:config, expected_report_section)
  end

  it "prints the validation section" do
    expect_output_for(
      :validation,
      [
        "Validation",
        /  Validating Push API key: (\e\[31m)?invalid(\e\[0m)?/
      ]
    )
  end

  it "submitted report contains validation section" do
    expect_report_for(
      :validation,
      "push_api_key" => "invalid"
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

    expect_output_for(:paths, matchers)
  end

  it "submitted report contains paths section" do
    default_paths = {
      "appsignal.log" => {
        "content" => including(
          "[2021-06-14T13:44:22 (process) #49713][INFO] Starting AppSignal diagnose",
          "[2021-06-14T13:50:02 (process) #51074][INFO] Starting AppSignal diagnose",
          "[2021-06-14T13:51:54 (process) #51823][INFO] Starting AppSignal diagnose",
          "[2021-06-14T13:52:07 (process) #52200][INFO] Starting AppSignal diagnose",
          "[2021-06-14T13:53:03 (process) #52625][INFO] Starting AppSignal diagnose",
          "[2021-06-14T13:55:20 (process) #53396][INFO] Starting AppSignal diagnose",
          "[2021-06-14T13:59:10 (process) #53880][INFO] Starting AppSignal diagnose",
          "[2021-06-14T14:05:53 (process) #54792][INFO] Starting AppSignal diagnose",
          "[2021-06-14T14:11:37 (process) #55323][INFO] Starting AppSignal diagnose"
        ),
        "exists" => true,
        "mode" => kind_of(String),
        "ownership" => path_ownership(@runner.type),
        "path" => ending_with("/appsignal.log"),
        "type" => "file",
        "writable" => true
      },
      "log_dir_path" => {
        "exists" => true,
        "mode" => kind_of(String),
        "ownership" => path_ownership(@runner.type),
        "path" => ending_with("/tmp"),
        "type" => "directory",
        "writable" => true
      },
      "working_dir" => {
        "exists" => true,
        "mode" => kind_of(String),
        "ownership" => path_ownership(@runner.type),
        "path" => match(PATH_PATTERN),
        "type" => "directory",
        "writable" => true
      }
    }

    matchers =
      case @runner.type
      when :nodejs
        default_paths
      when :ruby
        default_paths.merge(
          "ext/mkmf.log" => {
            "exists" => false,
            "path" => ending_with("ext/mkmf.log")
          },
          "package_install_path" => { # TODO: Add this to Node.js as well
            "exists" => true,
            "mode" => kind_of(String),
            "ownership" => path_ownership(@runner.type),
            "path" => ending_with("ruby"),
            "type" => "directory",
            "writable" => true
          },
          "root_path" => { # TODO: Add this to Node.js as well
            "exists" => true,
            "mode" => kind_of(String),
            "ownership" => path_ownership(@runner.type),
            "path" => @runner.directory,
            "type" => "directory",
            "writable" => true
          }
        )
      when :elixir
        # TODO
        raise "Report matchers missing"
      else
        raise "No match found for runner #{@runner.type}"
      end
    expect_report_for(:paths, matchers)
  end

  it "prints the diagnostics report section" do
    expect_output_for(
      :send_report,
      [
        "Diagnostics report",
        "  Do you want to send this diagnostics report to AppSignal?",
        "  If you share this report you will be given a link to",
        "  AppSignal.com to validate the report.",
        "  You can also contact us at support@appsignal.com",
        "  with your support token.",
        "",
        "  Send diagnostics report to AppSignal? (Y/n):   Transmitting diagnostics report",
        "",
        "  Your support token: diag_support_token",
        "  View this report:   https://appsignal.com/diagnose/diag_support_token"
      ]
    )
  end
end

RSpec.describe "Running the diagnose command and not submitting report" do
  before :all do
    @runner = init_runner(:prompt => "n")
    @runner.run
    @received_report = DiagnoseServer.last_received_report
  end

  it "does not ask to send the report" do
    expect_output_for(
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

  it "does not submit a report" do
    expect(@received_report).to be_nil
  end
end

RSpec.describe "Running the diagnose command with the --send-report option" do
  before :all do
    @runner = init_runner(:args => ["--send-report"])
    @runner.run
    @received_report = DiagnoseServer.last_received_report
  end

  it "sends the report automatically" do
    send_report = section(:send_report)
    expect(send_report).to_not include("Send diagnostics report to AppSignal?")
    expect(send_report).to include(
      "  Your support token: diag_support_token",
      "  View this report:   https://appsignal.com/diagnose/diag_support_token"
    )
  end

  it "submit a report automatically" do
    expect(@received_report).to be_instance_of(DiagnoseReport)
  end
end

RSpec.describe "Running the diagnose command with the --no-send-report option" do
  before :all do
    @runner = init_runner(:args => ["--no-send-report"])
    @runner.run
    @received_report = DiagnoseServer.last_received_report
  end

  it "does not ask to send the report" do
    send_report = section(:send_report)
    expect(send_report).to_not include("Send diagnostics report to AppSignal?")
    expect(send_report).to include(
      "Not sending report. (Specified with the --no-send-report option.)"
    )
  end

  it "does not submit a report" do
    expect(@received_report).to be_nil
  end
end

RSpec.describe "Running the diagnose command without install report file" do
  before :all do
    @runner = init_runner(:install_report => false, :prompt => "y")
    @runner.run
    @received_report = DiagnoseServer.last_received_report
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

    expect_output_for(:installation, matchers)
  end

  it "submitted report contains install report errors" do
    matchers =
      case @runner.type
      when :nodejs
        {
          "parsing_error" => {
            "backtrace" => kind_of(Array),
            "error" => match(/Error: ENOENT: no such file or directory.*install\.report/)
          }
        }
      when :ruby
        {
          "parsing_error" => {
            "backtrace" => kind_of(Array),
            "error" => match(/Errno::ENOENT: No such file or directory.*install\.report/)
          }
        }
      when :elixir
        # TODO
        raise "Report matchers missing"
      else
        raise "No clause for runner #{@runner}"
      end
    expect_report_for(:installation, matchers)
  end
end

RSpec.describe "Running the diagnose command without Push API key" do
  before :all do
    @runner = init_runner(:push_api_key => "", :prompt => "y")
    @runner.run
    @received_report = DiagnoseServer.last_received_report
  end

  it "prints agent diagnose section with errors" do
    expect_output_for(
      :agent,
      [
        /Agent diagnostics/,
        /  Extension tests/,
        /  Configuration: invalid/,
        /     Error: RequiredEnvVarNotPresent\("_APPSIGNAL_PUSH_API_KEY"\)/,
        /  Agent tests/,
        /    Started: -/,
        /    Process user id: -/,
        /    Process user group id: -/,
        /    Configuration: -/,
        /    Logger: -/,
        /    Working directory user id: -/,
        /    Working directory user group id: -/,
        /    Working directory permissions: -/,
        /    Lock path: -/
      ]
    )
  end

  it "submitted report contains agent diagnostics errors" do
    expect_report_for(
      :agent,
      "extension" => {
        "config" => {
          "valid" => {
            "error" => "RequiredEnvVarNotPresent(\"_APPSIGNAL_PUSH_API_KEY\")",
            "result" => false
          }
        }
      }
    )
  end
end
