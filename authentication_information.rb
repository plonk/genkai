require_relative 'extensions'

module Genkai
  class AuthenticationInformation < Struct.new(:id, :password)
    # 1〜30文字の印字可能文字。
    class << self
      def valid_password?(string)
        (string =~ /\A [\x20-\x7e]{1,30} \z/x).true?
      end
    end
  end
end
