# frozen_string_literal: true

require 'depo/utils/color'
require 'net/ssh'

module Depo
  module Setup
    extend Depo::Utils::Color

    def self.run(verbose: false)
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

      motd_warning = "WARNING! This server is managed by depo-cli (https://rubygems.org/gems/depo-cli). Manually administration of this server may cause unexpected behavior when using the `depo` command line tool to manage the server. Please proceed with caution."
      ssh_exec!(ssh, "echo '#{motd_warning}' > /etc/motd")

      begin
        ssh_exec!(ssh, "mkdir -p /var/lib/depo/keys /var/lib/depo/vhosts")
        ssh_exec!(ssh, "chown root:root /var/lib/depo /var/lib/depo/keys /var/lib/depo/vhosts")
        ssh_exec!(ssh, "chmod 1777 /var/lib/depo /var/lib/depo/keys /var/lib/depo/vhosts")
        check_abort(ssh, "pgrep -f 'nginx|apache|caddy'", 'Web server')
        steps.each do |step|
          run_step(step[:name], on_success: ->(msg) { green(msg) }, on_fail: ->(msg) { red(msg) }, verbose: verbose) do
            run_remote_commands(ssh, step[:cmd], verbose: verbose)
          end
        end
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

    def self.check_abort(ssh, cmd, name)
      result = ssh_exec!(ssh, cmd)
      if !result.strip.empty?
        raise "#{name} detected on server. Aborting."
      end
    end

    def self.run_remote_commands(ssh, cmds, verbose: false)
      Array(cmds).all? { |cmd| ssh_exec!(ssh, cmd, verbose: verbose) }
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
