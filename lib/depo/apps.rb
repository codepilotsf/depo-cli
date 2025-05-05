# frozen_string_literal: true

require 'io/console'
require 'pathname'
require 'depo/utils/color'
require 'tty-prompt'
require 'depo/utils/spinner'
require_relative 'apps_create'

module Depo
  class Apps
    extend Depo::Utils::Spinner
    # Display a beautiful CLI to select or create apps
    def self.run
      require 'yaml'
      require 'net/ssh'
      require 'io/console'
      require 'pathname'

      # 1. Try to find config/depo.yml in current dir or ancestors
      config_path = nil
      Pathname.pwd.ascend do |dir|
        candidate = dir + 'config/depo.yml'
        if candidate.exist?
          config_path = candidate.to_s
          break
        end
      end
      config = config_path ? YAML.load_file(config_path) : {}
      host = config['host']
      user = 'root'

      unless host
        puts "\n"
        print Depo::Utils::Color.green('Remote host: ')
        host = STDIN.gets.strip
      end

      begin
        ssh = nil
        puts "\n"
        with_spinner("Connecting to #{host} as #{user}...") do
          ssh = Net::SSH.start(host, user)
        end
        spinner_success("Connecting to #{host} as #{user}...")
        vhosts_dir = '/var/lib/depo/vhosts'
        files = ssh_exec!(ssh, "ls -1t #{vhosts_dir}/*.caddy 2>/dev/null || true").split("\n").reject(&:empty?)
        app_names = files.map { |f| File.basename(f, '.caddy') }
        show_menu(app_names)
      rescue Net::SSH::AuthenticationFailed, Net::SSH::Exception => e
        spinner_fail("Connecting to #{host} as #{user}...")
        puts red("SSH connection failed: #{e.message}")
        exit 1
      end
    end

    def self.ssh_exec!(ssh, command)
      output = ""
      ssh.open_channel do |channel|
        channel.exec(command) do |_ch, success|
          unless success
            return nil
          end
          channel.on_data do |_ch, data|
            output += data
          end
          channel.on_extended_data do |_ch, _type, data|
            output += data
          end
        end
      end
      ssh.loop
      output
    end

    def self.show_menu(app_names)
      prompt = TTY::Prompt.new(interrupt: :exit)
      puts "\n\e[1mDepo Apps\e[22m"
      puts "----------------------"
      choices = []
      choices << { name: 'Create New App', value: :create }
      choices += app_names if app_names.any?
      # Navigation hint with cancel info
      puts "\e[90m(Press ↑/↓ arrow to move, Enter to select, Ctrl+C to cancel)\e[0m"
      selection = prompt.select(nil, choices, per_page: 15, cycle: true, help: "")
      case selection
      when :create
        puts "\n[Create New App selected]"
        Depo::AppsCreate.run
      else
        puts "\n[Selected app: #{selection}]"
        # Future: trigger app management flow
      end
    end

  end
end
