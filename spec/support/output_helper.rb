# frozen_string_literal: true

module OutputHelper
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
