require_relative 'test_common'
require_relative 'authentication_information'

include Genkai

raise unless AuthenticationInformation.valid_password?('') == false
raise unless AuthenticationInformation.valid_password?(' ') == true
raise unless AuthenticationInformation.valid_password?('a') == true
raise unless AuthenticationInformation.valid_password?("\x7f") == false # DEL
raise unless AuthenticationInformation.valid_password?("\x08") == false # BS
raise unless AuthenticationInformation.valid_password?('abc123@,.[]') == true
raise unless AuthenticationInformation.valid_password?('あいうえお') == false
raise unless AuthenticationInformation.valid_password?('123456789012345678901234567890') == true
raise unless AuthenticationInformation.valid_password?('1234567890123456789012345678901') == false


puts 'all tests passed'
