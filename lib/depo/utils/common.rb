# frozen_string_literal: true

require_relative 'spinner'

module Depo
  module Utils
    module Common
      def run_step(name, on_success:, on_fail:, verbose: false, &block)
        if verbose
          begin
            result = yield
            if result
              puts Depo::Utils::Color.green("✔ #{on_success.call(name)}")
              true
            else
              puts Depo::Utils::Color.red("#{on_fail.call(name)} failed")
              puts
              exit 1
            end
          rescue => e
            puts Depo::Utils::Color.red(e.message.to_s)
            puts
            exit 1
          end
        else
          result = Depo::Utils::Spinner.with_spinner(name) { yield }
          if result
            puts "\r\e[2K\e[1G\e[32m\u2714\e[0m #{on_success.call(name)}"
            true
          else
            puts "\r\e[2K\e[1G" + Depo::Utils::Color.red("#{on_fail.call(name)} failed")
            puts
            exit 1
          end
        end
      end

      def check_abort(ssh, cmd, name)
        result = ssh_exec!(ssh, cmd)
        if !result.strip.empty?
          raise "#{name} detected on server. Aborting."
        end
      end

      def run_remote_commands(ssh, cmds, verbose: false)
        Array(cmds).all? { |cmd| ssh_exec!(ssh, cmd, verbose: verbose) }
      end

      def ssh_exec!(ssh, command, verbose: false)
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
    end
  end
end
