# frozen_string_literal: true

module OutputHelper
  def section(key)
    @runner.output.section(key)
  end

  def expect_output_for(section_key, expected)
    actual_section = section(section_key)
    section_lines = actual_section.split("\n")
    unless section_lines.length == expected.length
      raise "Not enough expectations given to `expect_section` for section `#{section_key}`. " \
        "Actual: #{section_lines.length} lines. Expected: #{expected.length} lines. " \
        "Actual contents:\n#{actual_section}\n\nExpectations:\n#{expected.join("\n")}"
    end

    section_lines.zip(expected).each do |actual_line, expectation|
      case expectation
      when Regexp
        expect(actual_line).to match(expectation), @runner.output.to_s
      else
        expect(actual_line).to eq(expectation), @runner.output.to_s
      end
    end
  end

  def quoted(string)
    quote = /['"]/
    /#{quote}#{string}#{quote}/
  end
end
