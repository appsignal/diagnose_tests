class Runner
  def initialize
    @read, @write = IO.pipe
  end

  def run
    Dir.chdir(directory)
    @pid = spawn(run_command, out: @write)
  end

  def readline
    @read.readline
  end

  def stop
    Process.kill(3, @pid)
  end
end

class Runner::Ruby < Runner
  def directory
    File.join(__dir__, "../ruby")
  end

  def run_command
    "bundle exec appsignal diagnose"
  end
end

RSpec.describe "Diagnose" do
  before do
    @runner = Runner::Ruby.new()
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
