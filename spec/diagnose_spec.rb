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
    line = @read.readline

    if ignored_lines.include? line
      readline
    else
      line
    end
  end

  def stop
    Process.kill(3, @pid)
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
    []
  end

  def language_name
    'Ruby'
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
      "==> appsignal\n",
      "AppSignal extension installation successful\n"
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
      "WARNING: Error when reading appsignal config, appsignal (as 501/20) not starting: Required environment variable '_APPSIGNAL_PUSH_API_KEY' not present\n"
    ]
  end

  def language_name
    'Node.js'
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
      %r(  (Gem|Package) version: \d+\.\d+\.\d+),
      %r(  Agent version: \w{6}),
      %r(  (Extension|Nif) loaded: yes)
    ])
  end

  after(:all) do
    @runner.stop
  end

  def expect_output(expected)
    expected.each do |line|
      expect(@runner.readline).to match(line)
    end
  end

  def expect_newline
    expect(@runner.readline).to match("\n")
  end
end
