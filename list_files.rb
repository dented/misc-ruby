require 'find'

files = {}
Find.find('.') do |f|
  files[f] = File::size?(f) if (f != '.' && f != '..')
end

sorted = files.sort_by {|k,v| v}.reverse
sorted.each do |k,v|
  puts "File: #{k} - Size: #{v}"
end