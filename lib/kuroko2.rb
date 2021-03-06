require 'chrono'
require 'addressable'
require 'aws-sdk'
require 'retryable'
require 'faraday'
require 'html/pipeline'

require "kuroko2/engine"
require "kuroko2/configuration"

module Kuroko2
  class << self
    def logger
      @logger ||= defined?(Rails) && Rails.env.test? ? Rails.logger : Kuroko2::Util::Logger.new($stdout)
    end

    def logger=(logger)
      @logger = logger
    end

    def config
      Configuration.config
    end
  end
end
