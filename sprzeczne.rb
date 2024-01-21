# coding: utf-8
require 'json'
require './roman.rb'
require 'pp'

class Numeric
	def sign
		self.zero? ? 0 : self/self.abs
	end
end

kat = Marshal.load File.binread 'savepoint-lifetime.marshal'
noty = JSON.parse File.binread 'items.json'

kat = Hash[ kat.map{|h| [ h[:title], h[:lifetime] ] } ]
noty = Hash[ noty.map{|t, l, _| [t, l] } ]

# $stderr.puts "total: kat=#{kat.length}, noty=#{noty.length}"

# step 1: basic comparison
# throw away exactly same or clearly missing data
confl = (kat.keys + noty.keys).sort.uniq.map{|k|
	ar = [kat[k], noty[k]].map{|yrs| yrs && yrs.gsub(/[-–—−=]|&[mn]dash;/, '-').gsub(/\s*w(\.|iek|)| n\.e\.?|ok.?/, '').strip }
	if ar.compact.length == 0 || ar.compact.uniq.length == 1
		nil # pass
	elsif !ar[0] and ar[1] # missing in cat
		[k, nil, ar[1]]
	elsif !ar[1] and ar[0] # missing in index
		nil
	elsif ar.compact.uniq.length == 2
		[k] + ar
	else
		raise "shouldn't happen #{ar.inspect}"
	end
}.compact

# bleh
confl.reject!{|t, a, b| !b[/\d/] || b=="1583(?" }

# $stderr.puts "#{confl.length} left after basic check"

# step 2: actual parsing and comparison
out = []
parse_one = lambda{|y|
	pne = y.index(/p\.?n\.?e/) ? -1 : 1
	case y
	when /\d+/;   y[/\d+/].to_i * pne
	when /[IVX]+/; y[/[IVX]+/].to_roman * pne
	else; nil
	end
}
parse_yrs = lambda{|yrs|
	case yrs
	when /ur?|\*|or/
		[ parse_one.call(yrs), nil ]
	when /zm?|†/
		[ nil, parse_one.call(yrs) ]
	when /-/
		parsed = yrs.split('-').map{|a| parse_one.call(a) }
		if parsed[0] && parsed[1] && parsed[0] > 100 && parsed[1] < -100
			# assume that the p.n.e. should apply to both dates
			parsed[0] = -parsed[0].abs
		end
		parsed
	when /^(?:\d+|[IVX]+)\s*(p\.?n\.?e\.?)?$/
		[ parse_one.call(yrs) ] # single value
	when nil
		[nil] # missing in cat
	else
		raise '!!!'+yrs
	end
}
in_century = lambda{|yr, cent|
	return false if yr.sign != cent.to_i.sign
	yr = yr.abs; cent = cent.abs; 
	return yr.between?((cent-1).to_i*100+1, cent.to_i*100)
}
do_compare = lambda{|a, b, mode, title|
	if (a && !b) || (b && !a)
		# missing in index or category
		['missing', title, mode, a, b]
	else # a && b
		if a != b
			if (RomanNumeral === a && RomanNumeral === b) || (Integer === a && Integer === b)
				['conflict', title, mode, a, b]
			else
				# try matching centuries
				cent = [a, b].find{|x| RomanNumeral === x }
				yr = [a, b].find{|x| Integer === x }
				if in_century.call(yr, cent)
					# more precision in index or category
					['precision', title, mode, a, b]
				else
					['conflict', title, mode, a, b]
				end
			end
		end
	end
}
confl.each{|title, a, b|
	a = parse_yrs.call(a);
	b = parse_yrs.call(b);
	
	if b.length == 2 && a.length == 2
		out << do_compare.call(a[0], b[0], 'birth', title)
		out << do_compare.call(a[1], b[1], 'death', title)
	elsif b.length == 1 && a.length == 1
		# only one number provided, ambiguous whether it's the birth date, death date, or both
		out << do_compare.call(a[0], b[0], 'birth (probably)', title)
	else
		# only one number provided on one side, two on the other
		out << do_compare.call(a[0], b[0], 'birth (maybe)', title)
		out << do_compare.call(a[1]||a[0], b[1]||b[0], 'death (maybe)', title)
	end
}

out.compact!
out.sort! # by type, title, birth/death

fmt = lambda{|yr|
	yr.nil? ? '—' : [yr.abs.to_s, (RomanNumeral===yr ? 'w.' : nil), yr<0 ? 'p.n.e.' : nil ].compact.join(' ')
}

fmt_lines = lambda{|out|
	lines = out.map{|type, title, bd, a, b|
		bd = bd[0] == ?b ? 'ur.' : 'zm.'
		"|-\n| [[#{title}]] || #{bd} || #{fmt.call a} || #{fmt.call b}"
	}
	lines.each_slice(30).map.with_index{|lns, i|
		<<-EOF.gsub(/\t/, '')
		== #{i+1} ==
		{| class=wikitable
		! Osoba !!  !! wg kat. !! wg not
		#{lns.join "\n"}
		|}

		EOF
	}
}

puts 'Konflikty pomiędzy kategoryzacją (daty z lewej) a notami biograficznymi (z prawej).'
puts ''
puts '<div class=hlist>__TOC__</div>'
puts ''
puts '= Konflikty ='
puts fmt_lines.call out.select{|a| a[0] == 'conflict' }
puts '= Brakujące dane ='
puts fmt_lines.call out.select{|a| a[0] == 'missing' }
# puts '= Niepełna precyzja ='
# puts fmt_lines.call out.select{|a| a[0] == 'precision' }
