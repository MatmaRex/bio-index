# coding: utf-8

# parts copied wholesale from
# https://github.com/MatmaRex/misc-scripts/blob/master/zajawki%20biolodzy.rb

def extract_lifetime plain
	msc = %w[kotek stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia]
	msc2 = %w[kotek styczeń luty marzec kwiecień maj czerwiec lipiec sierpień wrzesień październik listopad grudzień]
	msc3 = %w[kotek I II III IV V VI VII VIII IX X XI XII]

	data_regex = /
		(\d{1,2})(?:-ego|-go|\.|) \s+
		(#{(msc+msc2+msc3).join '|'}|\d{1,2}) \s+
		(\d{3,4})
	/x

	data_ur_regex = /(?:ur\.?|urodzon[ya])\s*#{data_regex}/
	data_zm_regex = /(?:zm\.?|zmarł[ya]?)\s*#{data_regex}/
	zasieg_regex = /#{data_regex}\s*[-–—]\s*#{data_regex}/

	data_sanitize = lambda do |mt|
		_,d,m,y = *mt
		m = msc.index(m) || msc2.index(m) || msc3.index(m) || m.to_i
		d = d.to_i
		y = y.to_i
		if m!=0 and d!=0 and y!=0
			[d,m,y]
		else
			nil
		end
	end

	lifetime = plain.match(zasieg_regex){|mt|
		a = mt.to_a
		ur, zm = a[1..3], a[4..6]
		[data_sanitize.call([nil]+ur), data_sanitize.call([nil]+zm)]
	}
	lifetime ||= [nil, nil]

	lifetime[0] ||= plain.match data_ur_regex, &data_sanitize
	lifetime[1] ||= plain.match data_zm_regex, &data_sanitize

	return lifetime.compact.empty? ? nil : lifetime
end

def parse_intro text
	# find the introductory paragraph
	zaj = text.split(/\r?\n/).grep(/\A(Sir|Dame|ks\.)?\s*('''|{{nihongo\|''')/i)[0]
	return [nil, nil] if !zaj

	# throw away:
	zaj.gsub!(/<ref[^>]+?\/>/, '') # refs
	zaj.gsub!(/<ref.+?(<\/ref>|\Z)/, '') # refs
	
	# this is the point where we haven't killed lifetime data yet
	lifetime = extract_lifetime zaj
	
	true while zaj.gsub!(/\s*\([^()]+\)/, '') # parentheses (lifetime etc.), including nested
	zaj.gsub!(/\s*\\{\{.+?\}\}/, '') # templates
	zaj.sub!(/\A.*'''(.+?)'''/, '') # bolded article name and everything prior
	zaj.sub!(/(\S{3,}\.)\s+.+/, '\1') # everything after the first sentence; try to grasp abbreviations
	zaj.sub!(/\.\s*\Z/, '') # (final full stop)
	zaj.gsub!(/\[\[([^\|\]]+\||)([^\|\]]+)\]\]/, '\2') # links
	zaj.sub!(/\A\W+/, '') # any non-word characters left at the beginning
	
	return [lifetime, zaj]
end

if __FILE__ == $0
	require 'sunflower'
	s = Sunflower.new.login
	# read from stdin
	list = s.make_list 'pages', readlines.map{|ln| ln.strip.encode('utf-8')}
	intros = list.pages.each do |p|
		lifetime, intro = parse_intro(p.text)
		puts "#{p.title} - #{intro}"
	end
end
