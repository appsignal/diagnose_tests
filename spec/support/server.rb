# frozen_string_literal: true

require "sinatra/base"

class DiagnoseReport
  attr_reader :params

  def initialize(params: {}, report: {})
    @params = params
    @report = report
  end

  def section(*keys)
    @report.dig(*keys.map(&:to_s)).tap do |section|
      raise "No `#{keys}` keys found in the DiagnoseReport" if section.nil?
    end
  end

  def to_h
    @report
  end
end

class DiagnoseServer < Sinatra::Base
  class << self
    def run!(port)
      @mutex = Mutex.new
      @received_requests = []
      super(:port => port)
    end

    def track_request(request)
      @mutex.synchronize do
        @received_requests << request
      end
    end

    def last_received_report
      @mutex.synchronize do
        request = @received_requests.last
        if request
          DiagnoseReport.new(
            :params => request.params,
            :report => JSON.parse(request.body.read)["diagnose"]
          )
        end
      end
    end

    def clear!
      @mutex.synchronize do
        @received_requests.clear
      end
    end
  end

  set :logging, false

  post "/diag" do
    DiagnoseServer.track_request(request)
    status 200
    JSON.dump({ :token => "diag_support_token" })
  end
end
