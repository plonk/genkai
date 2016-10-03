# frozen_string_literal: true
require 'sinatra'
require 'digest/md5'
require_relative 'genkai'

run Genkai::Application
