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
    "bundle exec appsignal diagnose"
  end

  def ignored_lines
    []
  end
end

class Runner::Elixir < Runner
  def directory
    File.join(__dir__, "../elixir")
  end

  def setup_command
    "mix do deps.get, compile"
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
end

RSpec.describe "Diagnose" do
  before do
    language = ENV['LANGUAGE'] || 'ruby'
    @runner = {
      'ruby' => Runner::Ruby.new(),
      'elixir' => Runner::Elixir.new()
    }[language]

    @runner.run()
  end

  it "prints the diagnose header" do
    expect(@runner.readline).to match(/AppSignal diagnose/)
    expect(@runner.readline).to match(/================================================================================/)
    expect(@runner.readline).to match(/Use this information to debug your configuration./)

    expect(@runner.readline).to match(/More information is available on the documentation site./)
    expect(@runner.readline).to match(%r(https://docs.appsignal.com/))
    expect(@runner.readline).to match(%r(Send this output to support@appsignal.com if you need help.))
    expect(@runner.readline).to match(/================================================================================/)
  end

  after do
    @runner.stop
  end
end
