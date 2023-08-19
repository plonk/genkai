require 'json'

class EmojiAnnotator
  def initialize
    # emoji-test.json のスキーマ。
    # [{
    #   "cp_text": "1F600",
    #   "status": "fully-qualified",
    #   "cp": "😀",
    #   "ver": "E1.0",
    #   "desc": "grinning face"
    # }, ...]
    #
    # anno.json のスキーマ。
    # [{
    #   "cp": "{",
    #   "annotation": "開き波括弧"
    # }, ...]

    emoji_test_json = File.join(File.dirname(__FILE__), 'emoji-test.json')
    anno_json       = File.join(File.dirname(__FILE__), 'anno.json')
    @emoji_db       = File.open(emoji_test_json, 'r') { JSON.load(_1) }
    @anno_db        = File.open(anno_json, 'r') { JSON.load(_1) }
  end

  def annotate(text)
    output = []
    while text.size > 0
      info = first_char_info(text)
      if info
        anno_info = get_annotation(info['cp'])
        if anno_info
          output << [:annotated, info['cp'], anno_info['annotation']]
        else
          output << [:unannotated, info['cp']]
        end

        text = text[info['cp'].size .. -1]
      else
        if output[-1] && output[-1][0] == :unannotated
          output[-1][1].concat(text[0])
        else
          output << [:unannotated, text[0]]
        end
        text = text[1..-1]
      end
    end
    return output
  end

  alias_method :call, :annotate

  private
  def get_annotation(cp)
    # U+FE0F が付いている場合は省いて検索する。
    cp = cp.gsub(/\u{fe0f}/, '')
    return @anno_db.find { |row| row['cp'] == cp }
  end

  def first_char_info(str)
    # 最長マッチする合法な絵文字シーケンスに関する情報を返す。
    return @emoji_db.select { |row| str.start_with?(row['cp']) }&.max_by { _1['cp'].size }
  end
end

if __FILE__ == $0
  annotator = EmojiAnnotator.new
  pp annotator.annotate("hello 📨👀🤔🤔🤔🤔🤔 please read")
end
