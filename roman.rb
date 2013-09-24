# coding: utf-8
require 'roman'

# monkey-patch for roman 0.2.0
def RomanNumeral.from_integer(int)
	return "-#{(-int).to_roman}" if int < 0
	return "" if int == 0
	RomanNumeral::ROMAN_VALUES_ASSOC.each do |(i, v)|
		return(i + from_integer(int-v)) if v <= int
	end
end
