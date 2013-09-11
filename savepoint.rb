class SavePoint
end
class << SavePoint
	def here! sp=nil
		@counter ||= 0
		@counter += 1
		
		fname = "savepoint-#{sp || @counter}.marshal"
		
		if File.exist? fname
			data = Marshal.load File.binread fname
		else
			data = yield
			File.open(fname, 'wb'){|f| f.write Marshal.dump data }
		end
		
		return data
	end
end
