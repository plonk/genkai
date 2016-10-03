# frozen_string_literal: true

# 配列の要素に番号を振るクラス。
class NumberedElement
  class << self
    def to_numbered_elements(array, first_number = 1)
      array.map.with_index(first_number) do |elt, i|
        new(elt, i)
      end
    end
  end

  attr_reader :number, :object

  def initialize(object, number)
    @object = object
    @number = number
  end

  def method_missing(message, *args)
    @object.__send__(message, *args)
  end

  # TODO: 書き方がわからない。
  # def respond_to_missing?
  # end
end
