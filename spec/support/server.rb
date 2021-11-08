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

class MockServer < Sinatra::Base
  class << self
    def run!(port)
      @mutex = Mutex.new
      @auth_response_code = 200
      @received_auth_requests = []
      @received_diagnose_requests = []
      super(:port => port)
    end

    def track_diagnose_request(request)
      @mutex.synchronize do
        @received_diagnose_requests << request
      end
    end

    def last_diagnose_report
      @mutex.synchronize do
        request = @received_diagnose_requests.last
        if request
          DiagnoseReport.new(
            :params => request.params,
            :report => JSON.parse(request.body.read)["diagnose"]
          )
        end
      end
    end

    def track_auth_request(request)
      @mutex.synchronize do
        @received_auth_requests << request
      end
    end

    def last_auth_request
      @mutex.synchronize do
        @received_auth_requests.last
      end
    end

    def auth_response_code
      @mutex.synchronize do
        @auth_response_code
      end
    end

    def auth_response_code=(code)
      @mutex.synchronize do
        @auth_response_code = code
      end
    end

    def clear!
      @mutex.synchronize do
        @auth_response_code = 200
        @received_auth_requests.clear
        @received_diagnose_requests.clear
      end
    end
  end

  set :logging, false

  post "/diag" do
    MockServer.track_diagnose_request(request)
    status 200
    JSON.dump({ :token => "diag_support_token" })
  end

  post "/1/auth" do
    MockServer.track_auth_request(request)
    status MockServer.auth_response_code
  end
end
