# frozen_string_literal: true

# 文字列をエスケープするメソッド。
module StringHelpers
  ESCAPE_TABLE = { '<' => '&lt;', '>' => '&gt;', '&' => '&amp;' }.freeze
  UNESCAPE_TABLE = ESCAPE_TABLE.invert.freeze

  def escape_field(str)
    str.gsub(/<|>|&(?!#\d{0,7};)/) { |char| ESCAPE_TABLE[char] }
  end
  module_function :escape_field

  def unescape_field(str)
    selection = UNESCAPE_TABLE.keys.map { |s| Regexp.escape(s) }.join('|')
    str.gsub(/#{selection}/) { |entity| UNESCAPE_TABLE[entity] }
  end
  module_function :unescape_field

  def escape_1001(str)
    escape_field(str).gsub("\n", "<br>\n")
  end
  module_function :escape_1001

  def unescape_1001(str)
    unescape_field(str.gsub("<br>\n", "\n"))
  end
  module_function :unescape_1001
end
