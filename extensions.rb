# frozen_string_literal: true

# 文字コード変換用のメソッド。
class String
  def to_utf8
    encode('UTF-8')
  end

  def to_sjis
    encode('CP932')
  end

  def to_utf8!
    encode!('UTF-8')
  end

  def to_sjis!
    encode!('CP932')
  end

  def as_utf8
    dup.force_encoding('UTF-8')
  end

  def as_sjis
    dup.force_encoding('CP932')
  end
end

# ファイルパス作成用のメソッド。
class String
  def /(other)
    File.join(self, other)
  end
end

class Object
  def blank?
    case self
    when String then empty?
    when nil then true
    else false
    end
  end

  def true?
    self ? true : false
  end
end

require_relative 'post_builder'

# 日付を2ちゃんねる形式の文字列に変換する。
class Time
  def to_nichan
    Genkai::PostBuilder.format_date(self)
  end
end
