# frozen_string_literal: true

VERSION_PATTERN = /\d+\.\d+\.\d+(-[a-z0-9]+)?([-.].+)?/
AGENT_VERSION_PATTERN = VERSION_PATTERN
ARCH_PATTERN = /(x(86_)?64|i686|arm64)/
TARGET_PATTERN = /(darwin\d*|linux(-gnu|-musl)?|freebsd)/
LIBRARY_TYPE_PATTERN = /static|dynamic/
TAR_FILENAME_PATTERN =
  /appsignal-#{ARCH_PATTERN}-#{TARGET_PATTERN}-all-#{LIBRARY_TYPE_PATTERN}.tar.gz/
DOWNLOAD_URL = %r{https://appsignal-agent-releases.global.ssl.fastly.net/#{AGENT_VERSION_PATTERN}/#{TAR_FILENAME_PATTERN}}
DATETIME_PATTERN = /\d{4}-\d{2}-\d{2}[ |T]\d{2}:\d{2}:\d{2}( ?UTC|.\d+Z)?/
TRUE_OR_FALSE_PATTERN = /(t|T)rue|(f|F)alse/
PATH_PATTERN = %r{[/\w.-]+}
LOG_LINE_PATTERN = /^(#.+|\[#{DATETIME_PATTERN} \(\w+\) \#\d+\]\[\w+\])/

RSpec.describe "Running the diagnose command without any arguments" do
  before(:all) do
    MockServer.auth_response_code = 200
    MockServer.diagnose_response_code = 200
    @runner = init_runner(:prompt => "y")
    @runner.run
    @received_report = MockServer.last_diagnose_report
  end

  it "receives the report with the correct query params" do
    matchers =
      case @runner.type
      when :ruby
        {
          "gem_version" => VERSION_PATTERN
        }
      end

    expect(@received_report.params).to match(
      {
        "api_key" => "test",
        "environment" => kind_of(String),
        "hostname" => be_empty.or(be_nil),
        "name" => "DiagnoseTests"
      }.merge(matchers || {})
    )
  end

  it "prints all sections in the correct order" do
    section_keys = [
      :header,
      :library,
      (:installation unless @runner.type == :python),
      :host,
      :agent,
      :config,
      :validation,
      :paths,
      :send_report
    ].compact
    expect(@runner.output.sections.keys).to eq(section_keys), @runner.output.to_s
  end

  it "submitted report contains all keys" do
    expect(@received_report.to_h.keys).to contain_exactly(*[
      "agent",
      "config",
      "host",
      ("installation" unless @runner.type == :python),
      "library",
      "paths",
      "process",
      "validation"
    ].compact)
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
    expected_output = if @runner.type == :python
                        [
                          /AppSignal library/,
                          /  Language: #{@runner.language_name}/,
                          /  (Gem|Package) version: #{quoted VERSION_PATTERN}/,
                          /  Agent version: #{quoted AGENT_VERSION_PATTERN}/,
                          /  Package architecture: #{quoted ARCH_PATTERN}/,
                          /  Package platform: #{quoted TARGET_PATTERN}/
                        ]
                      else
                        [
                          /AppSignal library/,
                          /  Language: #{@runner.language_name}/,
                          /  (Gem|Package) version: #{quoted VERSION_PATTERN}/,
                          /  Agent version: #{quoted AGENT_VERSION_PATTERN}/,
                          /  (Extension|Nif) loaded: (t|T)rue/
                        ]
                      end

    expect_output_for(
      :library,
      expected_output
    )
  end

  it "submitted report contains library section" do
    expected_output = {
      "language" => @runner.type.to_s,
      "agent_version" => AGENT_VERSION_PATTERN,
      "package_version" => VERSION_PATTERN
    }

    if @runner.type == :python
      expected_output["package_architecture"] = ARCH_PATTERN
      expected_output["package_platform"] = TARGET_PATTERN
    else
      expected_output["extension_loaded"] = true
    end

    expect_report_for(
      :library,
      expected_output
    )
  end

  it "prints the extension installation section" do
    skip if @runner.type == :python

    matchers = [
      "Extension installation report",
      /  Installation result/,
      /    Status: success/,
      /  Language details/
    ]
    matchers << /    Implementation: #{quoted "ruby"}/ if @runner.type == :ruby
    matchers << /    #{@runner.language_name} version: #{quoted VERSION_PATTERN}/
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
        /    Agent version: #{quoted AGENT_VERSION_PATTERN}/
      ]
    end

    matchers += [
      /    Architecture: #{quoted ARCH_PATTERN}/,
      /    Target: #{quoted TARGET_PATTERN}/,
      /    Musl override: #{TRUE_OR_FALSE_PATTERN}/,
      /    Linux ARM override: false/,
      /    Library type: #{quoted LIBRARY_TYPE_PATTERN}/,
      /    Dependencies: %?\{\}/,
      /    Flags: %?\{\}/,
      /  Host details/,
      /    Root user: #{TRUE_OR_FALSE_PATTERN}/,
      /    Dependencies: %?\{\}/
    ]
    expect_output_for(:installation, matchers)
  end

  it "submitted report contains extension installation section" do
    skip if @runner.type == :python

    extra_language =
      case @runner.type
      when :elixir
        { "otp_version" => /\d+/ }
      else
        { "implementation" => be_kind_of(String) }
      end
    extra_download =
      if @runner.type == :elixir
        {
          "time" => DATETIME_PATTERN,
          "architecture" => ARCH_PATTERN,
          "target" => TARGET_PATTERN,
          "musl_override" => false,
          "linux_arm_override" => false,
          "library_type" => "static"
        }
      end
    extra_build =
      if @runner.type == :elixir
        { # TODO: should also be part of the other integrations?
          "agent_version" => AGENT_VERSION_PATTERN,
          "package_path" => ending_with("appsignal/priv")
        }
      end
    expect_report_for(
      :installation,
      "result" => { "status" => "success" },
      "language" => {
        "name" => @runner.type.to_s,
        "version" => VERSION_PATTERN
      }.merge(extra_language || {}),
      "download" => {
        "checksum" => "verified",
        "download_url" => DOWNLOAD_URL
      }.merge(extra_download || {}),
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
      }.merge(extra_build || {}),
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
    matchers = {
      "architecture" => ARCH_PATTERN,
      "heroku" => false,
      "language_version" => VERSION_PATTERN,
      "os" => TARGET_PATTERN,
      "os_distribution" => kind_of(String),
      "root" => false,
      "running_in_container" => boolean
    }
    matchers.merge!("otp_version" => matching(/\d+/)) if @runner.type == :elixir
    expect_report_for(:host, matchers)
  end

  it "prints the agent diagnostics section" do
    expected_output = if @runner.type == :python
                        [
                          /Agent diagnostics/,
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
                      else
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
                      end

    expect_output_for(
      :agent,
      expected_output
    )
  end

  it "submitted report contains agent diagnostics section" do
    agent_matcher = {
      "agent" => {
        "boot" => {
          "started" => { "result" => true }
        },
        "config" => {
          "valid" => { "result" => true }
        },
        "host" => {
          "gid" => { "result" => kind_of(Numeric) },
          "uid" => { "result" => kind_of(Numeric) },
          "running_in_container" => { "result" => (be(true).or be(false)) }
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
      }
    }

    if @runner.type == :python
      expect_report_for(
        :agent,
        agent_matcher
      )
    else
      expect_report_for(
        :agent,
        agent_matcher.merge(
          "extension" => {
            "config" => {
              "valid" => { "result" => true }
            }
          }
        )
      )
    end
  end

  it "prints the configuration section" do
    matchers = ["Configuration"]

    case @runner.type
    when :ruby
      matchers += [
        /  active: true \(Loaded from: system\)/,
        /  activejob_report_errors: "all"/,
        %r{  ca_file_path: ".+/appsignal[-/]ruby/resources/cacert.pem"},
        "  dns_servers: []",
        /  enable_allocation_tracking: true/,
        /  enable_at_exit_hook: "on_error"/,
        /  enable_at_exit_reporter: true/,
        /  enable_gvl_global_timer: true/,
        /  enable_gvl_waiting_threads: true/,
        /  enable_host_metrics: true/,
        /  enable_minutely_probes: false/,
        /    Sources:/,
        /      default: true/,
        /      file:    false/,
        /  enable_nginx_metrics: false/,
        /  enable_rails_error_reporter: true/,
        /  enable_rake_performance_instrumentation: false/,
        /  enable_statsd: true/,
        /  endpoint: #{quoted ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil)}/,
        /    Sources:/,
        /      default: #{quoted "https://push.appsignal.com"}/,
        /      env:     #{quoted ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil)}/,
        /  environment: #{quoted("development")} \(Loaded from: initial\)/,
        /  files_world_accessible: true/,
        /  filter_metadata: \[\]/,
        /  filter_parameters: \[\]/,
        /  filter_session_data: \[\]/,
        /  ignore_actions: \[\]/,
        /  ignore_errors: \[\]/,
        /  ignore_logs: \[\]/,
        /  ignore_namespaces: \[\]/,
        /  instrument_http_rb: true/,
        /  instrument_net_http: true/,
        /  instrument_ownership: true/,
        /  instrument_redis: true/,
        /  instrument_sequel: true/,
        /  log: #{quoted("file")}/,
        /  logging_endpoint: #{quoted("https://appsignal-endpoint.net")}/,
        /  name: #{quoted "DiagnoseTests"} \(Loaded from: file\)/,
        /  ownership_set_namespace: false/,
        /  push_api_key: "test" \(Loaded from: env\)/,
        /  request_headers: \["HTTP_ACCEPT", "HTTP_ACCEPT_CHARSET", "HTTP_ACCEPT_ENCODING", "HTTP_ACCEPT_LANGUAGE", "HTTP_CACHE_CONTROL", "HTTP_CONNECTION", "CONTENT_LENGTH", "PATH_INFO", "HTTP_RANGE", "REQUEST_METHOD", "REQUEST_PATH", "SERVER_NAME", "SERVER_PORT", "SERVER_PROTOCOL"\]/, # rubocop:disable Layout/LineLength
        /  send_environment_metadata: true/,
        /  send_params: true/,
        /  send_session_data: true/,
        /  sidekiq_report_errors: "all"/
      ]
    when :nodejs
      matchers += [
        /  active: true/,
        /    Sources:/,
        /      default: false/,
        /      initial: true/,
        /  caFilePath: #{quoted ".+/cacert.pem"}/,
        /  disableDefaultInstrumentations: false/,
        /  dnsServers: \[\]/,
        /  enableHostMetrics: true/,
        /  enableMinutelyProbes: false/,
        /    Sources:/,
        /      default: true/,
        /      env:     false/,
        /  enableNginxMetrics: false/,
        /  enableOpentelemetryHttp: true/,
        /  enableStatsd: false/,
        /  endpoint: #{quoted ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil)}/,
        /    Sources:/,
        /      default: #{quoted "https://push.appsignal.com"}/,
        /      env:     #{quoted ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil)}/,
        /  environment: #{quoted("development")}/,
        /  filesWorldAccessible: true/,
        /  filterParameters: \[\]/,
        /  filterSessionData: \[\]/,
        /  ignoreActions: \[\]/,
        /  ignoreErrors: \[\]/,
        /  ignoreLogs: \[\]/,
        /  ignoreNamespaces: \[\]/,
        /  initializeOpentelemetrySdk: true/,
        /  log: #{quoted("file")}/,
        /  logLevel: #{quoted "debug"} \(Loaded from: initial\)/,
        /  loggingEndpoint: #{quoted("https://appsignal-endpoint.net")}/,
        /  name: #{quoted "DiagnoseTests"}/,
        /    Sources:/,
        /      env:     #{quoted "DiagnoseTests"}/,
        /      initial: #{quoted "DiagnoseTests"}/,
        /  opentelemetryPort: #{quoted "8099"}/,
        /  pushApiKey: #{quoted "test"} \(Loaded from: env\)/,
        /  requestHeaders: \["accept","accept-charset","accept-encoding","accept-language","cache-control","connection","content-length","range"\]/, # rubocop:disable Layout/LineLength
        /  sendEnvironmentMetadata: true/,
        /  sendParams: true/,
        /  sendSessionData: true/
      ]
    when :elixir
      matchers += [
        /  active: true/,
        /    Sources:/,
        /      default: false/,
        /      system:  true/,
        /  ca_file_path: #{quoted ".+/_build/dev/rel/elixir_diagnose/lib/appsignal-\\d+\\.\\d+\\.\\d+(-\\w+\\.\\d+)?/priv/cacert.pem"}/, # rubocop:disable Layout/LineLength
        /  debug: false/,
        "  dns_servers: []",
        /  enable_error_backend: true/,
        /  enable_host_metrics: true/,
        /  enable_minutely_probes: false/,
        /    Sources:/,
        /      default: true/,
        /      file:    false/,
        /  enable_nginx_metrics: false/,
        /  enable_statsd: false/,
        /  endpoint: #{quoted ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil)}/,
        /    Sources:/,
        /      default: #{quoted "https://push.appsignal.com"}/,
        /      env:     #{quoted ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil)}/,
        /  env: "dev"/,
        /  files_world_accessible: true/,
        /  filter_parameters: \[\]/,
        /  filter_session_data: \[\]/,
        /  ignore_actions: \[\]/,
        /  ignore_errors: \[\]/,
        /  ignore_logs: \[\]/,
        /  ignore_namespaces: \[\]/,
        /  instrument_absinthe: true/,
        /  instrument_ecto: true/,
        /  instrument_finch: true/,
        /  instrument_oban: true/,
        /  instrument_tesla: true/,
        /  log: "file"/,
        /  logging_endpoint: #{quoted("https://appsignal-endpoint.net")}/,
        /  name: #{quoted "DiagnoseTests"} \(Loaded from file\)/,
        /  push_api_key: #{quoted "test"} \(Loaded from env\)/,
        /  report_oban_errors: "all"/,
        /  request_headers: \["accept", "accept-charset", "accept-encoding", "accept-language", "cache-control", "connection", "content-length", "range"\]/, # rubocop:disable Layout/LineLength
        /  send_environment_metadata: true/,
        /  send_params: true/,
        /  send_session_data: true/,
        /  skip_session_data: false/
      ]
    when :python
      matchers += [
        /  ca_file_path: #{quoted ".+/src/appsignal/resources/cacert.pem"}/,
        /  diagnose_endpoint: #{quoted "http://localhost:4005/diag"}/,
        /  enable_host_metrics: True/,
        /  enable_minutely_probes: False/,
        /  enable_nginx_metrics: False/,
        /  enable_statsd: False/,
        /  environment: #{quoted "development"}/,
        /  endpoint: #{quoted ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil)}/,
        /  files_world_accessible: True/,
        /  log: #{quoted "file"}/,
        /  log_level: #{quoted "info"}/,
        /  logging_endpoint: #{quoted "https://appsignal-endpoint.net"}/,
        /  opentelemetry_port: 8099/,
        /  send_environment_metadata: True/,
        /  send_params: True/,
        /  send_session_data: True/,
        /  request_headers: \['accept', 'accept-charset', 'accept-encoding', 'accept-language', 'cache-control', 'connection', 'content-length', 'range'\]/, # rubocop:disable Layout/LineLength
        /  app_path:/,
        /  name: #{quoted "DiagnoseTests"}/,
        /  push_api_key: #{quoted "test"}/
      ]
    else
      raise "No clause for runner #{@runner}"
    end

    matchers += [
      "",
      "Read more about how the diagnose config output is rendered",
      %r{https://docs\.appsignal\.com/#{@runner.type}(/3.x)?/command-line/diagnose.html}
    ]
    expect_output_for(:config, matchers)
  end

  it "submitted report contains configuration options section" do
    expected_report_section =
      case @runner.type
      when :ruby
        {
          "active" => true,
          "activejob_report_errors" => "all",
          "ca_file_path" => matching(%r{.+/appsignal[-/]ruby/resources/cacert\.pem$}),
          "dns_servers" => [],
          "enable_allocation_tracking" => true,
          "enable_at_exit_hook" => "on_error",
          "enable_at_exit_reporter" => true,
          "enable_gvl_global_timer" => true,
          "enable_gvl_waiting_threads" => true,
          "enable_host_metrics" => true,
          "enable_minutely_probes" => false,
          "enable_nginx_metrics" => false,
          "enable_rails_error_reporter" => true,
          "enable_rake_performance_instrumentation" => false,
          "enable_statsd" => true,
          "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
          "env" => "development",
          "files_world_accessible" => true,
          "filter_metadata" => [],
          "filter_parameters" => [],
          "filter_session_data" => [],
          "ignore_actions" => [],
          "ignore_errors" => [],
          "ignore_logs" => [],
          "ignore_namespaces" => [],
          "instrument_http_rb" => true,
          "instrument_net_http" => true,
          "instrument_ownership" => true,
          "instrument_redis" => true,
          "instrument_sequel" => true,
          "log" => "file",
          "logging_endpoint" => "https://appsignal-endpoint.net",
          "name" => "DiagnoseTests",
          "ownership_set_namespace" => false,
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
            "REQUEST_PATH",
            "SERVER_NAME",
            "SERVER_PORT",
            "SERVER_PROTOCOL"
          ],
          "send_environment_metadata" => true,
          "send_params" => true,
          "send_session_data" => true,
          "sidekiq_report_errors" => "all"
        }
      when :elixir
        {
          "active" => true,
          "ca_file_path" => ending_with("priv/cacert.pem"),
          "diagnose_endpoint" => ENV.fetch("APPSIGNAL_DIAGNOSE_ENDPOINT", nil),
          "dns_servers" => [],
          "enable_error_backend" => true,
          "enable_host_metrics" => true,
          "enable_minutely_probes" => false,
          "enable_nginx_metrics" => false,
          "enable_statsd" => false,
          "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
          "env" => "dev",
          "files_world_accessible" => true,
          "filter_parameters" => [],
          "filter_session_data" => [],
          "ignore_actions" => [],
          "ignore_errors" => [],
          "ignore_logs" => [],
          "ignore_namespaces" => [],
          "instrument_absinthe" => true,
          "instrument_ecto" => true,
          "instrument_finch" => true,
          "instrument_oban" => true,
          "instrument_tesla" => true,
          "log" => "file",
          "logging_endpoint" => "https://appsignal-endpoint.net",
          "name" => "DiagnoseTests",
          "push_api_key" => "test",
          "report_oban_errors" => "all",
          "request_headers" => [
            "accept",
            "accept-charset",
            "accept-encoding",
            "accept-language",
            "cache-control",
            "connection",
            "content-length",
            "range"
          ],
          "send_environment_metadata" => true,
          "send_params" => true,
          "send_session_data" => true,
          "skip_session_data" => false
        }
      when :nodejs
        {
          "active" => true,
          "ca_file_path" => ending_with("cert/cacert.pem"),
          "disable_default_instrumentations" => false,
          "dns_servers" => [],
          "enable_host_metrics" => true,
          "enable_minutely_probes" => false,
          "enable_nginx_metrics" => false,
          "enable_opentelemetry_http" => true,
          "enable_statsd" => false,
          "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
          "env" => "development",
          "files_world_accessible" => true,
          "filter_parameters" => [],
          "filter_session_data" => [],
          "ignore_actions" => [],
          "ignore_errors" => [],
          "ignore_logs" => [],
          "ignore_namespaces" => [],
          "initialize_opentelemetry_sdk" => true,
          "log" => "file",
          "log_level" => "debug",
          "logging_endpoint" => "https://appsignal-endpoint.net",
          "name" => "DiagnoseTests",
          "opentelemetry_port" => "8099",
          "push_api_key" => "test",
          "request_headers" => [
            "accept",
            "accept-charset",
            "accept-encoding",
            "accept-language",
            "cache-control",
            "connection",
            "content-length",
            "range"
          ],
          "send_environment_metadata" => true,
          "send_params" => true,
          "send_session_data" => true
        }
      when :python
        {
          "app_path" => ending_with("diagnose/python"),
          "ca_file_path" => ending_with("resources/cacert.pem"),
          "diagnose_endpoint" => ending_with("diag"),
          "enable_host_metrics" => true,
          "enable_minutely_probes" => false,
          "enable_nginx_metrics" => false,
          "enable_statsd" => false,
          "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
          "environment" => "development",
          "files_world_accessible" => true,
          "log" => "file",
          "log_level" => "info",
          "logging_endpoint" => "https://appsignal-endpoint.net",
          "opentelemetry_port" => 8099,
          "name" => "DiagnoseTests",
          "push_api_key" => "test",
          "request_headers" => [
            "accept",
            "accept-charset",
            "accept-encoding",
            "accept-language",
            "cache-control",
            "connection",
            "content-length",
            "range"
          ],
          "send_environment_metadata" => true,
          "send_params" => true,
          "send_session_data" => true
        }
      else
        raise "No clause for runner #{@runner}"
      end

    expect_report_for(:config, :options, expected_report_section)
  end

  it "submitted report contains configuration sources section" do
    expected_report_section =
      case @runner.type
      when :ruby
        {
          "default" => {
            "activejob_report_errors" => "all",
            "ca_file_path" => matching(%r{.+/appsignal[-/]ruby/resources/cacert\.pem$}),
            "dns_servers" => [],
            "enable_allocation_tracking" => true,
            "enable_at_exit_hook" => "on_error",
            "enable_at_exit_reporter" => true,
            "enable_gvl_global_timer" => true,
            "enable_gvl_waiting_threads" => true,
            "enable_host_metrics" => true,
            "enable_minutely_probes" => true,
            "enable_nginx_metrics" => false,
            "enable_rails_error_reporter" => true,
            "enable_rake_performance_instrumentation" => false,
            "enable_statsd" => true,
            "endpoint" => "https://push.appsignal.com",
            "files_world_accessible" => true,
            "filter_metadata" => [],
            "filter_parameters" => [],
            "filter_session_data" => [],
            "ignore_actions" => [],
            "ignore_errors" => [],
            "ignore_logs" => [],
            "ignore_namespaces" => [],
            "instrument_http_rb" => true,
            "instrument_net_http" => true,
            "instrument_ownership" => true,
            "instrument_redis" => true,
            "instrument_sequel" => true,
            "log" => "file",
            "logging_endpoint" => "https://appsignal-endpoint.net",
            "ownership_set_namespace" => false,
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
              "REQUEST_PATH",
              "SERVER_NAME",
              "SERVER_PORT",
              "SERVER_PROTOCOL"
            ],
            "send_environment_metadata" => true,
            "send_params" => true,
            "send_session_data" => true,
            "sidekiq_report_errors" => "all"
          },
          "system" => {
            "active" => true
          },
          "loaders" => {},
          "initial" => {
            "env" => "development"
          },
          "file" => {
            "enable_minutely_probes" => false,
            "name" => "DiagnoseTests"
          },
          "env" => {
            "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
            "push_api_key" => "test"
          },
          "override" => {},
          "dsl" => {}
        }
      when :elixir
        {
          "default" => {
            "active" => false,
            "ca_file_path" => ending_with("priv/cacert.pem"),
            "diagnose_endpoint" => "https://appsignal.com/diag",
            "dns_servers" => [],
            "enable_error_backend" => true,
            "enable_host_metrics" => true,
            "enable_minutely_probes" => true,
            "enable_nginx_metrics" => false,
            "enable_statsd" => false,
            "endpoint" => "https://push.appsignal.com",
            "env" => "dev",
            "files_world_accessible" => true,
            "filter_parameters" => [],
            "filter_session_data" => [],
            "ignore_actions" => [],
            "ignore_errors" => [],
            "ignore_logs" => [],
            "ignore_namespaces" => [],
            "instrument_absinthe" => true,
            "instrument_ecto" => true,
            "instrument_finch" => true,
            "instrument_oban" => true,
            "instrument_tesla" => true,
            "log" => "file",
            "logging_endpoint" => "https://appsignal-endpoint.net",
            "report_oban_errors" => "all",
            "request_headers" => [
              "accept",
              "accept-charset",
              "accept-encoding",
              "accept-language",
              "cache-control",
              "connection",
              "content-length",
              "range"
            ],
            "send_environment_metadata" => true,
            "send_params" => true
          },
          "env" => {
            "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
            "diagnose_endpoint" => "http://localhost:4005/diag",
            "push_api_key" => "test"
          },
          "file" => {
            "name" => "DiagnoseTests",
            "enable_minutely_probes" => false
          },
          "system" => {
            "active" => true
          },
          "override" => {}
        }
      when :nodejs
        {
          "default" => {
            "active" => false,
            "ca_file_path" => ending_with("cert/cacert.pem"),
            "disable_default_instrumentations" => false,
            "dns_servers" => [],
            "enable_host_metrics" => true,
            "enable_minutely_probes" => true,
            "enable_nginx_metrics" => false,
            "enable_opentelemetry_http" => true,
            "enable_statsd" => false,
            "endpoint" => "https://push.appsignal.com",
            "env" => "development",
            "files_world_accessible" => true,
            "filter_parameters" => [],
            "filter_session_data" => [],
            "ignore_actions" => [],
            "ignore_errors" => [],
            "ignore_logs" => [],
            "ignore_namespaces" => [],
            "initialize_opentelemetry_sdk" => true,
            "log" => "file",
            "logging_endpoint" => "https://appsignal-endpoint.net",
            "opentelemetry_port" => "8099",
            "request_headers" => [
              "accept",
              "accept-charset",
              "accept-encoding",
              "accept-language",
              "cache-control",
              "connection",
              "content-length",
              "range"
            ],
            "send_environment_metadata" => true,
            "send_params" => true,
            "send_session_data" => true
          },
          "env" => {
            "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
            "enable_minutely_probes" => false,
            "push_api_key" => "test",
            "name" => "DiagnoseTests"
          },
          "initial" => {
            "active" => true,
            "log_level" => "debug",
            "name" => "DiagnoseTests"
          },
          "system" => {}
        }
      when :python
        {
          "default" => {
            "ca_file_path" => ending_with("resources/cacert.pem"),
            "diagnose_endpoint" => ending_with("diag"),
            "enable_host_metrics" => true,
            "enable_minutely_probes" => true,
            "enable_nginx_metrics" => false,
            "enable_statsd" => false,
            "environment" => "development",
            "endpoint" => "https://push.appsignal.com",
            "files_world_accessible" => true,
            "log" => "file",
            "log_level" => "info",
            "logging_endpoint" => "https://appsignal-endpoint.net",
            "opentelemetry_port" => 8099,
            "send_environment_metadata" => true,
            "send_params" => true,
            "send_session_data" => true,
            "request_headers" => [
              "accept",
              "accept-charset",
              "accept-encoding",
              "accept-language",
              "cache-control",
              "connection",
              "content-length",
              "range"
            ]
          },
          "system" => { "app_path" => ending_with("diagnose/python") },
          "initial" => { "name" => "DiagnoseTests" },
          "environment" => {
            "diagnose_endpoint" => ending_with("diag"),
            "enable_minutely_probes" => false,
            "endpoint" => ENV.fetch("APPSIGNAL_PUSH_API_ENDPOINT", nil),
            "environment" => "development",
            "name" => "DiagnoseTests",
            "push_api_key" => "test"
          }
        }
      else
        raise "No clause for runner #{@runner}"
      end
    expect_report_for(:config, :sources, expected_report_section)
  end

  it "prints the validation section" do
    expect_output_for(
      :validation,
      [
        "Validation",
        /  Validating Push API key: (\e\[32m)?valid(\e\[0m)?/
      ]
    )
  end

  it "submitted report contains validation section" do
    expect_report_for(
      :validation,
      "push_api_key" => "valid"
    )
  end

  it "validates the Push API key with the correct query params" do
    matchers =
      case @runner.type
      when :ruby
        {
          "gem_version" => VERSION_PATTERN
        }
      end

    expect(MockServer.last_auth_request.params).to match(
      {
        "api_key" => "test",
        "environment" => kind_of(String),
        "hostname" => be_empty.or(be_nil),
        "name" => "DiagnoseTests"
      }.merge(matchers || {})
    )
  end

  it "prints the paths section" do
    matchers = ["Paths"]

    if [:ruby, :python].include?(@runner.type)
      matchers += [
        /  (AppSignal gem path|Package install path)/,
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+\)/,
        ""
      ]
    end

    matchers += [
      %(  Current working directory),
      /    Path: #{quoted(PATH_PATTERN)}/,
      /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
      /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+/,
      ""
    ]

    if @runner.type == :ruby
      matchers += [
        %(  Root path),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+/,
        ""
      ]
    end

    matchers += [
      %(  Log directory),
      /    Path: #{quoted(PATH_PATTERN)}/,
      /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
      /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+/,
      ""
    ]

    if @runner.type == :nodejs
      matchers += [
        %(  AppSignal client file),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
        /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+/,
        ""
      ]
    end

    if @runner.type == :ruby
      matchers += [
        %(  Makefile install log),
        /    Path: #{quoted(PATH_PATTERN)}/,
        /    Exists\?: #{TRUE_OR_FALSE_PATTERN}/,
        ""
      ]
    end

    matchers += ([
      %(  AppSignal log),
      /    Path: #{quoted(PATH_PATTERN)}/,
      /    Writable\?: #{TRUE_OR_FALSE_PATTERN}/,
      /    Ownership\?: #{TRUE_OR_FALSE_PATTERN} \(file: (\w+:)?\d+, process: (\w+:)?\d+/,
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
      when :elixir
        default_paths
      when :nodejs
        default_paths.merge(
          "appsignal.cjs" => {
            "exists" => true,
            "mode" => kind_of(String),
            "ownership" => path_ownership(@runner.type),
            "path" => ending_with("/appsignal.cjs"),
            "type" => "file",
            "writable" => true
          }
        )
      when :python
        default_paths.merge(
          "package_install_path" => {
            "exists" => true,
            "mode" => kind_of(String),
            "ownership" => path_ownership(@runner.type),
            "path" => ending_with("python"),
            "type" => "directory",
            "writable" => true
          }
        )
      when :ruby
        default_paths.merge(
          "ext/mkmf.log" => {
            "exists" => false,
            "path" => ending_with("mkmf.log")
          },
          "package_install_path" => { # TODO: Add this to Elixir and Node.js as well
            "exists" => true,
            "mode" => kind_of(String),
            "ownership" => path_ownership(@runner.type),
            "path" => ending_with("ruby"),
            "type" => "directory",
            "writable" => true
          },
          "root_path" => { # TODO: Add this to Elixir and Node.js as well
            "exists" => true,
            "mode" => kind_of(String),
            "ownership" => path_ownership(@runner.type),
            "path" => @runner.directory,
            "type" => "directory",
            "writable" => true
          }
        )
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
    @received_report = MockServer.last_diagnose_report
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

RSpec.describe "Running the diagnose command with report submission error" do
  before(:all) do
    MockServer.auth_response_code = 200
    MockServer.diagnose_response_code = 500
    @runner = init_runner(:prompt => "y")
    @runner.run
    @received_report = MockServer.last_diagnose_report
  end

  it "prints an error about report submission" do
    send_report = section(:send_report)
    expect(send_report).to include(
      "  Error: Something went wrong while submitting the report to AppSignal.",
      "  Response code: 500",
      "  Response body:",
      "{\"error\":\"Internal server error\"}"
    )
  end
end

RSpec.describe "Running the diagnose command with the --send-report option" do
  before :all do
    MockServer.diagnose_response_code = 200
    @runner = init_runner(:args => ["--send-report"])
    @runner.run
    @received_report = MockServer.last_diagnose_report
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
    @received_report = MockServer.last_diagnose_report
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
    @received_report = MockServer.last_diagnose_report
  end

  it "prints handled errors instead of the report" do
    skip if @runner.type == :python

    matchers = ["Extension installation report"]
    case @runner.type
    when :ruby, :nodejs, :python
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
    skip if @runner.type == :python

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
        {
          "download_parsing_error" => { "error" => "enoent" },
          "installation_parsing_error" => { "error" => "enoent" }
        }
      else
        raise "No clause for runner #{@runner}"
      end
    expect_report_for(:installation, matchers)
  end
end

RSpec.describe "Running the diagnose command without Push API key" do
  before :all do
    MockServer.auth_response_code = 401
    MockServer.diagnose_response_code = 200
    @runner = init_runner(:push_api_key => "", :prompt => "y")
    @runner.run
    @received_report = MockServer.last_diagnose_report
  end

  it "receives the report without api_key query params" do
    matchers =
      case @runner.type
      when :ruby
        {
          "gem_version" => VERSION_PATTERN
        }
      end

    expect(@received_report.params).to match(
      {
        "api_key" => be_empty.or(be_nil),
        "environment" => kind_of(String),
        "hostname" => be_empty.or(be_nil),
        "name" => "DiagnoseTests"
      }.merge(matchers || {})
    )
  end

  it "prints agent diagnose section with errors" do
    expected_output = if @runner.type == :python
                        [
                          /Agent diagnostics/,
                          /  Agent tests/,
                          /    Started: started/,
                          /    Process user id: \d+/,
                          /    Process user group id: \d+/,
                          /    Configuration: invalid/,
                          /       Error: RequiredEnvVarNotPresent\("_APPSIGNAL_PUSH_API_KEY"\)/,
                          /    Logger: -/,
                          /    Working directory user id: -/,
                          /    Working directory user group id: -/,
                          /    Working directory permissions: -/,
                          /    Lock path: -/
                        ]
                      else
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
                      end

    expect_output_for(
      :agent,
      expected_output
    )
  end

  it "submitted report contains agent diagnostics errors" do
    skip if @runner.type == :python

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

  it "prints error about invalid Push API key" do
    validation = section(:validation)
    expect(validation).to match(/Validating Push API key: (\e\[31m)?invalid(\e\[0m)?/)
  end

  it "submitted report contains an invalid Push API key" do
    expect_report_for(
      :validation,
      "push_api_key" => "invalid"
    )
  end
end

RSpec.describe "Running the diagnose command with Push API key validation error" do
  before :all do
    MockServer.auth_response_code = 500
    MockServer.diagnose_response_code = 200
    @runner = init_runner(:push_api_key => "", :prompt => "y")
    @runner.run
    @received_report = MockServer.last_diagnose_report
  end

  it "prints error about an error validating Push API key" do
    validation = section(:validation)
    expect(validation)
      .to match(/Validating Push API key: (\e\[31m)?Failed to validate: .+(\e\[0m)?/)
  end

  it "submitted report contains an invalid Push API key" do
    expect_report_for(
      :validation,
      "push_api_key" => starting_with("Failed to validate: ")
    )
  end
end
