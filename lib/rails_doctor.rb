# frozen_string_literal: true

require_relative "rails_doctor/version"

module RailsDoctor
  Error = Class.new(StandardError)
end

require_relative "rails_doctor/config"
require_relative "rails_doctor/models"
require_relative "rails_doctor/command_runner"
require_relative "rails_doctor/project"
require_relative "rails_doctor/scanner"
require_relative "rails_doctor/scorer"
require_relative "rails_doctor/cli"
