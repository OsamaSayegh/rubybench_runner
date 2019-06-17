# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'yaml'
require 'fileutils'
require 'tmpdir'
require 'ostruct'
require 'open3'

require 'rubybench_runner/version'
require 'rubybench_runner/dependencies_checker'
require 'rubybench_runner/configurations'
require 'rubybench_runner/base_runner'
require 'rubybench_runner/rails_runner'

module RubybenchRunner
  SUPPORTED_REPOS = {
    rails: RailsRunner
  }
end
