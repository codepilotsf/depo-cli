# frozen_string_literal: true

module Depo
  module Utils
    module Color
      def self.green(str)
        "\e[38;5;42m#{str}\e[0m" # Medium light green (ANSI 256-color code 42)
      end

      def self.red(str)
        "\e[31m#{str}\e[0m"
      end
    end
  end
end
