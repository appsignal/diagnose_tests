RSpec.describe "Diagnose" do
  before do
    gemfile = File.join(__dir__, "../ruby/Gemfile")
    command = "bundle exec --gemfile='#{gemfile}' appsignal diagnose"
    puts command

    @read, write = IO.pipe
    @pid = spawn(command, out: write)
  end

  it "prints the diagnose header" do
    expect(next_line).to match(/AppSignal diagnose/)
    expect(next_line).to match(/================================================================================/)
    expect(next_line).to match(/Use this information to debug your configuration./)

    expect(next_line).to match(/More information is available on the documentation site./)
    expect(next_line).to match(%r(https://docs.appsignal.com/))
    expect(next_line).to match(%r(Send this output to support@appsignal.com if you need help.))
    expect(next_line).to match(/================================================================================/)
  end

  after do
    Process.kill(3, @pid)
    @read.close
  end

  def next_line
    begin
      @read.readline
    rescue IOError
    end
  end
end
