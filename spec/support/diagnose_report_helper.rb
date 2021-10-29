# frozen_string_literal: true

module DiagnoseReportHelper
  def expect_report_for(section_key, expected)
    unless @received_report
      raise "expect_report_for: No @received_report found, is `#{@received_report.inspect}`"
    end

    section = @received_report.section(section_key.to_s)
    expect(section).to match(expected)
  end
end
