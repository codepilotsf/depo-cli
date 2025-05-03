# frozen_string_literal: true

module Depo
  class CLI
    require 'net/ssh'

    def self.start(args)
      case args.first
      when 'test'
        puts 'Test successful'
      when 'setup'
        run_setup
      else
        puts 'Unknown command'
        exit 1
      end
    end

    def self.run_setup
      puts ""
      print green('Hostname or IP address of remote server? ')
      host = STDIN.gets.strip
      user = 'root'
      steps = [
        {name: 'Installing asdf', cmd: install_asdf_commands},
        {name: 'Installing Ruby', cmd: install_ruby_commands},
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
          run_step(step[:name], on_success: ->(msg) { green(msg) }, on_fail: ->(msg) { red(msg) }) do
            run_remote_commands(ssh, step[:cmd])
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

    def self.run_step(name, on_success:, on_fail:)
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

    def self.run_remote_commands(ssh, cmds)
      Array(cmds).all? { |cmd| ssh_exec!(ssh, cmd) }
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

    def self.install_asdf_commands
      [
        'apt update',
        'apt install -y git curl',
        'git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.13.1',
        'echo ". $HOME/.asdf/asdf.sh" >> ~/.bashrc',
        'echo ". $HOME/.asdf/completions/asdf.bash" >> ~/.bashrc',
        'export PATH="$HOME/.asdf/bin:$PATH"'
      ]
    end

    def self.install_ruby_commands
      [
        '. $HOME/.asdf/asdf.sh',
        'asdf plugin-add ruby || true',
        'asdf install ruby latest',
        'asdf global ruby $(asdf latest ruby)'
      ]
    end

    def self.install_puma_commands
      [
        '. $HOME/.asdf/asdf.sh',
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
