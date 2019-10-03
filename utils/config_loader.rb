module Utils
  class << self
    attr_accessor :config_loader
  end

  module ENV
    CLIENT = 'client'
    SERVER = 'server'
  end

  class ConfigLoader
    attr_reader :config

    def initialize(environment, config_file_path = nil)
      @config = YAML.load_file('./default.config.yml')[environment]
      unless config_file_path.nil?
        if (user_config_file = YAML.load_file(config_file_path))
          user_config = user_config_file[environment]
          @config = @config.merge(user_config) unless user_config.nil?
        end
      end
    end
  end

end
