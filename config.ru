require 'sinatra'
require 'digest/md5'
require_relative 'genkai'

run Genkai::Application
