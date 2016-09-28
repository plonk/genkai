class String
  def to_utf8
    encode('UTF-8')
  end

  def to_sjis
    encode('CP932')
  end

  def as_utf8
    dup.force_encoding('UTF-8')
  end

  def as_sjis
    dup.force_encoding('CP932')
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
end

require_relative 'post_builder'

class Time
  def to_nichan
    Genkai::PostBuilder.format_date(self)
  end
end
