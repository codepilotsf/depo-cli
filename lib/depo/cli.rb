# frozen_string_literal: true

require_relative 'setup'
require_relative 'apps'
require_relative 'up'
require_relative 'utils/color'
require 'net/ssh'

module Depo
  class CLI
    prepend Depo::Utils::Color

    def self.start(args)
      verbose = args.include?('-v') || args.include?('--verbose')
      case args.first
      when 'setup'
        Depo::Setup.run(verbose: verbose)
      when 'up'
        Depo::Up.run(verbose: verbose)
      when 'apps'
        Depo::Apps.run
      else
        puts 'Unknown command'
        exit 1
      end
    end
  end
end
