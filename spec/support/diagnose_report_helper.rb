# frozen_string_literal: true

module DiagnoseReportHelper
  def expect_report_for(*section_keys, expected)
    unless @received_report
      raise "expect_report_for: No @received_report found, is `#{@received_report.inspect}`"
    end

    section = @received_report.section(*section_keys)

    expect(section).to match(expected)
  end

  def path_ownership(runner_type)
    {
      "gid" => kind_of(Numeric),
      "uid" => kind_of(Numeric)
    }.tap do |hash|
      if runner_type == :ruby
        hash["group"] = kind_of(String)
        hash["user"] = kind_of(String)
      end
    end
  end
end
