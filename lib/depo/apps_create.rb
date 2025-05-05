# frozen_string_literal: true

require 'tty-prompt'
require 'net/ssh'
require 'depo/utils/spinner'
require 'depo/utils/color'

module Depo
  class AppsCreate
    extend Depo::Utils::Spinner

    # Prompts for a valid hostname (not IP), SSH as root, creates user, installs asdf, Ruby, vhost, restarts caddy
    def self.run
      prompt = TTY::Prompt.new(interrupt: :exit)
      hostname = nil
      loop do
        hostname = prompt.ask("Enter a hostname (not an IP address):") do |q|
          q.required true
          q.validate(/^(?!\d+\.\d+\.\d+\.\d+$)(?!\d+:[^:]+:[^:]+:[^:]+:)[a-zA-Z0-9.-]+$/, "Must be a valid hostname, not an IP")
        end
        break if hostname && hostname !~ /^(\d+\.){3}\d+$/
        puts Depo::Utils::Color.red("Please enter a valid hostname (not an IP address)")
      end
      user = hostname.tr('-', '_')
      puts "\nConnecting to #{hostname} as root..."
      ssh = nil
      begin
        with_spinner("Connecting to #{hostname} as root...") do
          ssh = Net::SSH.start(hostname, 'root')
        end
        spinner_success("Connecting to #{hostname} as root...")
      rescue Net::SSH::AuthenticationFailed, Net::SSH::Exception => e
        spinner_fail("Connecting to #{hostname} as root...")
        puts Depo::Utils::Color.red("SSH connection failed: #{e.message}")
        puts Depo::Utils::Color.red("Aborting app creation.")
        return
      end

      # 3. Create user
      begin
        with_spinner("Creating user #{user}...") do
          user_create_result = ssh_exec!(ssh, "id -u #{user} || useradd -m #{user}")
          if user_create_result.nil? || user_create_result.include?("already exists")
            raise "User #{user} already exists or could not be created."
          end
        end
        spinner_success("Created user #{user}")
      rescue => e
        spinner_fail("Creating user #{user}...")
        puts Depo::Utils::Color.red("Failed to create user: #{e.message}")
        puts Depo::Utils::Color.red("Aborting app creation.")
        ssh.close if ssh
        return
      end

      # 4. Install asdf for user
      begin
        with_spinner("Installing asdf for #{user}...") do
          asdf_result = ssh_exec!(ssh, "su - #{user} -c 'git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0 || true'")
          bashrc_result = ssh_exec!(ssh, "su - #{user} -c 'echo \\n. $HOME/.asdf/asdf.sh >> ~/.bashrc'")
          if asdf_result.nil? || bashrc_result.nil?
            raise "asdf could not be installed for #{user}"
          end
        end
        spinner_success("asdf installed for #{user}")
      rescue => e
        spinner_fail("Installing asdf for #{user}...")
        puts Depo::Utils::Color.red("Failed to install asdf: #{e.message}")
        puts Depo::Utils::Color.red("Aborting app creation.")
        ssh.close if ssh
        return
      end

      # 5. Prompt for Ruby version
      ssh_exec!(ssh, "su - #{user} -c 'export ASDF_DIR=\"$HOME/.asdf\"; . $HOME/.asdf/asdf.sh; asdf plugin add ruby 2>/dev/null'")
      available_rubies = ssh_exec!(ssh, "su - #{user} -c 'export ASDF_DIR=\"$HOME/.asdf\"; . $HOME/.asdf/asdf.sh; asdf list-all ruby'").split("\n").map(&:strip).reject(&:empty?)
      filtered_rubies = available_rubies.select { |v| v.match?(/^(2|3)\.\d+(\.\d+)*$/) }
      ruby_version = prompt.select("Select Ruby version to install:", filtered_rubies.reverse, default: 1, per_page: 10, help: "")

      # 6. Install Ruby
      begin
        with_spinner("Installing Ruby #{ruby_version} for #{user}...") do
          ruby_result = ssh_exec!(ssh, "su - #{user} -c 'export ASDF_DIR=\"$HOME/.asdf\"; . $HOME/.asdf/asdf.sh; asdf install ruby #{ruby_version} && asdf global ruby #{ruby_version}'")
          if ruby_result.nil?
            raise "Ruby #{ruby_version} could not be installed for #{user}"
          end
        end
        spinner_success("Ruby #{ruby_version} installed for #{user}")
      rescue => e
        spinner_fail("Installing Ruby #{ruby_version} for #{user}...")
        puts Depo::Utils::Color.red("Failed to install Ruby: #{e.message}")
        puts Depo::Utils::Color.red("Aborting app creation.")
        ssh.close if ssh
        return
      end

      # 7. Create vhost
      vhost_path = "/var/lib/depo/vhosts/#{hostname}.caddy"
      vhost_content = "#{hostname} {\n  respond \"<h1>#{hostname}</h1>\"\n}"
      begin
        with_spinner("Creating vhost for #{hostname}...") do
          vhost_exists = ssh_exec!(ssh, "test -f #{vhost_path} && echo exists || echo not_exists").strip == "exists"
          if vhost_exists
            raise "Vhost file already exists at #{vhost_path}"
          end
          vhost_result = ssh_exec!(ssh, "echo '#{vhost_content.gsub("'", "'\\''").gsub("\n", "'\\n'")}' > #{vhost_path}")
          if vhost_result.nil?
            raise "Failed to create vhost at #{vhost_path}"
          end
        end
        spinner_success("Vhost created at #{vhost_path}")
      rescue => e
        spinner_fail("Creating vhost for #{hostname}...")
        puts Depo::Utils::Color.red("Failed to create vhost: #{e.message}")
        puts Depo::Utils::Color.red("Aborting app creation.")
        ssh.close if ssh
        return
      end

      # 8. Restart caddy
      begin
        with_spinner("Restarting caddy...") do
          caddy_result = ssh_exec!(ssh, "systemctl restart caddy")
          if caddy_result.nil?
            raise "Failed to restart caddy"
          end
        end
        spinner_success("Caddy restarted and SSL will be provisioned for #{hostname}")
      rescue => e
        spinner_fail("Restarting caddy...")
        puts Depo::Utils::Color.red("Failed to restart caddy: #{e.message}")
        puts Depo::Utils::Color.red("Aborting app creation.")
        ssh.close if ssh
        return
      end

      puts Depo::Utils::Color.green("\nApp setup complete! Visit https://#{hostname}/ to verify.")
      ssh.close
    rescue Net::SSH::AuthenticationFailed, Net::SSH::Exception => e
      spinner_fail("Connecting to #{hostname} as root...")
      puts Depo::Utils::Color.red("SSH connection failed: #{e.message}")
    rescue => e
      puts Depo::Utils::Color.red("Error: #{e.message}")
      puts e.backtrace.join("\n")
    end

    # Reuse ssh_exec! from Depo::Apps
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
  end
end
