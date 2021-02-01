require_relative 'application'

raise unless Genkai.increment_subject('第2回うんちっち大会スレその1') == '第2回うんちっち大会スレその2'
raise unless Genkai.increment_subject('第2回うんちっち大会スレその1ぽよ') == '第2回うんちっち大会スレその2ぽよ'
raise unless Genkai.increment_subject('汚定地避難所1') == '汚定地避難所2'
raise unless Genkai.increment_subject('汚定地避難所99') == '汚定地避難所100'
raise unless Genkai.increment_subject('汚定地避難所') == '汚定地避難所2'

puts 'all tests passed'
