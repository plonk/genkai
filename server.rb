require 'sinatra/base'
require 'webrick'
require_relative 'genkai'

app = Genkai::Application.new
srv = WEBrick::HTTPServer.new({ :DocumentRoot => './',
                                :BindAddress => '0.0.0.0',
                                :Port => 8080})
srv.mount('/', Rack::Handler::WEBrick, app)
trap("INT"){ srv.shutdown }
srv.start
