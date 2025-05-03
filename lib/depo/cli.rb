# frozen_string_literal: true

module Depo
  class CLI
    require 'net/ssh'

    def self.start(args)
      verbose = args.include?('-v') || args.include?('--verbose')
      case args.first
      when 'test'
        puts 'Test successful'
      when 'setup'
        run_setup(verbose: verbose)
      else
        puts 'Unknown command'
        exit 1
      end
    end

    def self.run_setup(verbose: false)
      puts ""
      print green('Hostname or IP address of remote server? ')
      host = STDIN.gets.strip
      user = 'root'
      steps = [
        {name: 'Installing rbenv', cmd: install_rbenv_commands},
        {name: 'Installing Ruby', cmd: install_rbenv_ruby_commands},
        {name: 'Installing Puma', cmd: install_puma_commands},
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

      begin
        # Pre-checks
        check_abort(ssh, "pgrep -f 'nginx|apache|caddy'", 'Web server')
        check_abort(ssh, "pgrep -f puma", 'Puma')
        check_abort(ssh, "command -v asdf", 'asdf')

        steps.each do |step|
          run_step(step[:name], on_success: ->(msg) { green(msg) }, on_fail: ->(msg) { red(msg) }, verbose: verbose) do
            run_remote_commands(ssh, step[:cmd], verbose: verbose)
          end
        end
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

    def self.install_rbenv_commands
      [
        'apt update',
        'apt install -y git curl build-essential libssl-dev libreadline-dev zlib1g-dev libffi-dev libyaml-dev',
        'git clone https://github.com/rbenv/rbenv.git ~/.rbenv',
        'echo "export PATH=\"$HOME/.rbenv/bin:$PATH\"" >> ~/.profile',
        'echo \'eval "$(rbenv init -)"\' >> ~/.profile',
        'git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build',
        'export PATH="$HOME/.rbenv/bin:$PATH"',
        'eval "$(~/.rbenv/bin/rbenv init -)"'
      ]
    end

    def self.install_rbenv_ruby_commands
      [
        '~/.rbenv/bin/rbenv install $(~/.rbenv/bin/rbenv install -l | grep -v - | tail -1)',
        '~/.rbenv/bin/rbenv global $(~/.rbenv/bin/rbenv install -l | grep -v - | tail -1)',
        '~/.rbenv/bin/rbenv rehash'
      ]
    end

    def self.install_puma_commands
      [
        'gem install puma'
      ]
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
