require 'net/http'
require 'timeout'
require 'json'

class Peercast
  RPC_TIMEOUT = 2

  class Unavailable < StandardError
    attr_accessor :host, :port, :message

    def initialize(host, port, message)
      @host, @port, @message = host, port, message
    end
  end

  class << self
    attr_accessor :logger
  end

  attr_reader :host, :port, :opts

  def initialize(host, port, opts = {})
    @host = host
    @port = port
    @opts = opts
  end

  def method_missing(*_args, &block)
    name, *args = _args
    value = nil
    span = time do
      Timeout.timeout(RPC_TIMEOUT) do
        uri = URI("http://#{@host}:#{@port}/api/1")
        req = Net::HTTP::Post.new(uri, @opts)
        str = JSON.dump({ "jsonrpc" => "2.0",
                          "method" => name,
                          "params" => args,
                          "id" => 1 })
p str
        req.body = str
        req.content_type = "application/json"
        res = Net::HTTP.start(@host, @port) do |http|
          http.request(req)
        end
        if res.code != "200"
          fail "status #{res.code}"
        end
p res.body
p res.body.encoding
        json = JSON.parse(res.body)
p json
        if json['error']
          raise json['error']['message']
        end
        value = json['result']
      end
    end
    Peercast.logger&.info("%s:%d: %s: %d usec elapsed" % [@host, @port, name, span*1000*1000])
    value
  rescue Errno::ECONNREFUSED, Timeout::Error => e
    raise Unavailable.new(host, port, e.message)
  end

  private

  def time(&block)
    start = Time.now
    block.call
    Time.now - start
  end
end
