# frozen_string_literal: true

require "json"

module RailsDoctor
  module Reporters
    class Json
      def initialize(result, include_raw: false)
        @result = result
        @include_raw = include_raw
      end

      def render
        JSON.pretty_generate(@result.to_h(include_raw: @include_raw)) + "\n"
      end
    end
  end
end
