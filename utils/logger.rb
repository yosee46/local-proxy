require 'logger'

module Utils
  class << self
    attr_accessor :log
  end

  class Logger
    def initialize
      @log = ::Logger.new(STDOUT)
      @log_file = ::Logger.new(Utils.config_loader.config['log_file_path'])

      log_level = Utils.config_loader.config['log_level']
      unless log_level.nil?
        case log_level
        when 'debug'
          @log.level = ::Logger::DEBUG
          @log_file.level = ::Logger::DEBUG
        when 'info'
          @log.level = ::Logger::INFO
          @log_file.level = ::Logger::INFO
        when 'warn'
          @log.level = ::Logger::WARN
          @log_file.level = ::Logger::WARN
        when 'error'
          @log.level = ::Logger::ERROR
          @log_file.level = ::Logger::ERROR
        end
      end
    end

    def debug(message)
      @log.debug(message)
    end

    def info (message)
      @log_file.info(message)
      @log.info(message)
    end

    def warn(message)
      @log_file.info(message)
      @log.info(message)
    end

    def error (message)
      @log_file.info(message)
      @log.info(message)
    end
  end

end
