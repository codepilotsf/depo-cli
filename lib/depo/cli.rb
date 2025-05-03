# frozen_string_literal: true

require 'depo/apps'
require 'depo/utils/color'

module Depo
  class CLI
    require 'net/ssh'
    prepend Depo::Utils::Color

    def self.start(args)
      verbose = args.include?('-v') || args.include?('--verbose')
      case args.first
      when 'setup'
        run_setup(verbose: verbose)
      when 'up'
        run_up(verbose: verbose)
      when 'apps'
        Depo::Apps.run
      else
        puts 'Unknown command'
        exit 1
      end
    end

    def self.run_up(verbose: false)
      require 'yaml'
      require 'pathname'
      # 1. Search for config/depo.yml in current dir or ancestors
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

    def self.run_setup(verbose: false)
      puts ""
      print green('Hostname or IP address of remote server? ')
      host = STDIN.gets.strip
      user = 'root'
      steps = [
        {name: 'Installing Caddy', cmd: install_caddy_commands},
        {name: 'Starting services', cmd: start_services_commands}
      ]

      puts "\n"
      ssh = nil
      run_step('Connecting', on_success: ->(msg) { green(msg) }, on_fail: ->(msg) { red(msg) }) do
        begin
          ssh = Net::SSH.start(host, user)
        rescue Net::SSH::AuthenticationFailed, Net::SSH::Exception => e
          raise "SSH connection failed: #{e.message}"
        end
      end
      return unless ssh

      # Write login warning message to /etc/motd (plain text, no ANSI codes)
      motd_warning = "WARNING! This server is managed by depo-cli (https://rubygems.org/gems/depo-cli). Manually administration of this server may cause unexpected behavior when using the `depo` command line tool to manage the server. Please proceed with caution."
      ssh_exec!(ssh, "echo '#{motd_warning}' > /etc/motd")

      begin
        # Ensure /var/lib/depo/ and subdirectories exist and are properly permissioned
        ssh_exec!(ssh, "mkdir -p /var/lib/depo/keys /var/lib/depo/vhosts")
        ssh_exec!(ssh, "chown root:root /var/lib/depo /var/lib/depo/keys /var/lib/depo/vhosts")
        ssh_exec!(ssh, "chmod 1777 /var/lib/depo /var/lib/depo/keys /var/lib/depo/vhosts")

        # Pre-checks
        check_abort(ssh, "pgrep -f 'nginx|apache|caddy'", 'Web server')

        steps.each do |step|
          run_step(step[:name], on_success: ->(msg) { green(msg) }, on_fail: ->(msg) { red(msg) }, verbose: verbose) do
            run_remote_commands(ssh, step[:cmd], verbose: verbose)
          end
        end

        # Write a Caddyfile that includes all vhosts
        caddyfile_content = "# Managed by depo-cli\ninclude /var/lib/depo/vhosts/*.caddy\n"
        ssh_exec!(ssh, "echo '#{caddyfile_content.gsub("'", "'\\''").gsub("\n", "'\\n'")}' > /etc/caddy/Caddyfile")

        ssh.close
        puts "\nFinished."
      rescue => e
        puts red(e.message)
        puts
        exit 1
      end
    end

    def self.green(str)
      "\e[38;5;42m#{str}\e[0m" # Medium light green (ANSI 256-color code 42)
    end

    def self.red(str)
      "\e[31m#{str}\e[0m" # Red
    end

    def self.run_step(name, on_success:, on_fail:, verbose: false)
      if verbose
        begin
          result = yield
          if result
            puts green("✔ #{on_success.call(name)}")
            true
          else
            puts red("#{on_fail.call(name)} failed")
            puts
            exit 1
          end
        rescue => e
          puts red(e.message.to_s)
          puts
          exit 1
        end
      else
        spinner_running = true
        spinner_thread = Thread.new do
          spinner = %w[| / - \\]
          i = 0
          while spinner_running
            print "\r#{spinner[i % spinner.length]} #{name}"
            sleep 0.1
            i += 1
          end
        end
        begin
          result = yield
          spinner_running = false
          spinner_thread.join
          if result
            puts "\r\e[2K\e[1G\e[32m\u2714\e[0m #{on_success.call(name)}"
            true
          else
            puts "\r\e[2K\e[1G" + red("#{on_fail.call(name)} failed")
            puts
            exit 1
          end
        rescue => e
          spinner_running = false
          spinner_thread.join
          puts "\r\e[2K\e[1G" + red(e.message.to_s)
          puts
          exit 1
        end
      end
    end

    def self.spin(msg)
      spinner = %w[| / - \\]
      i = 0
      while true
        print "\r#{spinner[i % spinner.length]} #{msg}"
        sleep 0.1
        i += 1
      end
    end

    def self.check_abort(ssh, cmd, name)
      result = ssh_exec!(ssh, cmd)
      if !result.strip.empty?
        raise "#{name} detected on server. Aborting."
      end
    end

    def self.run_remote_commands(ssh, cmds, verbose: false)
      Array(cmds).all? { |cmd| ssh_exec!(ssh, cmd, verbose: verbose) }
    end

    def self.ssh_exec!(ssh, command, verbose: false)
      output = ""
      ssh.open_channel do |channel|
        channel.exec(command) do |_ch, success|
          unless success
            return nil
          end
          channel.on_data do |_ch, data|
            output += data
            puts data if verbose
          end
          channel.on_extended_data do |_ch, _type, data|
            output += data
            puts data if verbose
          end
        end
      end
      ssh.loop
      output
    end

    def self.install_caddy_commands
      [
        'apt install -y debian-keyring debian-archive-keyring apt-transport-https',
        'curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" | apt-key add -',
        'curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" | tee /etc/apt/sources.list.d/caddy-stable.list',
        'apt update',
        'apt install -y caddy'
      ]
    end

    def self.start_services_commands
      [
        'systemctl start caddy',
        'systemctl enable caddy'
      ]
    end
  end
end
