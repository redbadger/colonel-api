require './app'
require 'rack/test'
require 'simplecov'

SimpleCov.start

ENV['RACK_ENV'] = 'test'
