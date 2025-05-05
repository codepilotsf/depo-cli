# frozen_string_literal: true

require 'depo/utils/color'
require 'net/ssh'
require 'yaml'
require 'pathname'

module Depo
  module Up
    extend Depo::Utils::Color

    def self.run(verbose: false)
      config_path = nil
      Pathname.pwd.ascend do |dir|
        candidate = dir + 'config/depo.yml'
        if candidate.exist?
          config_path = candidate.to_s
          break
        end
      end
      unless config_path
        puts red('config/depo.yml not found in this directory or any parent directory.')
        exit 1
      end
      config = YAML.load_file(config_path)
      unless config['host'] && config['user']
        puts red('config/depo.yml must contain both host and user properties.')
        exit 1
      end
      puts green('config/depo.yml found and valid.')
      # Future: rsync/upload logic here
    end
  end
end
