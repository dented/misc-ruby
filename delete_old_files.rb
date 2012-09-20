require 'find'
require 'date'

files = {}
six_months = (Date.today - 180).to_time
Find.find('.') do |f|
  if(f != '.' && f != '..' && File.file?(f) && !f.include?('git'))
    if File::mtime(f) < six_months
      File::delete f
    else
      # File.open("a_file", "w") do |f|
      #     f.write "some data"
      # end
    end
  end
end