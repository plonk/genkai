.PHONY: clean all

all: emoji-test.json anno.json

clean:
	rm -f anno.json emoji-test.json ja.xml ja-derived.xml emoji-test.txt

emoji-test.json: emoji-test.txt
	bundle exec ruby make-emoji-test-json.rb > emoji-test.json

anno.json: ja.xml ja-derived.xml
	bundle exec ruby make-anno-json.rb > anno.json

ja.xml:
	wget "https://raw.githubusercontent.com/unicode-org/cldr/master/common/annotations/ja.xml"

ja-derived.xml:
	wget "https://raw.githubusercontent.com/unicode-org/cldr/master/common/annotationsDerived/ja.xml" -O ja-derived.xml

emoji-test.txt:
	wget "http://unicode.org/Public/emoji/15.0/emoji-test.txt"
