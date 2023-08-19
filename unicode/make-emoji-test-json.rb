require 'json'

$db = []

File.read('emoji-test.txt').each_line do |line|
  if line =~ /^([0-9A-F]+(?: [0-9A-F]+)*)\s+;\s+(fully-qualified|minimally-qualified|unqualified)\s+#\s+(\S+)\s+(E\d+\.\d+)\s+(.*)$/
    #p [$1, $2, $3, $4, $5]
    $db << { cp_text: $1, status: $2, cp: $3, ver: $4, desc: $5 }
  else
    #p line
  end
end

puts JSON.pretty_generate($db)
