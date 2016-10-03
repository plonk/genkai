# frozen_string_literal: true
module Genkai
  # DATファイルの一行で表わされるレスを表わすクラス。
  class Post
    class << self
      def from_line(str)
        new(*str.chomp.split('<>', 5))
      end
    end

    attr_reader :name, :mail, :body, :date, :subject

    def initialize(name, mail, date, body, subject)
      @name = name
      @mail = mail
      @date = date
      @body = body
      @subject = subject
    end

    def to_line
      [name, mail, date, body, subject].join('<>') + "\n"
    end

    def id
      return nil unless date =~ %r{ ID:([A-Za-z0-9+/]+)}
      $1
    end

    def date_proper
      date.sub(%r{ ID:[A-Za-z0-9+/]+}, '')
    end
  end
end
