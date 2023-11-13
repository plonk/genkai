# frozen_string_literal: true

require 'json'

module Genkai
  # DATファイルの一行で表わされるレスを表わすクラス。
  class Post
    class << self
      def from_line(str, number = nil)
        new(*str.chomp.split('<>', 5), number)
      end
    end

    attr :number
    attr_accessor :date, :subject
    attr_reader :name, :mail, :body

    def initialize(name, mail, date, body, subject, number = nil)
      @name = name
      @mail = mail
      @date = date
      @body = body
      @subject = subject
      @number = number
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

    def to_h
      { name: name, mail: mail, date: date, body: body, subject: subject, number: number }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
