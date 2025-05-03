# frozen_string_literal: true

module Depo
  module Utils
    module Spinner
      def with_spinner(msg)
        spinner = %w[| / - \\]
        running = true
        t = Thread.new do
          i = 0
          while running
            print "\r#{msg} #{spinner[i % spinner.length]}"
            sleep 0.1
            i += 1
          end
        end
        result = yield
        running = false
        t.join
        result
      end

      def spinner_success(msg)
        puts "\r\e[2K\e[1G#{Depo::Utils::Color::green('✔')} #{msg}"
      end

      def spinner_fail(msg)
        puts "\r\e[2K\e[1G#{Depo::Utils::Color::red('✘')} #{msg}"
      end
    end
  end
end
