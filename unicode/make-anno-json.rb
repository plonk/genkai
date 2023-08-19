require 'nokogiri'

files = ['ja.xml', 'ja-derived.xml']
data = [] 

files.each do |file|
  doc = File.open(file, 'r') { Nokogiri.parse(_1) }
  doc.css('ldml > annotations > annotation').each do |node|
    if node.attr('type') == 'tts'
      #puts "#{node.attr('cp')} #{node.attr('cp').codepoints.inspect} #{node.text}"
      data << { cp: node.attr('cp'), annotation: node.text }
    end
  end
end

require 'json'
puts JSON.pretty_generate(data)
